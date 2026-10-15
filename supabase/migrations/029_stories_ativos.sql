-- ============================================================
-- Feira Comercial — 029: Stories ativos decididos pelo servidor
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Antes: cada telemóvel/computador decidia com o SEU relógio se um story já
-- tinha passado das 48 horas. Um aparelho com a hora adiantada deixava de ver
-- stories que ainda estavam ativos.
-- Agora: é a hora do servidor que decide, igual para todas as pessoas.
-- ============================================================

create or replace function public.stories_ativos()
returns table(id bigint, media_url text, media_type text, created_at timestamptz,
              user_id uuid, full_name text, avatar_url text, agora timestamptz)
language sql stable security invoker set search_path = public as $$
  select s.id, s.media_url, s.media_type, s.created_at, s.user_id, p.full_name, p.avatar_url, now()
    from stories s
    left join perfis p on p.id = s.user_id
   where s.created_at > now() - interval '48 hours'
   order by s.created_at;
$$;
revoke all on function public.stories_ativos() from public, anon;
grant execute on function public.stories_ativos() to authenticated;

-- só contas com sessão iniciada criam stories (a regra RLS já o exigia; isto tira a permissão que sobrava)
revoke insert on public.stories from anon;
