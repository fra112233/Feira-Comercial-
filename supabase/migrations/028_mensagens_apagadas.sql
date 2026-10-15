-- ============================================================
-- Feira Comercial — 028: Mensagens apagadas ficam só para a equipa
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Antes: "apagar para todos" escondia a mensagem no ecrã, mas o texto continuava
-- na conversa e quem a recebeu ainda o conseguia obter por meios técnicos.
-- Agora: o original é guardado num arquivo que só a equipa vê (para investigar
-- denúncias) e a mensagem fica vazia para as duas pessoas.
-- ============================================================

create table if not exists public.mensagens_apagadas (
  message_id   bigint primary key,
  sender_id    uuid,
  receiver_id  uuid,
  content      text,
  file_url     text,
  media_type   text,
  file_name    text,
  ref          jsonb,
  enviada_em   timestamptz,
  apagada_em   timestamptz not null default now()
);
create index if not exists mensagens_apagadas_conversa_idx on public.mensagens_apagadas (sender_id, receiver_id);
alter table public.mensagens_apagadas enable row level security;
revoke all on public.mensagens_apagadas from anon, authenticated;   -- ninguém lê diretamente; só a função da equipa

-- corre DEPOIS das regras de proteção (o nome começa por "zz" para ser o último)
create or replace function public.arquivar_mensagem_apagada()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.deleted and not coalesce(old.deleted, false) then
    insert into mensagens_apagadas (message_id, sender_id, receiver_id, content, file_url, media_type, file_name, ref, enviada_em)
    values (old.id, old.sender_id, old.receiver_id, old.content, old.file_url, old.media_type, old.file_name, old.ref, old.created_at)
    on conflict (message_id) do nothing;
    new.content := ''; new.file_url := null; new.file_name := null; new.media_type := null; new.ref := null; new.reaction := null;
  end if;
  return new;
end $$;
revoke all on function public.arquivar_mensagem_apagada() from public, anon, authenticated;
drop trigger if exists zz_arquivar_mensagem_apagada on public.messages;
create trigger zz_arquivar_mensagem_apagada before update on public.messages
  for each row execute function public.arquivar_mensagem_apagada();

-- a regra de proteção estava ligada duas vezes (desde a 004 e a 019): fica só uma
drop trigger if exists messages_proteger on public.messages;

-- mensagens que já tinham sido apagadas antes desta migração
insert into public.mensagens_apagadas (message_id, sender_id, receiver_id, content, file_url, media_type, file_name, ref, enviada_em)
select id, sender_id, receiver_id, content, file_url, media_type, file_name, ref, created_at
  from public.messages where deleted and (coalesce(content, '') <> '' or file_url is not null)
on conflict (message_id) do nothing;
update public.messages set content = '', file_url = null, file_name = null, media_type = null, ref = null, reaction = null
 where deleted and (coalesce(content, '') <> '' or file_url is not null);

-- a equipa continua a ver o original ao abrir uma conversa denunciada
create or replace function public.admin_conversa(p_a uuid, p_b uuid, p_motivo text)
returns table(id bigint, criado timestamptz, de uuid, conteudo text, ficheiro text, tipo_ficheiro text, nome_ficheiro text,
              apagada boolean, limpa_remetente boolean, limpa_destinatario boolean, lida timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if char_length(trim(coalesce(p_motivo, ''))) < 5 then raise exception 'indique o motivo (ex.: denúncia n.º …)'; end if;
  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
  values (auth.uid(), 'abrir_conversa', p_a, p_b, left(trim(p_motivo), 300));
  return query
  select m.id, m.created_at, m.sender_id,
         coalesce(a.content, m.content), coalesce(a.file_url, m.file_url), coalesce(a.media_type, m.media_type), coalesce(a.file_name, m.file_name),
         coalesce(m.deleted, false), coalesce(m.cleared_by_sender, false), coalesce(m.cleared_by_receiver, false), m.read_at
  from messages m left join mensagens_apagadas a on a.message_id = m.id
  where (m.sender_id = p_a and m.receiver_id = p_b) or (m.sender_id = p_b and m.receiver_id = p_a)
  order by m.created_at;
end $$;

-- quem apaga a conta leva também o arquivo das suas mensagens apagadas
create or replace function public.limpar_arquivo_ao_apagar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from mensagens_apagadas where sender_id = old.id or receiver_id = old.id;
  return old;
end $$;
revoke all on function public.limpar_arquivo_ao_apagar() from public, anon, authenticated;
drop trigger if exists trg_limpar_arquivo on public.perfis;
create trigger trg_limpar_arquivo before delete on public.perfis for each row execute function public.limpar_arquivo_ao_apagar();
