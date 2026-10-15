-- ============================================================
-- Feira Comercial — 022: Notificações de atividade (o sino 🔔)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Avisa quando: curtem/comentam a minha publicação ou vídeo, respondem ao meu
-- comentário, alguém me segue, e quando quem eu sigo publica, faz vídeo ou entra em Live.
-- Cada aviso fica na lista do sino e, se o aparelho tiver avisos ligados, chega por push.
-- ============================================================

create table if not exists public.notificacoes (
  id        bigserial primary key,
  user_id   uuid not null references public.perfis(id) on delete cascade,   -- quem recebe
  autor_id  uuid references public.perfis(id) on delete cascade,            -- quem fez
  tipo      text not null check (tipo in ('gosto','comentario','resposta','seguir','publicacao',
                                          'video','gosto_video','comentario_video','live')),
  post_id   bigint references public.posts(id)  on delete cascade,
  video_id  bigint references public.videos(id) on delete cascade,
  live_id   uuid   references public.lives(id)  on delete cascade,
  texto     text,
  lida      boolean not null default false,
  criado    timestamptz not null default now()
);
create index if not exists notificacoes_user_idx on public.notificacoes (user_id, criado desc);
create index if not exists notificacoes_por_ler_idx on public.notificacoes (user_id) where not lida;
create index if not exists notificacoes_autor_idx on public.notificacoes (autor_id);
create index if not exists notificacoes_post_idx on public.notificacoes (post_id);
create index if not exists notificacoes_video_idx on public.notificacoes (video_id);
create index if not exists notificacoes_live_idx on public.notificacoes (live_id);

alter table public.notificacoes enable row level security;
revoke all on public.notificacoes from anon, authenticated;
grant select, delete on public.notificacoes to authenticated;
grant update (lida) on public.notificacoes to authenticated;      -- só pode marcar como lida

