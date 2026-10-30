-- ============================================================
-- Feira Comercial — 063: Amigos — sugestões, pesquisa melhor e seguidores
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Página Amigos → "Descobrir":
--  1) SUGESTÕES PARA TI (sem pesquisa): primeiro quem os teus amigos seguem,
--     quem está na tua cidade/província, lojas verificadas 👑 e quem te segue
--     (para seguir de volta). Quem já segues não aparece.
--  2) PESQUISA: pelo nome, @utilizador, setor, cidade ou província, com ou sem
--     acentos ("maputo", "Eletronica", "@lojabompreco").
--  3) VER MAIS: 30 de cada vez (antes parava nos 60).
--  4) Número de seguidores e coroa 👑 em cada cartão.
-- Nunca mostra: contas privadas, suspensas, nem quem bloqueou ou foi bloqueado.
-- ============================================================

-- texto sem acentos e em minúsculas (para pesquisar "eletronica" e achar "Eletrónica")
create or replace function public.fc_sem_acentos(t text)
returns text language sql immutable parallel safe set search_path = public as $$
  select translate(lower(coalesce(t, '')), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn');
$$;

drop function if exists public.descobrir_perfis(text, text, text, text, int, int);
create function public.descobrir_perfis(
  p_termo text default null,
  p_provincia text default null,
  p_setor text default null,
  p_tipo text default null,
  p_desde int default 0,
  p_limite int default 30)
returns table (
  id uuid, full_name text, username text, type text, sector text, bio text,
  city text, province text, avatar_url text, created_at timestamptz,
  seguidores bigint, verificada boolean, amigos_comum bigint, amigo_nome text,
  mesma_cidade boolean, segue_me boolean)
language sql stable security definer set search_path = public as $$
  with eu as (
    select p.id, fc_sem_acentos(p.city) as cidade, p.province from perfis p where p.id = (select auth.uid())
  ),
  termo as (
    select nullif(fc_sem_acentos(btrim(regexp_replace(coalesce(p_termo, ''), '^\s*@', ''))), '') as t
  ),
  base as (
    select p.*,
           (select count(*) from followers f where f.following_id = p.id) as n_seg,
           (select count(*) from followers a join followers b on b.follower_id = a.following_id
              where a.follower_id = eu.id and b.following_id = p.id) as n_comum,
           exists (select 1 from followers f where f.follower_id = p.id and f.following_id = eu.id) as me_segue,
           exists (select 1 from followers f where f.follower_id = eu.id and f.following_id = p.id) as sigo,
           (eu.cidade <> '' and fc_sem_acentos(p.city) = eu.cidade) as cidade_igual,
           (p.province is not null and p.province = eu.province) as prov_igual,
           (p.verificada_em is not null) as coroa
      from perfis p, eu, termo
     where p.id <> eu.id
       and coalesce(p.visibility, 'publico') = 'publico'
       and coalesce(p.bloqueado, false) = false
       and not exists (select 1 from bloqueios b
                        where (b.blocker_id = eu.id and b.blocked_id = p.id)
                           or (b.blocker_id = p.id and b.blocked_id = eu.id))
       and (nullif(p_provincia, '') is null or p.province = p_provincia)
       and (nullif(p_setor, '') is null or p.sector = p_setor)
       and (nullif(p_tipo, '') is null or p.type = p_tipo)
       and (termo.t is null
            or strpos(fc_sem_acentos(p.full_name), termo.t) > 0
            or strpos(lower(coalesce(p.username, '')), termo.t) > 0
            or strpos(fc_sem_acentos(p.sector), termo.t) > 0
            or strpos(fc_sem_acentos(p.city), termo.t) > 0
            or strpos(fc_sem_acentos(p.province), termo.t) > 0)
  )
  select b.id, b.full_name, b.username, b.type, b.sector, b.bio, b.city, b.province, b.avatar_url, b.created_at,
         b.n_seg, b.coroa, b.n_comum,
         (select a2.full_name from followers a join followers x on x.follower_id = a.following_id
            join perfis a2 on a2.id = a.following_id
           where a.follower_id = (select id from eu) and x.following_id = b.id
           order by (select count(*) from followers z where z.following_id = a2.id) desc, a2.id
           limit 1),
         b.cidade_igual, b.me_segue
    from base b, termo
   -- sem pesquisa são sugestões: quem já sigo não aparece
   where termo.t is not null or not b.sigo
   order by
     -- na pesquisa: primeiro os nomes que começam pelo que se escreveu
     case when termo.t is not null then
       (left(fc_sem_acentos(b.full_name), length(termo.t)) = termo.t
         or left(lower(coalesce(b.username, '')), length(termo.t)) = termo.t)::int
     else 0 end desc,
     -- sugestões: amigos em comum, mesma cidade/província, coroa, quem me segue, mais seguidos
     (least(b.n_comum, 5) * 3 + b.cidade_igual::int * 4 + b.prov_igual::int * 2 + b.coroa::int * 3
       + (b.me_segue and not b.sigo)::int * 5 + least(b.n_seg, 50) / 10) desc,
     b.n_seg desc,
     b.created_at desc nulls last,
     b.id
   offset greatest(coalesce(p_desde, 0), 0)
   limit greatest(1, least(coalesce(p_limite, 30), 60));
$$;
revoke all on function public.descobrir_perfis(text, text, text, text, int, int) from public, anon;
grant execute on function public.descobrir_perfis(text, text, text, text, int, int) to authenticated;

-- número de seguidores de várias contas de uma vez (listas "A seguir" e "Seguidores")
create or replace function public.contar_seguidores(p_ids uuid[])
returns table (id uuid, seguidores bigint)
language sql stable set search_path = public as $$
  select i, (select count(*) from followers f where f.following_id = i)
    from unnest(p_ids[1:500]) as i;
$$;
revoke all on function public.contar_seguidores(uuid[]) from public, anon;
grant execute on function public.contar_seguidores(uuid[]) to authenticated;

-- ver se ficou bem: deve mostrar 2 linhas
select p.proname as funcao from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('descobrir_perfis', 'contar_seguidores') order by 1;
