-- ============================================================
-- Feira Comercial — 066: Correções da revisão de 31/10/2026
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
-- Precisa das migrações 051, 061, 064 e 065.
--
-- 1) NÚMEROS INOCENTES: quando uma conta é suspensa, a lista de burlas guarda os
--    números do PERFIL dela e também os números que ela ESCREVEU nas mensagens.
--    Nas mensagens, um burlão pode escrever o número de outra pessoa (ex.: "ligue
--    para a Loja X, 84…"). Esse número inocente passava a ter, no perfil da Loja X,
--    o aviso vermelho público e sem botões Ligar/WhatsApp, e a Loja X não podia
--    pô-lo numa conta nova.
--    Agora cada número da lista guarda de onde veio (origem):
--      perfil   → do perfil da conta suspensa        → aviso público e bloqueio
--      mensagem → escrito nas mensagens dela          → só aviso à equipa e Radar
--      (vazio)  → denúncias da comunidade ou equipa   → aviso público e bloqueio
--    No chat, quem envia o PRÓPRIO número (o do seu perfil) já não leva o aviso
--    vermelho por causa de um número que só apareceu nas mensagens de um burlão.
-- 2) APARELHOS: a limpeza dos registos com mais de 1 ano passa a usar um índice
--    (antes percorria a tabela toda a cada registo).
-- 3) RADAR: "aparelho e rede iguais aos de uma conta suspensa" vale 5 pontos (era
--    15) e só conta aparelhos de burlões usados nos últimos 30 dias. Muitos
--    telemóveis iguais partilham a mesma rede móvel, o que dava falsos alarmes.
-- ============================================================

-- ---------- 1) Origem dos números da lista ----------
alter table public.numeros_proibidos add column if not exists origem text;
alter table public.numeros_proibidos drop constraint if exists numeros_proibidos_origem_check;
alter table public.numeros_proibidos add constraint numeros_proibidos_origem_check
  check (origem is null or origem in ('perfil', 'mensagem'));

-- números que já estão na lista: do perfil da conta suspensa ou só das mensagens
update public.numeros_proibidos np
   set origem = case when exists (select 1 from perfis x where x.id = np.conta
                                    and np.numero = any (numeros_em(coalesce(x.phone, '') || ' ' || coalesce(x.whatsapp, ''))))
                     then 'perfil' else 'mensagem' end
 where np.conta is not null and np.origem is null;

-- uma conta é suspensa: primeiro os números do perfil, depois os das mensagens
create or replace function public.proibir_numeros_de(p_uid uuid, p_motivo text)
returns int language plpgsql security definer set search_path = public as $$
declare n int; m int;
begin
  insert into numeros_proibidos (numero, conta, motivo, origem)
  select distinct x, p_uid, left(p_motivo, 200), 'perfil'
    from (select unnest(numeros_em(coalesce(p.phone, '') || ' ' || coalesce(p.whatsapp, ''))) x from perfis p where p.id = p_uid) s
   where x ~ '^8[2-7][0-9]{7}$'
  on conflict (numero) do nothing;
  get diagnostics n = row_count;
  insert into numeros_proibidos (numero, conta, motivo, origem)
  select distinct x, p_uid, left(p_motivo, 200), 'mensagem'
    from (
      select unnest(numeros_em(m.content)) x from messages m where m.sender_id = p_uid and m.created_at > now() - interval '60 days'
      union all
      select unnest(numeros_em(a.content)) from mensagens_apagadas a where a.sender_id = p_uid and a.enviada_em > now() - interval '60 days'
    ) s
   where x ~ '^8[2-7][0-9]{7}$'
  on conflict (numero) do nothing;
  get diagnostics m = row_count;
  return n + m;
end $$;
revoke execute on function public.proibir_numeros_de(uuid, text) from public, anon, authenticated;

-- aviso público e bloqueio: só números do perfil de um burlão, de denúncias ou da equipa
create or replace function public.contas_numero_burla(p_ids uuid[])
returns table (id uuid)
language sql stable security definer set search_path = public as $$
  select p.id from perfis p
   where p.id = any (p_ids[1:300])
     and coalesce(p.role, '') not in ('admin', 'equipa')
     and exists (select 1 from numeros_proibidos np
                  where np.numero = any (numeros_do_perfil(p.phone, p.whatsapp))
                    and np.conta is distinct from p.id
                    and coalesce(np.origem, '') <> 'mensagem');
