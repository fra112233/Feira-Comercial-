-- ============================================================
-- Feira Comercial — 015: Notificações push (mensagens novas)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Quando alguém recebe uma mensagem, o telemóvel/computador mostra um aviso
-- (mesmo com a aplicação fechada) e o número no ícone da aplicação.
-- ============================================================

create extension if not exists pg_net;

-- 1) Onde cada aparelho está registado para receber avisos
create table if not exists public.push_subscricoes (
  id         bigserial primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  endpoint   text not null unique,
  p256dh     text not null,
  auth       text not null,
  criado     timestamptz not null default now()
);
create index if not exists push_subscricoes_user_idx on public.push_subscricoes(user_id);
alter table public.push_subscricoes enable row level security;
revoke all on public.push_subscricoes from anon, authenticated;

-- 2) Segredos do servidor (chaves VAPID e senha interna) — ninguém de fora lê
create table if not exists public.push_segredo (
  id     int primary key default 1 check (id = 1),
  token  text not null,
  vapid  jsonb
);
alter table public.push_segredo enable row level security;
revoke all on public.push_segredo from anon, authenticated;
insert into public.push_segredo (id, token)
values (1, replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (id) do nothing;

-- 3) O utilizador regista / remove o seu aparelho
create or replace function public.guardar_push(p_endpoint text, p_p256dh text, p_auth text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sem sessão'; end if;
  insert into push_subscricoes (user_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth, criado = now();
end $$;

create or replace function public.apagar_push(p_endpoint text)
returns void language sql security definer set search_path = public as $$
  delete from push_subscricoes where endpoint = p_endpoint and user_id = auth.uid();
$$;

revoke all on function public.guardar_push(text, text, text) from public, anon;
revoke all on function public.apagar_push(text) from public, anon;
grant execute on function public.guardar_push(text, text, text) to authenticated;
grant execute on function public.apagar_push(text) to authenticated;

-- 4) Mensagem nova → chama a função "push" (só se o destinatário tiver aparelhos registados)
create or replace function public.notificar_mensagem()
returns trigger language plpgsql security definer set search_path = public as $$
declare tok text;
begin
  if coalesce(new.deleted, false) then return new; end if;
  if not exists (select 1 from push_subscricoes where user_id = new.receiver_id) then return new; end if;
  select token into tok from push_segredo where id = 1;
  if tok is null then return new; end if;
  perform net.http_post(
    url := 'https://bljnkwrhqnpawclybqrw.supabase.co/functions/v1/push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJsam5rd3JocW5wYXdjbHlicXJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3Njg1OTMsImV4cCI6MjA5MTM0NDU5M30.CX2UVsuUllQuqDWDfTop2Bb3f8IM9OzdGM3jUKToO78',
      'x-push-token', tok),
    body := jsonb_build_object('mensagem', new.id),
    timeout_milliseconds := 10000
  );
  return new;
exception when others then
  return new;   -- um aviso que falha nunca impede a mensagem de ser enviada
end $$;

drop trigger if exists trg_notificar_mensagem on public.messages;
create trigger trg_notificar_mensagem
  after insert on public.messages
  for each row execute function public.notificar_mensagem();
