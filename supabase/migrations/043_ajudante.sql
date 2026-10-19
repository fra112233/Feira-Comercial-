-- ============================================================
-- Feira Comercial — 043: Função "Ajudante"
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- O Ajudante é uma pessoa de confiança que ajuda o administrador. Pode:
--   ✓ ler e responder na Caixa da Equipa (em nome da Equipa Feira Comercial)
--   ✓ tratar reclamações e denúncias (ver e responder)
--   ✓ ver as contas novas e dar-lhes as boas-vindas
-- NÃO pode: ver pagamentos, receitas, configurações, crescimento, abrir conversas
-- privadas entre utilizadores, suspender contas nem criar outros ajudantes.
-- Só o administrador põe ou tira alguém como Ajudante (Administração → Contas).
-- Cada resposta da Equipa fica registada com quem a escreveu.
-- ============================================================

-- quem pode ajudar: administrador ou ajudante (com verificação em dois passos, se a tiver ativa)
create or replace function public.sou_suporte()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and role in ('admin', 'ajudante'))
     and (coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
          or not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified'));
$$;
revoke all on function public.sou_suporte() from public, anon;
grant execute on function public.sou_suporte() to authenticated;

-- reclamações e denúncias: o ajudante também vê e responde
drop policy if exists reclamacoes_ajudante_ver on public.reclamacoes;
create policy reclamacoes_ajudante_ver on public.reclamacoes for select to authenticated using ((select sou_suporte()));
drop policy if exists reclamacoes_ajudante_responder on public.reclamacoes;
create policy reclamacoes_ajudante_responder on public.reclamacoes for update to authenticated
  using ((select sou_suporte())) with check ((select sou_suporte()));

-- registo de quem respondeu em nome da Equipa
create table if not exists public.equipa_respostas (
  mensagem_id bigint primary key references public.messages(id) on delete cascade,
  autor_id uuid references public.perfis(id) on delete set null,
  criado timestamptz not null default now()
);
alter table public.equipa_respostas enable row level security;
revoke all on public.equipa_respostas from anon, authenticated;

-- Caixa da Equipa: administrador e ajudante
create or replace function public.equipa_conversas()
returns table (outro uuid, nome text, avatar text, tipo text, ultima text, ultima_em timestamptz, de_mim boolean, por_ler int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  return query
  with m as (
    select case when x.sender_id = equipa then x.receiver_id else x.sender_id end o, x.*
      from messages x
     where (x.sender_id = equipa or x.receiver_id = equipa) and not coalesce(x.deleted, false)
  ), ult as (
    select distinct on (o) o, content, media_type, created_at, sender_id = equipa de_mim from m order by o, created_at desc
  )
  select u.o, p.full_name, p.avatar_url, p.type,
         coalesce(nullif(left(u.content, 120), ''), case when u.media_type is not null then '📎 Ficheiro' else '' end),
         u.created_at, u.de_mim,
         (select count(*)::int from messages y where y.sender_id = u.o and y.receiver_id = equipa and y.read_at is null and not coalesce(y.deleted, false))
    from ult u join perfis p on p.id = u.o
   order by u.created_at desc
   limit 300;
end $$;

drop function if exists public.equipa_mensagens(uuid);
create or replace function public.equipa_mensagens(p_outro uuid)
returns table (id bigint, de_mim boolean, content text, media_type text, ref jsonb, created_at timestamptz, read_at timestamptz, autor text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  update messages set read_at = now()
   where sender_id = p_outro and receiver_id = equipa and read_at is null;
  return query
  select x.id, x.sender_id = equipa, x.content, x.media_type, x.ref, x.created_at, x.read_at,
         (select split_part(trim(a.full_name), ' ', 1) from equipa_respostas r join perfis a on a.id = r.autor_id where r.mensagem_id = x.id)
    from messages x
   where ((x.sender_id = equipa and x.receiver_id = p_outro) or (x.sender_id = p_outro and x.receiver_id = equipa))
     and not coalesce(x.deleted, false)
   order by x.created_at desc
   limit 200;
end $$;

create or replace function public.equipa_enviar(p_para uuid, p_texto text)
returns bigint language plpgsql security definer set search_path = public as $$
declare equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd'; novo bigint;
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  if p_para is null or p_para = equipa or not exists (select 1 from perfis where id = p_para) then raise exception 'destinatário inválido'; end if;
  if length(btrim(coalesce(p_texto, ''))) = 0 then raise exception 'mensagem vazia'; end if;
  insert into messages (sender_id, receiver_id, content) values (equipa, p_para, left(btrim(p_texto), 2000)) returning id into novo;
  insert into equipa_respostas (mensagem_id, autor_id) values (novo, auth.uid());
  return novo;
end $$;

revoke all on function public.equipa_conversas() from public, anon;
revoke all on function public.equipa_mensagens(uuid) from public, anon;
revoke all on function public.equipa_enviar(uuid, text) from public, anon;
grant execute on function public.equipa_conversas() to authenticated;
grant execute on function public.equipa_mensagens(uuid) to authenticated;
grant execute on function public.equipa_enviar(uuid, text) to authenticated;

-- Contas novas: administrador e ajudante (a regra de "já cumprimentada" mantém-se)
do $$
declare def text;
begin
  def := pg_get_functiondef('public.admin_contas_novas(integer)'::regprocedure);
  if position('if not sou_admin() then' in def) > 0 then
    execute replace(def, 'if not sou_admin() then', 'if not sou_suporte() then');
  end if;
end $$;

-- pôr ou tirar alguém como Ajudante (só o administrador)
create or replace function public.admin_definir_ajudante(p_uid uuid, p_sim boolean)
returns void language plpgsql security definer set search_path = public as $$
declare r text;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  select role into r from perfis where id = p_uid;
  if not found then raise exception 'conta não encontrada'; end if;
  if r in ('admin', 'equipa') then raise exception 'esta conta já é da equipa'; end if;
  update perfis set role = case when p_sim then 'ajudante' else 'user' end where id = p_uid;
  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
    values (auth.uid(), case when p_sim then 'ajudante_sim' else 'ajudante_nao' end, p_uid, null, null);
end $$;
revoke all on function public.admin_definir_ajudante(uuid, boolean) from public, anon;
grant execute on function public.admin_definir_ajudante(uuid, boolean) to authenticated;
