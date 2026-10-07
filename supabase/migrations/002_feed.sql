-- ============================================================
-- Feira Comercial — 002: feed partilhado (posts, gostos, comentários, stories, fotos)
-- Correr UMA vez no Supabase: SQL Editor → New query → colar → Run
-- É seguro correr de novo.
-- ============================================================

-- ---------- POSTS ----------
-- várias fotos/vídeos por post: [{ "url": "...", "type": "image" | "video" }]
alter table public.posts
  add column if not exists media jsonb not null default '[]'::jsonb;
alter table public.posts alter column user_id set default auth.uid();
update public.posts set curtidas_count = coalesce(curtidas_count, 0), comentarios_count = coalesce(comentarios_count, 0);
alter table public.posts alter column curtidas_count set default 0;
alter table public.posts alter column comentarios_count set default 0;

-- esta regra estava criada como "ver" (SELECT) em vez de "apagar"
drop policy if exists "usuário pode deletar o próprio post" on public.posts;
drop policy if exists "posts_apagar_o_meu" on public.posts;
create policy "posts_apagar_o_meu" on public.posts
  for delete to authenticated using (auth.uid() = user_id);
drop policy if exists "posts_editar_o_meu" on public.posts;
create policy "posts_editar_o_meu" on public.posts
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists posts_created_at_idx on public.posts (created_at desc);

-- ---------- GOSTOS (reações) ----------
alter table public.likes add column if not exists reaction text not null default 'Curtir';
alter table public.likes alter column user_id set default auth.uid();
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'likes_post_user_unique') then
    alter table public.likes add constraint likes_post_user_unique unique (post_id, user_id);
  end if;
end $$;

drop policy if exists "likes_ver" on public.likes;
create policy "likes_ver" on public.likes for select to authenticated using (true);
drop policy if exists "likes_criar_o_meu" on public.likes;
create policy "likes_criar_o_meu" on public.likes for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "likes_mudar_o_meu" on public.likes;
create policy "likes_mudar_o_meu" on public.likes for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "likes_apagar_o_meu" on public.likes;
create policy "likes_apagar_o_meu" on public.likes for delete to authenticated using (auth.uid() = user_id);

-- ---------- COMENTÁRIOS (com respostas) ----------
alter table public.comments add column if not exists parent_id bigint references public.comments(id) on delete cascade;
alter table public.comments alter column user_id set default auth.uid();

-- faltava a regra para LER comentários
drop policy if exists "comments_ver" on public.comments;
create policy "comments_ver" on public.comments for select to authenticated using (true);

create index if not exists comments_post_idx on public.comments (post_id);
create index if not exists likes_post_idx on public.likes (post_id);

-- ---------- CONTADORES automáticos ----------
create or replace function public.atualizar_contadores_post()
returns trigger language plpgsql security definer set search_path = public as $$
declare pid bigint := coalesce(new.post_id, old.post_id);
begin
  update public.posts set
    curtidas_count    = (select count(*) from public.likes    where post_id = pid),
    comentarios_count = (select count(*) from public.comments where post_id = pid)
  where id = pid;
  return null;
end; $$;
revoke execute on function public.atualizar_contadores_post() from public, anon, authenticated;

drop trigger if exists likes_contar on public.likes;
create trigger likes_contar after insert or delete on public.likes
  for each row execute function public.atualizar_contadores_post();
drop trigger if exists comments_contar on public.comments;
create trigger comments_contar after insert or delete on public.comments
  for each row execute function public.atualizar_contadores_post();

-- ---------- STORIES ----------
create table if not exists public.stories (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  media_url   text not null,
  media_type  text not null default 'image',
  created_at  timestamptz not null default now()
);
alter table public.stories enable row level security;
drop policy if exists "stories_ver" on public.stories;
create policy "stories_ver" on public.stories for select to authenticated using (true);
drop policy if exists "stories_criar_o_meu" on public.stories;
create policy "stories_criar_o_meu" on public.stories for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "stories_apagar_o_meu" on public.stories;
create policy "stories_apagar_o_meu" on public.stories for delete to authenticated using (auth.uid() = user_id);
create index if not exists stories_created_at_idx on public.stories (created_at desc);

-- atualizações em tempo real para stories
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'stories') then
    alter publication supabase_realtime add table public.stories;
  end if;
end $$;

-- ---------- FICHEIROS (fotos e vídeos do feed) ----------
-- bucket público "media": cada utilizador só envia/apaga dentro da sua pasta (<id>/...)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 52428800, array['image/*', 'video/*'])
on conflict (id) do nothing;

drop policy if exists "media_enviar_na_minha_pasta" on storage.objects;
create policy "media_enviar_na_minha_pasta" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "media_apagar_da_minha_pasta" on storage.objects;
create policy "media_apagar_da_minha_pasta" on storage.objects
  for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- FOTOS DE PERFIL ----------
-- bucket público "avatars" (o site já o usa, mas não existia)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/*'])
on conflict (id) do nothing;

drop policy if exists "avatars_ver_os_meus" on storage.objects;
create policy "avatars_ver_os_meus" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars_enviar_na_minha_pasta" on storage.objects;
create policy "avatars_enviar_na_minha_pasta" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars_mudar_na_minha_pasta" on storage.objects;
create policy "avatars_mudar_na_minha_pasta" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars_apagar_da_minha_pasta" on storage.objects;
create policy "avatars_apagar_da_minha_pasta" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
