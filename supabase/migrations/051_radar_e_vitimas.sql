-- ============================================================
-- 051 — Ferramentas da equipa contra burlas
--   1) Números proibidos: os números M-Pesa/telefone de uma conta suspensa ficam numa lista.
--      Se outra conta os enviar numa mensagem, a mensagem leva um alerta (o cliente vê um
--      aviso vermelho) e a equipa recebe um aviso no sino.
--   2) Limite para contas novas: na 1.ª semana, uma conta só pode começar conversa com
--      15 pessoas novas por dia (responder a quem lhe escreveu não conta).
--   3) Radar de suspeitos: nota de risco 0–100 por conta, com os motivos, para o administrador.
--   4) Avisar as vítimas: depois de suspender, a Equipa avisa todos os que falaram com a conta.
-- ============================================================

-- ---------- utilitários ----------

-- números de Moçambique (82–87 + 7 algarismos, com ou sem +258, espaços ou traços) → '841234567'
create or replace function public.numeros_em(t text)
returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct regexp_replace(m[1], '\D', '', 'g')), '{}')
    from regexp_matches(coalesce(t, ''), '(?:\+?258[\s.-]?)?(8[2-7](?:[\s.-]?\d){7})', 'g') as m
$$;

-- mesma ideia do burlas.js (aviso no chat), aqui para o radar: 'codigo', 'adiantado', 'premio', 'equipa' ou null
create or replace function public.sinal_burla(t text)
returns text language sql immutable as $$
  select case
    when x ~ '(equipa|suporte|apoio|administra\w*|seguranca|moderador\w*)\M.{0,25}\mfeira\M' then 'equipa'
    when x ~ '\m(codigo|cod|code|pin|senha|palavra.?passe|password|otp|token)\M'
     and x ~ '\m(envi|mand|diz|diga|pass|partilh|da-?me|de-?me|confirm|recebe|cheg|escrev|copi|send|give|share|tell)' then 'codigo'
    when x ~ '\m(adiantad\w*|antecipad\w*|caucao|advance|upfront)\M'
      or x ~ '\m(pag|transf|deposit|envi|mand)\w*\M.{0,25}\m(antes|primeiro|metade)\M'
      or x ~ '\m(pag\w*|dar|de|da|mand\w*|envi\w*|transf\w*)\M.{0,15}\msinal\M'
      or x ~ '\mtaxa (de )?(entrega|envio|reserva|transporte|liberta\w*|alfandeg\w*|desalfandeg\w*)' then 'adiantado'
    when x ~ '\m(ganhou|ganhaste|sorteado|premio|sorteio|bonus|prize|winner)\M'
     and x ~ '\m(pag|envi|mand|taxa|codigo|levant|reclam)' then 'premio'
  end
  from (select translate(lower(coalesce(t, '')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') as x) s
$$;

create index if not exists messages_criado_idx on public.messages (created_at);
create index if not exists messages_conversa_idx on public.messages (sender_id, receiver_id, created_at);

-- ---------- 1) Números proibidos ----------

create table if not exists public.numeros_proibidos (
  numero text primary key check (numero ~ '^8[2-7][0-9]{7}$'),
  conta  uuid references public.perfis(id) on delete set null,
  motivo text,
  criado timestamptz not null default now()
);
alter table public.numeros_proibidos enable row level security;   -- só pelas funções abaixo

alter table public.messages add column if not exists alerta text;

-- guarda na lista os números de uma conta suspensa: os do perfil e os que enviou nas mensagens (60 dias)
create or replace function public.proibir_numeros_de(p_uid uuid, p_motivo text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into numeros_proibidos (numero, conta, motivo)
  select distinct x, p_uid, left(p_motivo, 200)
    from (
      select unnest(numeros_em(coalesce(p.phone, '') || ' ' || coalesce(p.whatsapp, ''))) x from perfis p where p.id = p_uid
      union all
      select unnest(numeros_em(m.content)) from messages m where m.sender_id = p_uid and m.created_at > now() - interval '60 days'
      union all
      select unnest(numeros_em(a.content)) from mensagens_apagadas a where a.sender_id = p_uid and a.enviada_em > now() - interval '60 days'
    ) s
   where x ~ '^8[2-7][0-9]{7}$'
  on conflict (numero) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- cada mensagem nova: alerta se tiver um número proibido (de outra conta)
create or replace function public.verificar_mensagem()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.alerta := null;
  if coalesce(new.content, '') !~ '8[2-7]' then return new; end if;
  if exists (select 1 from perfis where id = new.sender_id and role in ('admin', 'equipa', 'ajudante')) then return new; end if;
  if exists (select 1 from numeros_proibidos np
              where np.numero = any (numeros_em(new.content)) and np.conta is distinct from new.sender_id) then
    new.alerta := 'numero_proibido';
    if not exists (select 1 from notificacoes where tipo = 'numero_proibido' and autor_id = new.sender_id and criado > now() - interval '1 day') then
      insert into notificacoes (user_id, autor_id, tipo, texto)
      select p.id, new.sender_id, 'numero_proibido', 'enviou um número de uma conta suspensa'
        from perfis p where p.role = 'admin';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists zz_verificar_mensagem on public.messages;
create trigger zz_verificar_mensagem before insert on public.messages
  for each row execute function public.verificar_mensagem();

-- ninguém tira o alerta de uma mensagem
create or replace function public.proteger_alerta()
returns trigger language plpgsql as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    new.alerta := old.alerta;
  end if;
  return new;
end $$;
drop trigger if exists zz_proteger_alerta on public.messages;
create trigger zz_proteger_alerta before update on public.messages
  for each row execute function public.proteger_alerta();

-- ---------- 2) Limite para contas novas ----------

create or replace function public.limitar_contas_novas()
returns trigger language plpgsql security definer set search_path = public as $$
declare a perfis%rowtype; n int;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return new; end if;
  select * into a from perfis where id = new.sender_id;
  if not found or a.role in ('admin', 'equipa', 'ajudante') or a.verificada_em is not null
     or a.created_at < now() - interval '7 days' then
    return new;
  end if;
  if exists (select 1 from perfis where id = new.receiver_id and role in ('admin', 'equipa', 'ajudante')) then return new; end if;
  -- conversa que já existe (a pessoa escreveu-me, ou eu já lhe tinha escrito) não conta
  if exists (select 1 from messages where sender_id = new.receiver_id and receiver_id = new.sender_id)
     or exists (select 1 from messages where sender_id = new.sender_id and receiver_id = new.receiver_id) then
    return new;
  end if;
  -- conversas começadas por esta conta nas últimas 24 h
  select count(distinct m.receiver_id) into n
    from messages m
   where m.sender_id = new.sender_id and m.created_at > now() - interval '24 hours'
     and not exists (select 1 from messages r where r.sender_id = m.receiver_id and r.receiver_id = m.sender_id and r.created_at < m.created_at)
     and not exists (select 1 from messages o where o.sender_id = m.sender_id and o.receiver_id = m.receiver_id and o.created_at <= now() - interval '24 hours');
  if n >= 15 then
    raise exception 'Conta nova: na primeira semana pode começar conversa com até 15 pessoas novas por dia. Responda a quem já lhe escreveu ou tente amanhã.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_limite_contas_novas on public.messages;
create trigger trg_limite_contas_novas before insert on public.messages
  for each row execute function public.limitar_contas_novas();

-- ---------- avisos no sino ----------

alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto', 'comentario', 'resposta', 'seguir', 'publicacao', 'video', 'gosto_video', 'comentario_video',
  'live', 'avaliacao', 'resposta_avaliacao', 'convite_aceite', 'convite_premio', 'marco_publicacao',
  'marco_seguidor', 'marco_mensagem', 'gratis_fim', 'mensalidade_fim', 'oferta_guardado', 'oferta_loja',
  'resumo_semanal', 'lojas_hoje', 'travao', 'numero_proibido']));

