-- ============================================================
-- Feira Comercial — 005: vídeos curtos (estilo TikTok) e anúncios de empresas
-- Correr UMA vez no Supabase: SQL Editor → New query → colar → Run
-- É seguro correr de novo.
-- ============================================================

-- ======================= VÍDEOS =======================
create table if not exists public.videos (
  id              bigint generated always as identity primary key,
  user_id         uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  video_url       text not null,
  caption         text,
  duracao         numeric,
  views           bigint not null default 0,
  likes_count     bigint not null default 0,
  comments_count  bigint not null default 0,
  created_at      timestamptz not null default now()
);
create index if not exists videos_created_idx on public.videos (created_at desc);
create index if not exists videos_user_idx on public.videos (user_id);

create table if not exists public.video_likes (
  video_id   bigint not null references public.videos(id) on delete cascade,
  user_id    uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (video_id, user_id)
);

create table if not exists public.video_comments (
  id         bigint generated always as identity primary key,
  video_id   bigint not null references public.videos(id) on delete cascade,
  user_id    uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  content    text not null check (length(content) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists video_comments_video_idx on public.video_comments (video_id, created_at);

alter table public.videos enable row level security;
alter table public.video_likes enable row level security;
alter table public.video_comments enable row level security;

drop policy if exists "videos_ver" on public.videos;
create policy "videos_ver" on public.videos for select to authenticated using (true);
drop policy if exists "videos_publicar" on public.videos;
create policy "videos_publicar" on public.videos for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "videos_editar_os_meus" on public.videos;
create policy "videos_editar_os_meus" on public.videos for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "videos_apagar_os_meus" on public.videos;
create policy "videos_apagar_os_meus" on public.videos for delete to authenticated using (user_id = auth.uid());

drop policy if exists "vlikes_ver" on public.video_likes;
create policy "vlikes_ver" on public.video_likes for select to authenticated using (true);
drop policy if exists "vlikes_dar" on public.video_likes;
create policy "vlikes_dar" on public.video_likes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "vlikes_tirar" on public.video_likes;
create policy "vlikes_tirar" on public.video_likes for delete to authenticated using (user_id = auth.uid());

drop policy if exists "vcom_ver" on public.video_comments;
create policy "vcom_ver" on public.video_comments for select to authenticated using (true);
drop policy if exists "vcom_comentar" on public.video_comments;
create policy "vcom_comentar" on public.video_comments for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "vcom_apagar" on public.video_comments;
create policy "vcom_apagar" on public.video_comments for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.videos v where v.id = video_id and v.user_id = auth.uid()));

-- os contadores não podem ser mexidos pelo dono do vídeo
create or replace function public.proteger_contadores_video()
returns trigger language plpgsql set search_path = public as $$
begin
  -- só limita alterações feitas diretamente pelo site (as funções do sistema podem atualizar os contadores)
  if current_user = 'authenticated' then
    new.views := old.views; new.likes_count := old.likes_count; new.comments_count := old.comments_count;
    new.video_url := old.video_url; new.user_id := old.user_id; new.created_at := old.created_at;
  end if;
  return new;
end; $$;
drop trigger if exists videos_proteger on public.videos;
create trigger videos_proteger before update on public.videos
  for each row execute function public.proteger_contadores_video();

-- contadores automáticos de gostos e comentários
create or replace function public.contar_video()
returns trigger language plpgsql security definer set search_path = public as $$
declare vid bigint := coalesce(new.video_id, old.video_id);
begin
  update public.videos set
    likes_count    = (select count(*) from public.video_likes    where video_id = vid),
    comments_count = (select count(*) from public.video_comments where video_id = vid)
  where id = vid;
  return null;
end; $$;
revoke execute on function public.contar_video() from public, anon, authenticated;
drop trigger if exists vlikes_contar on public.video_likes;
create trigger vlikes_contar after insert or delete on public.video_likes for each row execute function public.contar_video();
drop trigger if exists vcom_contar on public.video_comments;
create trigger vcom_contar after insert or delete on public.video_comments for each row execute function public.contar_video();

