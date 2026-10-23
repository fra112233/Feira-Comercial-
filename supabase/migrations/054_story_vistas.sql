-- ============================================================
-- Feira Comercial — 054: Quem viu e quem gostou dos stories
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Antes: o "visto" de um story ficava só no telemóvel de quem via, e não havia gostos.
-- Agora:
--   • cada vez que alguém abre um story fica registado (uma vez por pessoa);
--   • quem vê pode carregar em ❤️ (e tirar);
--   • SÓ o dono do story vê a lista de quem viu e quem gostou;
--   • o dono recebe no sino "gostou do seu story" (só no primeiro gosto de cada pessoa).
-- ============================================================

create table if not exists public.story_vistas (
  story_id bigint not null references public.stories(id) on delete cascade,
  user_id  uuid   not null references public.perfis(id)  on delete cascade,
  visto    timestamptz not null default now(),
  reacao   text check (reacao in ('Curtir','Amei','Haha','Triste','Uau')),
  reagiu   timestamptz,
  primary key (story_id, user_id)
);
create index if not exists story_vistas_user_idx on public.story_vistas(user_id);

alter table public.story_vistas enable row level security;
-- ler: as minhas próprias linhas (saber se já gostei) ou as dos MEUS stories (quem viu)
drop policy if exists story_vistas_ver on public.story_vistas;
create policy story_vistas_ver on public.story_vistas for select to authenticated
  using (user_id = (select auth.uid())
         or exists (select 1 from public.stories s where s.id = story_id and s.user_id = (select auth.uid())));
-- escrever: só pelas funções abaixo
revoke all on public.story_vistas from anon;
revoke insert, update, delete on public.story_vistas from authenticated;
grant select on public.story_vistas to authenticated;

-- ---------- registar que vi ----------
create or replace function public.story_ver(p_story bigint)
returns void language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); dono uuid;
begin
  if eu is null then return; end if;
  select user_id into dono from stories where id = p_story;
  if dono is null or dono = eu then return; end if;           -- o dono não conta como visita
  insert into story_vistas (story_id, user_id) values (p_story, eu)
  on conflict (story_id, user_id) do nothing;
end $$;

-- ---------- gostar / tirar o gosto (p_reacao null = tirar) ----------
create or replace function public.story_reagir(p_story bigint, p_reacao text default 'Amei')
returns void language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); dono uuid; antes text; ja_reagiu timestamptz;
begin
  if eu is null then raise exception 'Inicie sessão para reagir.'; end if;
  if p_reacao is not null and p_reacao not in ('Curtir','Amei','Haha','Triste','Uau') then
    raise exception 'Reação inválida.';
  end if;
  select user_id into dono from stories where id = p_story;
  if dono is null then raise exception 'Este story já não existe.'; end if;
  if dono = eu then return; end if;
  select reacao, reagiu into antes, ja_reagiu from story_vistas where story_id = p_story and user_id = eu;
  insert into story_vistas (story_id, user_id, reacao, reagiu)
  values (p_story, eu, p_reacao, case when p_reacao is null then null else now() end)
  on conflict (story_id, user_id) do update
     set reacao = excluded.reacao,
         reagiu = coalesce(story_vistas.reagiu, excluded.reagiu);
  -- aviso só no primeiro gosto desta pessoa neste story (tirar e voltar a pôr não repete)
  if p_reacao is not null and ja_reagiu is null then
    perform criar_notificacao(dono, eu, 'gosto_story');
  end if;
end $$;

revoke all on function public.story_ver(bigint) from public, anon;
revoke all on function public.story_reagir(bigint, text) from public, anon;
grant execute on function public.story_ver(bigint) to authenticated;
grant execute on function public.story_reagir(bigint, text) to authenticated;

-- ---------- novo tipo de aviso no sino ----------
do $$
declare def text; lista text;
begin
  select pg_get_constraintdef(oid) into def from pg_constraint
   where conrelid = 'public.notificacoes'::regclass and conname = 'notificacoes_tipo_check';
  if def is not null and def not like '%gosto_story%' then
    lista := substring(def from 'ARRAY\[(.*)\]');
    execute 'alter table public.notificacoes drop constraint notificacoes_tipo_check';
    execute 'alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[' || lista || ', ''gosto_story''::text]))';
  end if;
end $$;