-- ---------- suspender: guarda / liberta os números ----------

create or replace function public.admin_suspender(p_uid uuid, p_suspender boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_uid = auth.uid() then raise exception 'não pode suspender a própria conta'; end if;
  update perfis set bloqueado = p_suspender,
         bloqueio_motivo = case when p_suspender then left(nullif(trim(p_motivo), ''), 300) else null end,
         revisto_em = case when p_suspender then revisto_em else now() end
  where id = p_uid;
  if p_suspender then
    perform proibir_numeros_de(p_uid, coalesce(nullif(trim(p_motivo), ''), 'Conta suspensa'));
  else
    delete from numeros_proibidos where conta = p_uid;
  end if;
end $$;

-- o travão automático também guarda os números (saem se o administrador reativar a conta)
create or replace function public.travao_denuncias()
returns trigger language plpgsql security definer set search_path = public as $$
declare a perfis%rowtype; quantos int; desde timestamptz;
begin
  if new.tipo <> 'denuncia' or new.denunciado is null or new.user_id is null then return null; end if;
  select * into a from perfis where id = new.denunciado;
  if not found or coalesce(a.bloqueado, false) or a.role in ('admin', 'equipa', 'ajudante')
     or a.verificada_em is not null or a.created_at < now() - interval '30 days' then
    return null;
  end if;
  desde := greatest(now() - interval '30 days', coalesce(a.revisto_em, '-infinity'));
  select count(distinct r.user_id) into quantos
    from reclamacoes r join perfis q on q.id = r.user_id
   where r.denunciado = a.id and r.tipo = 'denuncia' and r.created_at >= desde
     and q.created_at < now() - interval '1 day'
     and exists (select 1 from messages mm
                  where (mm.sender_id = r.user_id and mm.receiver_id = a.id)
                     or (mm.sender_id = a.id and mm.receiver_id = r.user_id));
  if quantos < 3 then return null; end if;
  update perfis set bloqueado = true,
         bloqueio_motivo = 'Em revisão: várias pessoas denunciaram esta conta. A equipa vai analisar em breve.'
   where id = a.id;
  perform proibir_numeros_de(a.id, 'Travão automático: ' || quantos || ' denúncias');
  insert into registo_admin (admin_id, acao, conta_a, motivo)
  values ('a73d8f73-5b2c-4f03-9deb-17aa890287dd', 'travao_automatico', a.id, quantos || ' denúncias de pessoas diferentes');
  insert into notificacoes (user_id, autor_id, tipo, texto)
  select p.id, a.id, 'travao', coalesce(a.full_name, 'Uma conta') || ' ficou em revisão: ' || quantos || ' denúncias'
    from perfis p where p.role in ('admin', 'ajudante');
  return null;
end $$;

-- ---------- lista de números (administrador) ----------

create or replace function public.admin_numeros_proibidos()
returns table (numero text, conta uuid, nome text, motivo text, criado timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query select np.numero, np.conta, p.full_name, np.motivo, np.criado
                 from numeros_proibidos np left join perfis p on p.id = np.conta
                order by np.criado desc;
end $$;

create or replace function public.admin_numero_proibido(p_numero text, p_proibir boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare n text := (numeros_em(p_numero))[1];
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if n is null then raise exception 'Número inválido: use um número de Moçambique (82 a 87 + 7 algarismos).' using errcode = 'P0001'; end if;
  if p_proibir then
    insert into numeros_proibidos (numero, motivo) values (n, coalesce(nullif(trim(p_motivo), ''), 'Adicionado pela equipa'))
    on conflict (numero) do nothing;
  else
    delete from numeros_proibidos where numero = n;
  end if;
end $$;

-- ---------- 3) Radar de suspeitos ----------

create table if not exists public.radar_dispensas (
  conta  uuid primary key references public.perfis(id) on delete cascade,
  pontos int not null,
  por    uuid,
  em     timestamptz not null default now()
);
alter table public.radar_dispensas enable row level security;

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
  cand as (
    select uid from sinais union select uid from contactos union select uid from denuncias union select uid from bloqs
  ),
  nota as (
    select p.id, p.full_name, p.avatar_url, p.type, p.created_at, p.verificada_em is not null as verif,
           coalesce(s.codigo, 0) codigo, coalesce(s.adiantado, 0) adiantado, coalesce(s.premio, 0) premio,
           coalesce(s.equipa, 0) equipa, coalesce(s.numero, 0) numero, coalesce(s.links, 0) links,
           coalesce(c.novos, 0) novos, coalesce(c.novos24, 0) novos24, coalesce(d.n, 0) denun, coalesce(b.n, 0) bloq,
           (exists (select 1 from numeros_proibidos np
                     where np.numero = any (numeros_em(coalesce(p.phone, '') || ' ' || coalesce(p.whatsapp, '')))
                       and np.conta is distinct from p.id)) num_perfil
      from cand x join perfis p on p.id = x.uid
      left join sinais s on s.uid = p.id left join contactos c on c.uid = p.id
      left join denuncias d on d.uid = p.id left join bloqs b on b.uid = p.id
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
      ) / (case when n.verif then 2 else 1 end))::int as pts
      from nota n
  )
  select p.id, p.full_name, p.avatar_url, p.type, p.created_at, p.verif, p.pts,
         array_remove(array[
           case when p.created_at > now() - interval '7 days' then
             (select case when d = 0 then 'Conta criada hoje' when d = 1 then 'Conta criada há 1 dia' else 'Conta criada há ' || d || ' dias' end
                from (select greatest(0, extract(day from now() - p.created_at)::int) as d) x) end,
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

-- "Está bem": sai da lista até a nota subir
create or replace function public.admin_radar_dispensar(p_uid uuid, p_pontos int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  insert into radar_dispensas (conta, pontos, por) values (p_uid, p_pontos, auth.uid())
  on conflict (conta) do update set pontos = excluded.pontos, por = excluded.por, em = now();
end $$;

-- ---------- 4) Avisar as vítimas ----------

-- quem falou com a conta nos últimos 30 dias (sem a equipa)
create or replace function public.vitimas_de(p_uid uuid)
returns table (uid uuid) language sql stable security definer set search_path = public as $$
  select distinct o from (
    select case when m.sender_id = p_uid then m.receiver_id else m.sender_id end as o
      from messages m where (m.sender_id = p_uid or m.receiver_id = p_uid) and m.created_at > now() - interval '30 days'
    union
    select case when a.sender_id = p_uid then a.receiver_id else a.sender_id end
      from mensagens_apagadas a where (a.sender_id = p_uid or a.receiver_id = p_uid) and a.enviada_em > now() - interval '30 days'
  ) s
  join perfis p on p.id = s.o
  where s.o <> p_uid and coalesce(p.role, 'user') not in ('admin', 'equipa', 'ajudante')
$$;
revoke execute on function public.vitimas_de(uuid) from public, anon, authenticated;

create or replace function public.admin_contar_vitimas(p_uid uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return (select count(*) from vitimas_de(p_uid));
end $$;

create or replace function public.admin_avisar_vitimas(p_uid uuid, p_motivo_pt text, p_motivo_en text default null)
returns int language plpgsql security definer set search_path = public as $$
declare alvo perfis%rowtype; n int; motivo_pt text := nullif(trim(p_motivo_pt), ''); motivo_en text;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  select * into alvo from perfis where id = p_uid;
  if not found or not coalesce(alvo.bloqueado, false) then
    raise exception 'Primeiro suspenda a conta; só depois se avisam as pessoas.' using errcode = 'P0001';
  end if;
  if motivo_pt is null then raise exception 'Escolha o motivo.' using errcode = 'P0001'; end if;
  if exists (select 1 from registo_admin where acao = 'avisar_vitimas' and conta_a = p_uid and criado > now() - interval '1 day') then
    raise exception 'As pessoas que falaram com esta conta já foram avisadas hoje.' using errcode = 'P0001';
  end if;
  motivo_pt := left(motivo_pt, 200);
  motivo_en := left(coalesce(nullif(trim(p_motivo_en), ''), motivo_pt), 200);
  insert into messages (sender_id, receiver_id, content)
  select 'a73d8f73-5b2c-4f03-9deb-17aa890287dd', v.uid,
         case when p.idioma = 'en' then
           '⚠️ Notice from the Feira Comercial Team' || chr(10) || chr(10) ||
           'The account "' || coalesce(alvo.full_name, 'unknown') || '", which you talked to on Feira, has been suspended due to ' || motivo_en || '.' || chr(10) || chr(10) ||
           'If you had any problem with this account, reply to this message and the team will help.' || chr(10) ||
           '🔒 We never ask for your password or codes.'
         else
           '⚠️ Aviso da Equipa Feira Comercial' || chr(10) || chr(10) ||
           'A conta «' || coalesce(alvo.full_name, 'desconhecida') || '», com quem falou na Feira, foi suspensa por ' || motivo_pt || '.' || chr(10) || chr(10) ||
           'Se teve algum problema com esta conta, responda a esta mensagem e a equipa ajuda.' || chr(10) ||
           '🔒 Nunca pedimos a sua palavra-passe nem códigos.'
         end
    from vitimas_de(p_uid) v join perfis p on p.id = v.uid;
  get diagnostics n = row_count;
  insert into registo_admin (admin_id, acao, conta_a, motivo) values (auth.uid(), 'avisar_vitimas', p_uid, n || ' pessoas · ' || motivo_pt);
  return n;
end $$;

revoke execute on function public.proibir_numeros_de(uuid, text) from public, anon, authenticated;
revoke execute on function public.verificar_mensagem() from public, anon, authenticated;
revoke execute on function public.limitar_contas_novas() from public, anon, authenticated;