drop policy if exists notif_ver on public.notificacoes;
create policy notif_ver on public.notificacoes for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists notif_marcar on public.notificacoes;
create policy notif_marcar on public.notificacoes for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists notif_apagar on public.notificacoes;
create policy notif_apagar on public.notificacoes for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------- criar um aviso (com regras anti-spam) ----------
create or replace function public.criar_notificacao(
  p_user uuid, p_autor uuid, p_tipo text,
  p_post bigint default null, p_video bigint default null, p_live uuid default null, p_texto text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_user = p_autor then return; end if;                 -- nunca a mim próprio
  if exists (select 1 from bloqueios where blocker_id = p_user and blocked_id = p_autor) then return; end if;
  -- gostos e seguir: não repetir o mesmo aviso em 24 h (tirar e voltar a pôr o gosto não gera spam)
  if p_tipo in ('gosto','gosto_video','seguir') and exists (
       select 1 from notificacoes
        where user_id = p_user and autor_id = p_autor and tipo = p_tipo
          and post_id is not distinct from p_post and video_id is not distinct from p_video
          and criado > now() - interval '24 hours') then
    return;
  end if;
  insert into notificacoes (user_id, autor_id, tipo, post_id, video_id, live_id, texto)
  values (p_user, p_autor, p_tipo, p_post, p_video, p_live, left(nullif(trim(p_texto), ''), 140));
exception when others then
  return;   -- um aviso que falha nunca impede o gosto/comentário/publicação
end $$;
revoke all on function public.criar_notificacao(uuid, uuid, text, bigint, bigint, uuid, text) from public, anon, authenticated;

-- avisar todos os seguidores de alguém (publicação nova, vídeo novo, Live)
create or replace function public.notificar_seguidores(
  p_autor uuid, p_tipo text, p_post bigint default null, p_video bigint default null, p_live uuid default null, p_texto text default null)
returns void language plpgsql security definer set search_path = public as $$
declare s record;
begin
  for s in select follower_id from followers where following_id = p_autor loop
    perform criar_notificacao(s.follower_id, p_autor, p_tipo, p_post, p_video, p_live, p_texto);
  end loop;
end $$;
revoke all on function public.notificar_seguidores(uuid, text, bigint, bigint, uuid, text) from public, anon, authenticated;

-- ---------- gatilhos ----------
create or replace function public.notif_gosto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform criar_notificacao((select user_id from posts where id = new.post_id), new.user_id, 'gosto', new.post_id);
  return null;
end $$;
drop trigger if exists trg_notif_gosto on public.likes;
create trigger trg_notif_gosto after insert on public.likes for each row execute function public.notif_gosto();

create or replace function public.notif_comentario() returns trigger
language plpgsql security definer set search_path = public as $$
declare dono uuid; autor_pai uuid;
begin
  select user_id into dono from posts where id = new.post_id;
  if new.parent_id is not null then
    select user_id into autor_pai from comments where id = new.parent_id;
    perform criar_notificacao(autor_pai, new.user_id, 'resposta', new.post_id, null, null, new.content);
  end if;
  if dono is distinct from autor_pai then
    perform criar_notificacao(dono, new.user_id, 'comentario', new.post_id, null, null, new.content);
  end if;
  return null;
end $$;
drop trigger if exists trg_notif_comentario on public.comments;
create trigger trg_notif_comentario after insert on public.comments for each row execute function public.notif_comentario();

create or replace function public.notif_seguir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform criar_notificacao(new.following_id, new.follower_id, 'seguir');
  return null;
end $$;
drop trigger if exists trg_notif_seguir on public.followers;
create trigger trg_notif_seguir after insert on public.followers for each row execute function public.notif_seguir();

create or replace function public.notif_publicacao() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notificar_seguidores(new.user_id, 'publicacao', new.id, null, null, new.content);
  return null;
end $$;
drop trigger if exists trg_notif_publicacao on public.posts;
create trigger trg_notif_publicacao after insert on public.posts for each row execute function public.notif_publicacao();

create or replace function public.notif_video() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notificar_seguidores(new.user_id, 'video', null, new.id, null, new.caption);
  return null;
end $$;
drop trigger if exists trg_notif_video on public.videos;
create trigger trg_notif_video after insert on public.videos for each row execute function public.notif_video();

create or replace function public.notif_live() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notificar_seguidores(new.user_id, 'live', null, null, new.id, new.titulo);
  return null;
end $$;
drop trigger if exists trg_notif_live on public.lives;
create trigger trg_notif_live after insert on public.lives for each row execute function public.notif_live();

create or replace function public.notif_gosto_video() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform criar_notificacao((select user_id from videos where id = new.video_id), new.user_id, 'gosto_video', null, new.video_id);
  return null;
end $$;
drop trigger if exists trg_notif_gosto_video on public.video_likes;
create trigger trg_notif_gosto_video after insert on public.video_likes for each row execute function public.notif_gosto_video();

create or replace function public.notif_comentario_video() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform criar_notificacao((select user_id from videos where id = new.video_id), new.user_id, 'comentario_video', null, new.video_id, null, new.content);
  return null;
end $$;
drop trigger if exists trg_notif_comentario_video on public.video_comments;
create trigger trg_notif_comentario_video after insert on public.video_comments for each row execute function public.notif_comentario_video();

-- funções dos gatilhos não são chamadas de fora
revoke all on function public.notif_gosto(), public.notif_comentario(), public.notif_seguir(), public.notif_publicacao(),
  public.notif_video(), public.notif_live(), public.notif_gosto_video(), public.notif_comentario_video()
  from public, anon, authenticated;

-- ---------- push: aviso novo → função "push" (só se houver aparelhos registados) ----------
create or replace function public.push_notificacao() returns trigger
language plpgsql security definer set search_path = public as $$
declare tok text;
begin
  if not exists (select 1 from push_subscricoes where user_id = new.user_id) then return null; end if;
  select token into tok from push_segredo where id = 1;
  if tok is null then return null; end if;
  perform net.http_post(
    url := 'https://bljnkwrhqnpawclybqrw.supabase.co/functions/v1/push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJsam5rd3JocW5wYXdjbHlicXJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3Njg1OTMsImV4cCI6MjA5MTM0NDU5M30.CX2UVsuUllQuqDWDfTop2Bb3f8IM9OzdGM3jUKToO78',
      'x-push-token', tok),
    body := jsonb_build_object('notificacao', new.id),
    timeout_milliseconds := 10000
  );
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.push_notificacao() from public, anon, authenticated;
drop trigger if exists trg_push_notificacao on public.notificacoes;
create trigger trg_push_notificacao after insert on public.notificacoes for each row execute function public.push_notificacao();

-- tempo real: o sino atualiza-se sozinho
do $$ begin
  alter publication supabase_realtime add table public.notificacoes;
exception when duplicate_object then null; when undefined_object then null;
end $$;

-- limpeza: avisos com mais de 60 dias desaparecem
create or replace function public.limpar_notificacoes() returns void
language sql security definer set search_path = public as $$
  delete from notificacoes where criado < now() - interval '60 days';
$$;
revoke all on function public.limpar_notificacoes() from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'limpar-notificacoes';
select cron.schedule('limpar-notificacoes', '17 3 * * *', 'select public.limpar_notificacoes()');
