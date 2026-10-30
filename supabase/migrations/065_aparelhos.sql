-- ============================================================
-- Feira Comercial — 065: Reconhecer o aparelho de um burlão
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
-- Precisa das migrações 050/051 (travão e Radar), 053 e 064.
--
-- O burlão suspenso cria outra conta, com outro e-mail e outro número, mas no
-- MESMO telemóvel. O site guarda uma marca do aparelho (um código ao acaso, sem
-- fotos, contactos nem nada pessoal) e a base de dados compara-a.
--
--  1) CONTA NOVA NO APARELHO DE UMA CONTA SUSPENSA
--       • conta com menos de 30 dias, sem coroa e ainda não revista pela equipa:
--         fica logo EM REVISÃO (travão: não publica nem envia mensagens) e o
--         administrador e os Ajudantes recebem aviso no sino;
--       • outras contas (antigas, com coroa ou já revistas): só aviso no sino.
--  2) UMA CONTA É SUSPENSA → as outras contas no mesmo aparelho seguem a mesma
--     regra: as novas ficam em revisão, as outras geram aviso no sino.
--  3) RADAR (Painel → Suspeitos): "Usa o mesmo aparelho de uma conta suspensa"
--     (+50) e "Aparelho e rede iguais aos de uma conta suspensa" (+15, para quem
--     apagou os dados do navegador).
-- A equipa tira sempre a revisão (Suspeitos / Contas). Um aparelho pode ser
-- emprestado ou vendido: por isso a conta fica em revisão, não apagada.
-- Os registos com mais de 1 ano são apagados sozinhos.
-- ============================================================

create table if not exists public.aparelhos (
  conta     uuid not null references public.perfis(id) on delete cascade,
  token     text not null check (token ~ '^[A-Za-z0-9_-]{16,64}$'),
  impressao text check (impressao ~ '^[a-f0-9]{16,64}$'),   -- características do aparelho (resumo)
  rede      text check (rede ~ '^[a-f0-9]{32}$'),            -- resumo da rede (nunca o endereço)
  primeiro  timestamptz not null default now(),
  ultimo    timestamptz not null default now(),
  vezes     int not null default 1,
  primary key (conta, token)
);
create index if not exists aparelhos_token_idx on public.aparelhos (token);
create index if not exists aparelhos_impressao_idx on public.aparelhos (impressao, rede);
alter table public.aparelhos enable row level security;    -- só pelas funções abaixo
revoke all on public.aparelhos from anon, authenticated;

-- cada par (conta, conta suspensa) só gera um aviso
create table if not exists public.aparelhos_avisos (
  conta    uuid not null references public.perfis(id) on delete cascade,
  suspensa uuid not null references public.perfis(id) on delete cascade,
  criado   timestamptz not null default now(),
  primary key (conta, suspensa)
);
alter table public.aparelhos_avisos enable row level security;
revoke all on public.aparelhos_avisos from anon, authenticated;

-- novos tipos de aviso no sino
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo in (
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio',
  'marco_publicacao','marco_seguidor','marco_mensagem','gratis_fim','mensalidade_fim',
  'oferta_guardado','oferta_loja','resumo_semanal','lojas_hoje','travao','numero_proibido','cobranca',
  'gosto_story','numero_denunciado','numero_no_perfil','mesmo_aparelho'));

