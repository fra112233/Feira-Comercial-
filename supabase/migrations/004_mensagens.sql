-- ============================================================
-- Feira Comercial — 004: mensagens em tempo real
-- Correr UMA vez no Supabase: SQL Editor → New query → colar → Run
-- É seguro correr de novo.
-- ============================================================

-- ---------- Campos novos nas mensagens ----------
alter table public.messages
  add column if not exists media_type   text,                    -- 'image' | 'video' | 'doc'
  add column if not exists file_name    text,
  add column if not exists file_size    text,
  add column if not exists reply_to     bigint references public.messages(id) on delete set null,
  add column if not exists ref          jsonb,                   -- publicação/status citado: {userName, text, thumb}
  add column if not exists reaction     text,
  add column if not exists deleted      boolean not null default false,
  add column if not exists read_at      timestamptz,
  add column if not exists cleared_by_sender   boolean not null default false,  -- "limpar conversa" só para mim
  add column if not exists cleared_by_receiver boolean not null default false;
alter table public.messages alter column sender_id set default auth.uid();

create index if not exists messages_sender_idx   on public.messages (sender_id, created_at desc);
create index if not exists messages_receiver_idx on public.messages (receiver_id, created_at desc);

-- ---------- Bloqueios ----------
create table if not exists public.bloqueios (
  blocker_id uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  blocked_id uuid not null references public.perfis(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
alter table public.bloqueios enable row level security;
drop policy if exists "bloqueios_ver_os_meus" on public.bloqueios;
create policy "bloqueios_ver_os_meus" on public.bloqueios
  for select to authenticated using (blocker_id = auth.uid() or blocked_id = auth.uid());
drop policy if exists "bloqueios_criar" on public.bloqueios;
create policy "bloqueios_criar" on public.bloqueios
  for insert to authenticated with check (blocker_id = auth.uid() and blocked_id <> auth.uid());
drop policy if exists "bloqueios_apagar" on public.bloqueios;
create policy "bloqueios_apagar" on public.bloqueios
  for delete to authenticated using (blocker_id = auth.uid());

-- ---------- Regras das mensagens ----------
-- ver: só quem enviou ou recebeu (agora só para quem tem sessão)
drop policy if exists "Enable read access for all users" on public.messages;
drop policy if exists "mensagens_ver_as_minhas" on public.messages;
create policy "mensagens_ver_as_minhas" on public.messages
  for select to authenticated using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- enviar: como eu, para outra pessoa, que não me bloqueou
drop policy if exists "Permitir envio ao remetente" on public.messages;
drop policy if exists "mensagens_enviar" on public.messages;
create policy "mensagens_enviar" on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and receiver_id is not null
    and receiver_id <> auth.uid()
    and not exists (select 1 from public.bloqueios b
                    where b.blocker_id = messages.receiver_id and b.blocked_id = auth.uid())
  );

-- alterar: só os participantes (o trigger abaixo decide o quê)
drop policy if exists "mensagens_alterar" on public.messages;
create policy "mensagens_alterar" on public.messages
  for update to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id)
  with check (auth.uid() = sender_id or auth.uid() = receiver_id);

-- Proteção: ninguém muda o texto de uma mensagem.
--  • quem enviou pode apagá-la para todos (deleted = true)
--  • quem recebeu pode marcar como lida
--  • ambos podem reagir e "limpar a conversa" para si
create or replace function public.proteger_mensagem()
returns trigger language plpgsql set search_path = public as $$
declare eu uuid := auth.uid();
begin
  if eu is null then return new; end if;   -- SQL Editor / serviço
  new.sender_id := old.sender_id;
  new.receiver_id := old.receiver_id;
  new.created_at := old.created_at;
  new.content := old.content;
  new.file_url := old.file_url;
  new.media_type := old.media_type;
  new.file_name := old.file_name;
  new.file_size := old.file_size;
  new.reply_to := old.reply_to;
  new.ref := old.ref;

  if eu = old.sender_id then
    new.read_at := old.read_at;
    new.cleared_by_receiver := old.cleared_by_receiver;
    if new.deleted and not old.deleted then
      new.content := ''; new.file_url := null; new.file_name := null; new.ref := null; new.reaction := null;
    elsif not new.deleted and old.deleted then
      new.deleted := true;
    end if;
  else
    new.deleted := old.deleted;
    new.cleared_by_sender := old.cleared_by_sender;
    if old.read_at is not null then new.read_at := old.read_at; end if;
  end if;
  return new;
end; $$;

drop trigger if exists messages_proteger on public.messages;
create trigger messages_proteger before update on public.messages
  for each row execute function public.proteger_mensagem();

-- ---------- Ficheiros do chat ----------
-- o bucket "chat-media" já existe (público); cada um envia para a sua pasta
update storage.buckets set public = true, file_size_limit = 52428800 where id = 'chat-media';

-- realtime já inclui a tabela messages
