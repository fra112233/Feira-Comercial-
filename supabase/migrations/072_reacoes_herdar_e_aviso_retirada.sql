-- 072: duas regras novas para as reações
--  1. Republicar herda as reações: a publicação nova traz as reações da versão anterior
--     (a mesma pessoa continua a contar uma só vez). Copiar não gera avisos ao dono.
--  2. Quem reagiu pode tirar a reação quando quiser, mas o dono da publicação é avisado
--     no sino ("retirou a reação da sua publicação"). Só no sino, sem aviso no telemóvel.
--     Como os outros avisos de gostos, no máximo 1 aviso por pessoa e publicação em 24 h.

-- novo tipo de aviso
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio','marco_publicacao','marco_seguidor',
  'marco_mensagem','gratis_fim','mensalidade_fim','oferta_guardado','oferta_loja','resumo_semanal','lojas_hoje',
  'travao','numero_proibido','cobranca','gosto_story','numero_denunciado','numero_no_perfil','mesmo_aparelho',
  'gosto_retirado']));

-- sem spam: tirar e voltar a pôr várias vezes gera no máximo 1 aviso de cada em 24 h
create or replace function public.criar_notificacao(p_user uuid, p_autor uuid, p_tipo text, p_post bigint default null,
  p_video bigint default null, p_live uuid default null, p_texto text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_user = p_autor then return; end if;                 -- nunca a mim próprio
  if exists (select 1 from bloqueios where blocker_id = p_user and blocked_id = p_autor) then return; end if;
  -- gostos e seguir: não repetir o mesmo aviso em 24 h (tirar e voltar a pôr o gosto não gera spam)
  if p_tipo in ('gosto','gosto_video','seguir','gosto_retirado') and exists (
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

-- aviso de reação nova (não avisa quando as reações são copiadas ao republicar)
create or replace function public.notif_gosto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('fc.sem_avisos', true), '') = '1' then return null; end if;
  perform criar_notificacao((select user_id from posts where id = new.post_id), new.user_id, 'gosto', new.post_id);
  return null;
end $$;

-- aviso de reação retirada. Se a publicação ou a conta forem apagadas, não há aviso:
-- a publicação já não existe (dono = null) ou o autor do aviso já não existe.
create or replace function public.notif_gosto_retirado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('fc.sem_avisos', true), '') = '1' then return null; end if;
  perform criar_notificacao((select user_id from posts where id = old.post_id), old.user_id, 'gosto_retirado', old.post_id);
  return null;
end $$;

drop trigger if exists trg_notif_gosto_retirado on public.likes;
create trigger trg_notif_gosto_retirado after delete on public.likes
  for each row execute function public.notif_gosto_retirado();

-- o aviso de reação retirada fica só no sino (não vai para o telemóvel)
create or replace function public.push_notificacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare tok text;
begin
  if new.tipo = 'gosto_retirado' then return null; end if;
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

-- republicar: copiar as reações da versão anterior mais recente (que já traz as que herdou)
create or replace function public.herdar_reacoes()
returns trigger language plpgsql security definer set search_path = public as $$
declare anterior bigint;
begin
  if new.republicado_de is null then return null; end if;
  select id into anterior from posts
   where id <> new.id and (id = new.republicado_de or republicado_de = new.republicado_de)
   order by created_at desc limit 1;
  if anterior is null then return null; end if;
  perform set_config('fc.sem_avisos', '1', true);
  insert into likes (post_id, user_id, reaction, created_at)
    select new.id, user_id, reaction, created_at from likes where post_id = anterior
    on conflict (post_id, user_id) do nothing;
  perform set_config('fc.sem_avisos', '', true);
  return null;
end $$;

drop trigger if exists trg_herdar_reacoes on public.posts;
create trigger trg_herdar_reacoes after insert on public.posts
  for each row execute function public.herdar_reacoes();

-- republicações que já existem: herdam agora as reações da versão anterior
do $$
declare r record; anterior bigint;
begin
  perform set_config('fc.sem_avisos', '1', true);
  for r in select id, republicado_de, created_at from posts where republicado_de is not null order by created_at loop
    select id into anterior from posts
     where id <> r.id and created_at < r.created_at and (id = r.republicado_de or republicado_de = r.republicado_de)
     order by created_at desc limit 1;
    if anterior is not null then
      insert into likes (post_id, user_id, reaction, created_at)
        select r.id, user_id, reaction, created_at from likes where post_id = anterior
        on conflict (post_id, user_id) do nothing;
    end if;
  end loop;
  perform set_config('fc.sem_avisos', '', true);
end $$;
