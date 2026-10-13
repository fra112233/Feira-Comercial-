-- ============================================================
-- Feira Comercial — 019: Gestão de contas pelo administrador
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • Lista de todas as contas (com pesquisa), último acesso e estado
-- • Mudar uma conta de Pessoa para Empresa (ou o contrário)
-- • Suspender / reativar uma conta: suspensa não publica, não comenta, não faz
--   stories, vídeos, anúncios nem lives, e só pode enviar mensagens à equipa
--   (Administrador / Equipa Feira Comercial) — para poder pedir ajuda
-- • Ver os acessos (sessões): quando, de que aparelho e de que IP
-- • Terminar todas as sessões de uma conta (obriga a entrar de novo)
-- ============================================================

-- 1) Estado da conta
alter table public.perfis add column if not exists bloqueado boolean not null default false;
alter table public.perfis add column if not exists bloqueio_motivo text;

-- só o administrador muda o estado (o próprio utilizador não consegue tirar a suspensão)
create or replace function public.bloquear_mudanca_tipo()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    new.type  := old.type;
    new.role  := old.role;
    new.email := old.email;
    new.id    := old.id;
    new.created_at := old.created_at;
    new.assinatura_ate := old.assinatura_ate;
    new.bloqueado := old.bloqueado;
    new.bloqueio_motivo := old.bloqueio_motivo;
  end if;
  new.updated_at := now();
  return new;
end $$;

-- 2) Conta suspensa: impedir publicar / comentar / etc.
create or replace function public.impedir_se_suspenso()
returns trigger language plpgsql security definer set search_path = public as $$
declare autor uuid; destino uuid;
begin
  if TG_TABLE_NAME = 'messages' then
    autor := new.sender_id; destino := new.receiver_id;
  elsif TG_TABLE_NAME = 'vagas_anuncios' then
    autor := new.empresa_id;
  else
    autor := new.user_id;
  end if;
  if exists (select 1 from perfis where id = autor and bloqueado) then
    -- mensagens para a equipa continuam permitidas (para pedir ajuda)
    if TG_TABLE_NAME = 'messages' and exists (select 1 from perfis where id = destino and role in ('admin', 'equipa')) then
      return new;
    end if;
    raise exception 'Conta suspensa: contacte a equipa da Feira Comercial.' using errcode = 'P0001';
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['posts','stories','comments','messages','videos','video_comments','ad_campaigns','vagas_anuncios','lives'] loop
    execute format('drop trigger if exists trg_suspenso on public.%I', t);
    execute format('create trigger trg_suspenso before insert on public.%I for each row execute function public.impedir_se_suspenso()', t);
  end loop;
end $$;
revoke all on function public.impedir_se_suspenso() from public, anon, authenticated;

-- 3) Lista de contas para o administrador
create or replace function public.admin_contas(p_pesquisa text default '')
returns table (
  id uuid, full_name text, username text, email text, avatar_url text, type text, role text,
  city text, province text, criado timestamptz, ultimo_acesso timestamptz,
  bloqueado boolean, bloqueio_motivo text, assinatura_ate timestamptz,
  publicacoes bigint, pagamentos_confirmados bigint, pagamentos_recusados bigint
) language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  select p.id, p.full_name, p.username, u.email::text, p.avatar_url, p.type, p.role,
         p.city, p.province, u.created_at, u.last_sign_in_at,
         p.bloqueado, p.bloqueio_motivo, p.assinatura_ate::timestamptz,
         (select count(*) from posts x where x.user_id = p.id),
         (select count(*) from pagamentos g where g.empresa_id = p.id and g.estado = 'confirmado'),
         (select count(*) from pagamentos g where g.empresa_id = p.id and g.estado = 'rejeitado')
  from perfis p join auth.users u on u.id = p.id
  where coalesce(p_pesquisa, '') = ''
     or p.full_name ilike '%' || p_pesquisa || '%'
     or u.email ilike '%' || p_pesquisa || '%'
     or p.username ilike '%' || p_pesquisa || '%'
  order by u.last_sign_in_at desc nulls last
  limit 500;
end $$;

-- 4) Acessos (sessões) de uma conta
create or replace function public.admin_acessos(p_uid uuid)
returns table (inicio timestamptz, ultima_atividade timestamptz, ip text, aparelho text)
language plpgsql stable security definer set search_path = public, auth as $$
#variable_conflict use_column
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  select s.created_at, coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at), host(s.ip), s.user_agent
  from auth.sessions s where s.user_id = p_uid
  order by coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at) desc
  limit 20;
end $$;