-- contar visualizações (chamado pelo site quando alguém vê um vídeo)
create or replace function public.ver_video(vid bigint)
returns void language sql security definer set search_path = public as $$
  update public.videos set views = views + 1 where id = vid;
$$;
revoke execute on function public.ver_video(bigint) from public, anon;
grant execute on function public.ver_video(bigint) to authenticated;

-- ficheiros dos vídeos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('videos', 'videos', true, 52428800, array['video/*', 'image/*'])
on conflict (id) do nothing;
drop policy if exists "videos_enviar_na_minha_pasta" on storage.objects;
create policy "videos_enviar_na_minha_pasta" on storage.objects for insert to authenticated
  with check (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "videos_apagar_da_minha_pasta" on storage.objects;
create policy "videos_apagar_da_minha_pasta" on storage.objects for delete to authenticated
  using (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text);

do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'videos') then
    alter publication supabase_realtime add table public.videos;
  end if;
end $$;

-- ======================= ANÚNCIOS (só empresas) =======================
alter table public.vagas_anuncios
  add column if not exists preco       text,                      -- "1.500 MT", "Salário a combinar"...
  add column if not exists localizacao text,
  add column if not exists validade    date,
  add column if not exists link        text,
  add column if not exists contacto    text,
  add column if not exists ativo       boolean not null default true,
  add column if not exists views       bigint not null default 0;
alter table public.vagas_anuncios alter column empresa_id set default auth.uid();
update public.vagas_anuncios set tipo = 'promo' where tipo is null or tipo not in ('promo', 'vaga', 'servico');
alter table public.vagas_anuncios alter column tipo set default 'promo';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'vagas_tipo_check') then
    alter table public.vagas_anuncios add constraint vagas_tipo_check check (tipo in ('promo', 'vaga', 'servico'));
  end if;
  -- ligação ao perfil da empresa (para mostrar nome, foto e contactos)
  if not exists (select 1 from pg_constraint where conname = 'vagas_anuncios_empresa_perfil_fkey') then
    alter table public.vagas_anuncios add constraint vagas_anuncios_empresa_perfil_fkey
      foreign key (empresa_id) references public.perfis(id) on delete cascade;
  end if;
end $$;
create index if not exists vagas_data_idx on public.vagas_anuncios (data_publicacao desc);

-- ver: quem tem conta vê os anúncios ativos (a empresa vê também os seus inativos)
drop policy if exists "Qualquer um pode ver as vagas" on public.vagas_anuncios;
drop policy if exists "vagas_ver" on public.vagas_anuncios;
create policy "vagas_ver" on public.vagas_anuncios for select to authenticated
  using (ativo or empresa_id = auth.uid());

-- editar só as suas e continuando a ser empresa (as regras de criar/apagar já existem do 003)
drop policy if exists "vagas_mudar_as_minhas" on public.vagas_anuncios;
create policy "vagas_mudar_as_minhas" on public.vagas_anuncios for update to authenticated
  using (empresa_id = auth.uid()) with check (empresa_id = auth.uid() and public.sou_empresa());

create or replace function public.ver_anuncio(aid uuid)
returns void language sql security definer set search_path = public as $$
  update public.vagas_anuncios set views = views + 1 where id = aid;
$$;
revoke execute on function public.ver_anuncio(uuid) from public, anon;
grant execute on function public.ver_anuncio(uuid) to authenticated;

-- fotos dos anúncios (bucket "ads_media", que já existia): só empresas, na sua pasta
update storage.buckets set public = true, file_size_limit = 10485760 where id = 'ads_media';
drop policy if exists "ads_enviar_se_empresa" on storage.objects;
create policy "ads_enviar_se_empresa" on storage.objects for insert to authenticated
  with check (bucket_id = 'ads_media' and (storage.foldername(name))[1] = auth.uid()::text and public.sou_empresa());
drop policy if exists "ads_apagar_os_meus" on storage.objects;
create policy "ads_apagar_os_meus" on storage.objects for delete to authenticated
  using (bucket_id = 'ads_media' and (storage.foldername(name))[1] = auth.uid()::text);

-- pequena correção de segurança sugerida pelo Supabase
alter function public.bloquear_mudanca_tipo() set search_path = public;