$$;
revoke all on function public.contas_numero_burla(uuid[]) from public;
grant execute on function public.contas_numero_burla(uuid[]) to anon, authenticated;

create or replace function public.impedir_numero_burla()
returns trigger language plpgsql security definer set search_path = public as $$
declare novos text[];
begin
  if coalesce(auth.role(), '') = 'service_role' then return new; end if;
  if coalesce(current_setting('fc.permitir_numero', true), '') = '1' then return new; end if;
  if new.role in ('admin', 'equipa') then return new; end if;
  novos := numeros_do_perfil(new.phone, new.whatsapp);
  if tg_op = 'UPDATE' then
    novos := array(select unnest(novos) except select unnest(numeros_do_perfil(old.phone, old.whatsapp)));
  end if;
  if coalesce(array_length(novos, 1), 0) > 0 and exists (
       select 1 from numeros_proibidos np
        where np.numero = any (novos) and np.conta is distinct from new.id
          and coalesce(np.origem, '') <> 'mensagem') then
    raise exception 'Este número está na lista de burlas da Feira Comercial. Use outro número ou fale com a equipa.'
      using errcode = 'P0001', hint = 'numero_burla';
  end if;
  return new;
end $$;
revoke all on function public.impedir_numero_burla() from public, anon, authenticated;

-- a tentativa só conta para números que bloqueiam (os mesmos de cima)
create or replace function public.avisar_tentativa_numero(p_numero text, p_criar_conta boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare n text := (numeros_em(p_numero))[1]; eu uuid := auth.uid();
begin
  if n is null then return; end if;
  if not exists (select 1 from numeros_proibidos where numero = n and conta is distinct from eu
                  and coalesce(origem, '') <> 'mensagem') then return; end if;
  if exists (select 1 from notificacoes where tipo = 'numero_no_perfil' and texto like '%' || n || '%'
              and criado > now() - interval '1 day') then return; end if;
  insert into notificacoes (user_id, autor_id, tipo, texto)
  select a.id, eu, 'numero_no_perfil',
         case when p_criar_conta or eu is null then 'tentou criar conta com o número ' || n
              else 'tentou pôr no perfil o número ' || n end
    from perfis a where a.role = 'admin';
end $$;
revoke all on function public.avisar_tentativa_numero(text, boolean) from public;
grant execute on function public.avisar_tentativa_numero(text, boolean) to anon, authenticated;

-- a equipa continua a ser avisada de TODOS (decide ela); o texto diz de onde veio o número
create or replace function public.avisar_perfis_com_numero()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into notificacoes (user_id, autor_id, tipo, texto)
  select a.id, p.id, 'numero_no_perfil',
         'tem no perfil o número ' || new.numero ||
         case when new.origem = 'mensagem'
              then ', que uma conta suspensa escreveu nas mensagens (pode ser de outra pessoa — confirme)'
              else ', que entrou agora na lista' end
    from perfis p
    join perfis a on a.role = 'admin'
   where p.id is distinct from new.conta
     and coalesce(p.role, '') not in ('admin', 'equipa')
     and new.numero = any (numeros_do_perfil(p.phone, p.whatsapp));
  return new;
end $$;
revoke all on function public.avisar_perfis_com_numero() from public, anon, authenticated;

-- chat: quem envia o seu próprio número não leva o aviso vermelho por um número que só
-- apareceu nas mensagens de um burlão (os outros casos ficam iguais)
create or replace function public.verificar_mensagem()
returns trigger language plpgsql security definer set search_path = public as $$
declare meus text[];
begin
  new.alerta := null;
  if coalesce(new.content, '') !~ '8[2-7]' then return new; end if;
  if exists (select 1 from perfis where id = new.sender_id and role in ('admin', 'equipa', 'ajudante')) then return new; end if;
  select numeros_do_perfil(phone, whatsapp) into meus from perfis where id = new.sender_id;
  if exists (select 1 from numeros_proibidos np
              where np.numero = any (numeros_em(new.content)) and np.conta is distinct from new.sender_id
                and not (np.origem = 'mensagem' and np.numero = any (coalesce(meus, '{}')))) then
    new.alerta := 'numero_proibido';
    if not exists (select 1 from notificacoes where tipo = 'numero_proibido' and autor_id = new.sender_id and criado > now() - interval '1 day') then
      insert into notificacoes (user_id, autor_id, tipo, texto)
      select p.id, new.sender_id, 'numero_proibido', 'enviou um número de uma conta suspensa'
        from perfis p where p.role = 'admin';
    end if;
  end if;
  return new;
end $$;

-- ---------- 2) Aparelhos: limpeza com índice ----------
create index if not exists aparelhos_ultimo_idx on public.aparelhos (ultimo);