-- 5) Ações do administrador
create or replace function public.admin_suspender(p_uid uuid, p_suspender boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_uid = auth.uid() then raise exception 'não pode suspender a própria conta'; end if;
  update perfis set bloqueado = p_suspender,
         bloqueio_motivo = case when p_suspender then left(nullif(trim(p_motivo), ''), 300) else null end
  where id = p_uid;
end $$;

create or replace function public.admin_mudar_tipo(p_uid uuid, p_tipo text)
returns void language plpgsql security definer set search_path = public as $$
declare dias int;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_tipo not in ('singular', 'empresa') then raise exception 'tipo inválido'; end if;
  select coalesce(nullif(valor, '')::int, 30) into dias from config where chave = 'dias_gratis';
  update perfis set type = p_tipo,
         assinatura_ate = case when p_tipo = 'empresa' and assinatura_ate is null
                               then now() + make_interval(days => coalesce(dias, 30)) else assinatura_ate end
  where id = p_uid;
end $$;

create or replace function public.admin_terminar_sessoes(p_uid uuid)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_uid = auth.uid() then raise exception 'use "Sair" para a sua própria conta'; end if;
  delete from auth.sessions where user_id = p_uid;
end $$;

revoke all on function public.admin_contas(text) from public, anon;
revoke all on function public.admin_acessos(uuid) from public, anon;
revoke all on function public.admin_suspender(uuid, boolean, text) from public, anon;
revoke all on function public.admin_mudar_tipo(uuid, text) from public, anon;
revoke all on function public.admin_terminar_sessoes(uuid) from public, anon;
grant execute on function public.admin_contas(text) to authenticated;
grant execute on function public.admin_acessos(uuid) to authenticated;
grant execute on function public.admin_suspender(uuid, boolean, text) to authenticated;
grant execute on function public.admin_mudar_tipo(uuid, text) to authenticated;
grant execute on function public.admin_terminar_sessoes(uuid) to authenticated;

-- ============================================================
-- 6) Conversas: ninguém consegue alterar nem apagar de verdade o que foi enviado
--    • o texto, ficheiros, remetente, destinatário e data nunca mudam depois de enviados
--    • "apagar" e "limpar conversa" só escondem a mensagem de quem apagou; o original fica guardado
--    • só o remetente pode marcar a sua mensagem como apagada; só o destinatário marca como lida
-- ============================================================
create or replace function public.proteger_mensagem()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(auth.role(), '') = 'service_role' or current_user in ('postgres', 'supabase_admin') then
    return new;
  end if;
  new.id := old.id; new.created_at := old.created_at;
  new.sender_id := old.sender_id; new.receiver_id := old.receiver_id;
  new.content := old.content; new.file_url := old.file_url; new.media_type := old.media_type;
  new.file_name := old.file_name; new.file_size := old.file_size; new.reply_to := old.reply_to; new.ref := old.ref;
  if auth.uid() is distinct from old.sender_id then
    new.deleted := old.deleted; new.cleared_by_sender := old.cleared_by_sender;
  end if;
  if auth.uid() is distinct from old.receiver_id then
    new.read_at := old.read_at; new.cleared_by_receiver := old.cleared_by_receiver;
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_mensagem on public.messages;
create trigger trg_proteger_mensagem before update on public.messages
  for each row execute function public.proteger_mensagem();

-- 7) Registo de cada vez que a administração abre uma conversa (com o motivo)
create table if not exists public.registo_admin (
  id bigserial primary key,
  admin_id uuid not null,
  acao text not null,
  conta_a uuid, conta_b uuid,
  motivo text,
  criado timestamptz not null default now()
);
alter table public.registo_admin enable row level security;
revoke all on public.registo_admin from anon, authenticated;

-- com quem uma conta conversou (só nomes e número de mensagens; sem conteúdo)
create or replace function public.admin_conversas_de(p_uid uuid)
returns table (outro uuid, nome text, mensagens bigint, ultima timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  select o.id, o.full_name, count(*), max(m.created_at)
  from messages m
  join perfis o on o.id = case when m.sender_id = p_uid then m.receiver_id else m.sender_id end
  where m.sender_id = p_uid or m.receiver_id = p_uid
  group by o.id, o.full_name
  order by max(m.created_at) desc;
end $$;

-- abrir a conversa entre duas contas (inclui mensagens apagadas) — exige motivo e fica registado
create or replace function public.admin_conversa(p_a uuid, p_b uuid, p_motivo text)
returns table (id bigint, criado timestamptz, de uuid, conteudo text, ficheiro text, tipo_ficheiro text,
               nome_ficheiro text, apagada boolean, limpa_remetente boolean, limpa_destinatario boolean, lida timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if char_length(trim(coalesce(p_motivo, ''))) < 5 then raise exception 'indique o motivo (ex.: denúncia n.º …)'; end if;
  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
  values (auth.uid(), 'abrir_conversa', p_a, p_b, left(trim(p_motivo), 300));
  return query
  select m.id, m.created_at, m.sender_id, m.content, m.file_url, m.media_type, m.file_name,
         coalesce(m.deleted, false), coalesce(m.cleared_by_sender, false), coalesce(m.cleared_by_receiver, false), m.read_at
  from messages m
  where (m.sender_id = p_a and m.receiver_id = p_b) or (m.sender_id = p_b and m.receiver_id = p_a)
  order by m.created_at;
end $$;

-- o administrador consegue abrir as fotos/ficheiros dessas conversas
drop policy if exists chat_media_admin_ver on storage.objects;
create policy chat_media_admin_ver on storage.objects for select to authenticated
  using (bucket_id = 'chat-media' and (select public.sou_admin()));

revoke all on function public.admin_conversas_de(uuid) from public, anon;
revoke all on function public.admin_conversa(uuid, uuid, text) from public, anon;
grant execute on function public.admin_conversas_de(uuid) to authenticated;
grant execute on function public.admin_conversa(uuid, uuid, text) to authenticated;