-- ---------- conta no aparelho de uma conta suspensa: travão (se nova) ou aviso ----------
-- Conta com menos de 30 dias, sem coroa e nunca revista pela equipa: fica EM REVISÃO.
-- As outras: só aviso no sino. No máximo um aviso por conta a cada 7 dias.
create or replace function public.travar_ou_avisar_aparelho(p_conta uuid, p_suspensa uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  c perfis%rowtype;
  nome_s text := coalesce((select full_name from perfis where id = p_suspensa), 'uma conta suspensa');
  ja boolean;
  sistema constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';   -- conta da Equipa Feira Comercial
begin
  select * into c from perfis where id = p_conta;
  if not found or coalesce(c.bloqueado, false) or c.role in ('admin', 'equipa', 'ajudante') then return; end if;
  ja := exists (select 1 from aparelhos_avisos where conta = c.id and criado > now() - interval '7 days');
  insert into aparelhos_avisos (conta, suspensa) values (c.id, p_suspensa) on conflict do nothing;
  if c.created_at > now() - interval '30 days' and c.verificada_em is null and c.revisto_em is null then
    update perfis set bloqueado = true,
           bloqueio_motivo = 'Em revisão: esta conta foi aberta num aparelho de uma conta suspensa. A equipa vai analisar em breve.'
     where id = c.id;
    insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
    values (sistema, 'travao_aparelho', c.id, p_suspensa, 'Aberta no aparelho de uma conta suspensa');
    insert into notificacoes (user_id, autor_id, tipo, texto)
    select p.id, c.id, 'travao', coalesce(c.full_name, 'Uma conta') || ' ficou em revisão: aberta no aparelho de ' || nome_s || ' (suspensa)'
      from perfis p where p.role in ('admin', 'ajudante');
  elsif not ja then
    insert into notificacoes (user_id, autor_id, tipo, texto)
    select p.id, c.id, 'mesmo_aparelho', nome_s from perfis p where p.role = 'admin';
  end if;
end $$;
revoke all on function public.travar_ou_avisar_aparelho(uuid, uuid) from public, anon, authenticated;

-- ---------- registar o aparelho (o site chama isto ao abrir, no máximo 2x por dia) ----------
create or replace function public.registar_aparelho(p_token text, p_impressao text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  eu perfis%rowtype;
  rede_h text;
  s record;
begin
  select * into eu from perfis where id = auth.uid();
  if not found then return; end if;
  if coalesce(p_token, '') !~ '^[A-Za-z0-9_-]{16,64}$' then return; end if;
  if coalesce(p_impressao, '') !~ '^[a-f0-9]{16,64}$' then p_impressao := null; end if;
  -- resumo da rede (primeiro endereço do pedido); o endereço em si não é guardado
  begin
    rede_h := md5('fc-rede:' || nullif(btrim(split_part(coalesce(
      current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1)), ''));
  exception when others then rede_h := null;
  end;

  insert into aparelhos as a (conta, token, impressao, rede)
  values (eu.id, p_token, p_impressao, rede_h)
  on conflict (conta, token) do update
    set ultimo = now(), vezes = a.vezes + 1,
        impressao = coalesce(excluded.impressao, a.impressao),
        rede = coalesce(excluded.rede, a.rede);

  delete from aparelhos where ultimo < now() - interval '1 year';

  if eu.role in ('admin', 'equipa', 'ajudante') or coalesce(eu.bloqueado, false) then return; end if;

  -- o mesmo aparelho já foi usado por uma conta suspensa?
  select q.id, q.full_name into s
    from aparelhos b join perfis q on q.id = b.conta
   where b.token = p_token and b.conta <> eu.id and coalesce(q.bloqueado, false)
     and not exists (select 1 from aparelhos_avisos v where v.conta = eu.id and v.suspensa = q.id)
   order by b.ultimo desc limit 1;
  if s.id is null then return; end if;
  perform travar_ou_avisar_aparelho(eu.id, s.id);
end $$;
revoke all on function public.registar_aparelho(text, text) from public, anon;
grant execute on function public.registar_aparelho(text, text) to authenticated;

-- ---------- uma conta é suspensa: avisar das outras contas no mesmo aparelho ----------
create or replace function public.avisar_contas_mesmo_aparelho()
returns trigger language plpgsql security definer set search_path = public as $$
declare o uuid;
begin
  for o in
    select distinct b.conta
      from aparelhos a join aparelhos b on b.token = a.token and b.conta <> a.conta
     where a.conta = new.id
       and not exists (select 1 from aparelhos_avisos v where v.conta = b.conta and v.suspensa = new.id)
  loop
    perform travar_ou_avisar_aparelho(o, new.id);
  end loop;
  return new;
end $$;
revoke all on function public.avisar_contas_mesmo_aparelho() from public, anon, authenticated;
drop trigger if exists trg_avisar_contas_mesmo_aparelho on public.perfis;
create trigger trg_avisar_contas_mesmo_aparelho after update of bloqueado on public.perfis
  for each row when (new.bloqueado is true and old.bloqueado is distinct from true)
  execute function public.avisar_contas_mesmo_aparelho();

-- ---------- Radar: sinais do aparelho ----------
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
      + (case when n.ap_mesmo then 50 when n.ap_parecido then 15 else 0 end)
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

-- ver se ficou bem: deve mostrar 4 linhas
select p.proname as funcao from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('registar_aparelho', 'travar_ou_avisar_aparelho', 'avisar_contas_mesmo_aparelho', 'admin_suspeitos')
 order by 1;
