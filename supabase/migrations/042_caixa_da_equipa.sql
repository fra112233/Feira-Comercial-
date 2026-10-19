-- ============================================================
-- Feira Comercial — 042: Caixa da Equipa
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Organização:
--  • Administrador = gestão (pagamentos, contas, configurações, crescimento).
--  • Equipa Feira Comercial = a cara pública (boas-vindas, ajuda no chat, novidades).
-- O administrador passa a ler e responder às conversas da conta da Equipa dentro
-- da Administração (separador "Caixa da Equipa"), sem trocar de conta.
-- As mensagens saem em nome da "Equipa Feira Comercial".
-- Só funciona para o administrador (sou_admin, com verificação em dois passos se ativa).
-- ============================================================

-- lista de conversas da Equipa (mais recentes primeiro)
create or replace function public.equipa_conversas()
returns table (outro uuid, nome text, avatar text, tipo text, ultima text, ultima_em timestamptz, de_mim boolean, por_ler int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
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

-- mensagens de uma conversa da Equipa (e marca como lidas as que chegaram)
create or replace function public.equipa_mensagens(p_outro uuid)
returns table (id bigint, de_mim boolean, content text, media_type text, ref jsonb, created_at timestamptz, read_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  update messages set read_at = now()
   where sender_id = p_outro and receiver_id = equipa and read_at is null;
  return query
  select x.id, x.sender_id = equipa, x.content, x.media_type, x.ref, x.created_at, x.read_at
    from messages x
   where ((x.sender_id = equipa and x.receiver_id = p_outro) or (x.sender_id = p_outro and x.receiver_id = equipa))
     and not coalesce(x.deleted, false)
   order by x.created_at desc
   limit 200;
end $$;

-- responder em nome da Equipa
create or replace function public.equipa_enviar(p_para uuid, p_texto text)
returns bigint language plpgsql security definer set search_path = public as $$
declare equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd'; novo bigint;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_para is null or p_para = equipa or not exists (select 1 from perfis where id = p_para) then raise exception 'destinatário inválido'; end if;
  if length(btrim(coalesce(p_texto, ''))) = 0 then raise exception 'mensagem vazia'; end if;
  insert into messages (sender_id, receiver_id, content) values (equipa, p_para, left(btrim(p_texto), 2000)) returning id into novo;
  return novo;
end $$;

revoke all on function public.equipa_conversas() from public, anon;
revoke all on function public.equipa_mensagens(uuid) from public, anon;
revoke all on function public.equipa_enviar(uuid, text) from public, anon;
grant execute on function public.equipa_conversas() to authenticated;
grant execute on function public.equipa_mensagens(uuid) to authenticated;
grant execute on function public.equipa_enviar(uuid, text) to authenticated;

-- "Contas novas": conta como cumprimentada se a Equipa OU o administrador já lhe escreveu
create or replace function public.admin_contas_novas(p_dias int default 14)
returns table (id uuid, full_name text, avatar_url text, type text, city text, province text, idioma text,
               criado timestamptz, passos int, cumprimentado boolean, respondeu boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  select p.id, p.full_name, p.avatar_url, p.type, p.city, p.province, p.idioma, p.created_at,
         ( (coalesce(nullif(p.avatar_url, ''), '') <> '')::int
         + (coalesce(nullif(trim(p.city), ''), nullif(trim(p.province), '')) is not null)::int
         + ((select count(*) from followers f where f.follower_id = p.id) >= 3)::int
         + (case when p.type = 'empresa' then exists (select 1 from posts x where x.user_id = p.id)
                 else exists (select 1 from likes l where l.user_id = p.id) end)::int ),
         -- mensagem pessoal (não conta a de boas-vindas automática, que é a primeira da Equipa)
         exists (select 1 from messages m where m.receiver_id = p.id
                   and (m.sender_id = auth.uid()
                        or (m.sender_id = equipa and m.created_at > p.created_at + interval '2 minutes'
                            and m.content not like '%Bem-vindo(a) à Feira Comercial%' and m.content not like '%Welcome to Feira Comercial%'
                            and m.content not like '%ainda não publicou%' and m.content not like '%hasn''t posted yet%'
                            and m.content not like '%Siga algumas empresas%' and m.content not like '%Follow a few businesses%'))),
         exists (select 1 from messages m join perfis e on e.id = m.receiver_id
                  where m.sender_id = p.id and e.role in ('admin', 'equipa'))
  from perfis p
  where p.created_at > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 14), 90)))
    and p.role not in ('admin', 'equipa')
  order by p.created_at desc;
end $$;
revoke all on function public.admin_contas_novas(int) from public, anon;
grant execute on function public.admin_contas_novas(int) to authenticated;