-- ---------- 3) Radar: "aparelho e rede iguais" pesa menos ----------
create or replace function public.admin_suspeitos(p_dias int default 7)
returns table (id uuid, nome text, avatar_url text, tipo text, criada timestamptz, verificada boolean, pontos int, motivos text[])
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 30)));
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  with msgs as (
    select m.sender_id, m.receiver_id, m.created_at, m.content, m.alerta from messages m where m.created_at > desde
    union all
    select a.sender_id, a.receiver_id, a.enviada_em, a.content, null from mensagens_apagadas a where a.enviada_em > desde
  ),
  sinais as (
    select sender_id as uid,
           count(*) filter (where sinal_burla(content) = 'codigo')    as codigo,
           count(*) filter (where sinal_burla(content) = 'adiantado') as adiantado,
           count(*) filter (where sinal_burla(content) = 'premio')    as premio,
           count(*) filter (where sinal_burla(content) = 'equipa')    as equipa,
           count(*) filter (where alerta = 'numero_proibido')         as numero,
           count(*) filter (where content ~* '(https?://|www\.)' and content !~* 'feira-comercial\.com') as links
      from msgs group by sender_id
  ),
  contactos as (   -- conversas começadas por cada conta no período
    select m.sender_id as uid, count(distinct m.receiver_id) as novos,
           count(distinct m.receiver_id) filter (where m.created_at > now() - interval '24 hours') as novos24
      from messages m
     where m.created_at > desde
       and not exists (select 1 from messages r where r.sender_id = m.receiver_id and r.receiver_id = m.sender_id and r.created_at < m.created_at)
       and not exists (select 1 from messages o where o.sender_id = m.sender_id and o.receiver_id = m.receiver_id and o.created_at <= desde)
     group by m.sender_id
  ),
  denuncias as (
    select r.denunciado as uid, count(distinct r.user_id) as n from reclamacoes r
     where r.tipo = 'denuncia' and r.denunciado is not null and r.created_at > now() - interval '30 days' group by r.denunciado
  ),
  bloqs as (
    select b.blocked_id as uid, count(*) as n from bloqueios b where b.created_at > desde group by b.blocked_id
  ),
  aparelho as (   -- o mesmo aparelho (ou o mesmo modelo na mesma rede) de uma conta suspensa
    select a.conta as uid,
           bool_or(exists (select 1 from aparelhos b join perfis q on q.id = b.conta
                            where b.token = a.token and b.conta <> a.conta and coalesce(q.bloqueado, false))) as mesmo,
           bool_or(a.impressao is not null and a.rede is not null and exists (
                     select 1 from aparelhos b join perfis q on q.id = b.conta
                      where b.impressao = a.impressao and b.rede = a.rede and b.conta <> a.conta
                        and b.ultimo > now() - interval '30 days'          -- só aparelhos de burlões usados há pouco
                        and coalesce(q.bloqueado, false))) as parecido
      from aparelhos a where a.ultimo > now() - interval '90 days'
     group by a.conta
  ),
  cand as (
    select uid from sinais union select uid from contactos union select uid from denuncias union select uid from bloqs
    union select uid from aparelho where mesmo or parecido
  ),
  nota as (
    select p.id, p.full_name, p.avatar_url, p.type, p.created_at, p.verificada_em is not null as verif,
           coalesce(s.codigo, 0) codigo, coalesce(s.adiantado, 0) adiantado, coalesce(s.premio, 0) premio,
           coalesce(s.equipa, 0) equipa, coalesce(s.numero, 0) numero, coalesce(s.links, 0) links,
           coalesce(c.novos, 0) novos, coalesce(c.novos24, 0) novos24, coalesce(d.n, 0) denun, coalesce(b.n, 0) bloq,
           (exists (select 1 from numeros_proibidos np
                     where np.numero = any (numeros_em(coalesce(p.phone, '') || ' ' || coalesce(p.whatsapp, '')))
                       and np.conta is distinct from p.id)) num_perfil,
           coalesce(ap.mesmo, false) ap_mesmo, coalesce(ap.parecido, false) ap_parecido
      from cand x join perfis p on p.id = x.uid
      left join sinais s on s.uid = p.id left join contactos c on c.uid = p.id
      left join denuncias d on d.uid = p.id left join bloqs b on b.uid = p.id
      left join aparelho ap on ap.uid = p.id
     where not coalesce(p.bloqueado, false) and coalesce(p.role, 'user') not in ('admin', 'equipa', 'ajudante')
  ),
  pont as (
    select n.*,
      least(100, (
        (case when n.created_at > now() - interval '7 days' then 15 when n.created_at > now() - interval '30 days' then 5 else 0 end)
      + (case when n.novos24 >= 25 then 25 when n.novos24 >= 10 then 15 when n.novos >= 20 then 10 else 0 end)
      + least(30, n.adiantado * 5) + least(30, n.codigo * 10) + least(20, n.premio * 10) + least(30, n.equipa * 15)
      + (case when n.numero > 0 or n.num_perfil then 40 else 0 end)
      + (case when n.links > 0 then 5 else 0 end)
      + least(30, n.denun * 10) + least(20, n.bloq * 5)
      + (case when n.ap_mesmo then 50 when n.ap_parecido then 5 else 0 end)
      ) / (case when n.verif then 2 else 1 end))::int as pts
      from nota n
  )
  select p.id, p.full_name, p.avatar_url, p.type, p.created_at, p.verif, p.pts,
         array_remove(array[
           case when p.created_at > now() - interval '7 days' then
             (select case when d = 0 then 'Conta criada hoje' when d = 1 then 'Conta criada ontem' else 'Conta criada há ' || d || ' dias' end
                from (select greatest(0, hoje_maputo() - dia_maputo(p.created_at)) as d) x) end,
           case when p.ap_mesmo then 'Usa o mesmo aparelho de uma conta suspensa'
                when p.ap_parecido then 'Aparelho e rede iguais aos de uma conta suspensa' end,
           case when p.novos24 >= 10 then 'Começou conversa com ' || p.novos24 || ' pessoas nas últimas 24 h'
                when p.novos >= 20 then 'Começou conversa com ' || p.novos || ' pessoas no período' end,
           case when p.adiantado > 0 then p.adiantado || ' mensagem(ns) a pedir pagamento adiantado' end,
           case when p.codigo > 0 then p.codigo || ' mensagem(ns) a pedir códigos, PIN ou palavra-passe' end,
           case when p.premio > 0 then p.premio || ' mensagem(ns) com prémios falsos' end,
           case when p.equipa > 0 then 'Diz ser da Equipa Feira Comercial (' || p.equipa || 'x)' end,
           case when p.numero > 0 then 'Enviou o número de uma conta suspensa (' || p.numero || 'x)'
                when p.num_perfil then 'Tem no perfil o número de uma conta suspensa' end,
           case when p.links > 0 then 'Enviou links para outros sites (' || p.links || 'x)' end,
           case when p.denun > 0 then p.denun || ' denúncia(s) nos últimos 30 dias' end,
           case when p.bloq > 0 then 'Bloqueada por ' || p.bloq || ' pessoa(s)' end,
           case when p.verif then 'Loja verificada (nota reduzida a metade)' end
         ], null)
    from pont p
    left join radar_dispensas rd on rd.conta = p.id
   where p.pts >= 20 and (rd.conta is null or p.pts > rd.pontos)
   order by p.pts desc
   limit 50;
end $$;


-- ver se ficou bem: deve mostrar 1 linha "origem | t"
select 'origem' as coluna, exists (select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'numeros_proibidos' and column_name = 'origem') as criada;
