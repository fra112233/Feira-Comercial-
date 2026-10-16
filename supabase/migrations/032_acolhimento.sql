-- ============================================================
-- Feira Comercial — 032: Acolhimento de quem chega
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Precisa da 022, 025 e 031. Pode ser corrido mais de uma vez sem problema.
--
-- 1) Boas-vindas assinadas pela "Equipa Feira Comercial", com vídeo curto.
-- 2) "Primeiros passos": o site sabe o que já foi feito (foto, cidade, seguir, publicar).
-- 3) Sugestões de empresas para seguir (da mesma província primeiro).
-- 4) Parabéns nas primeiras vezes (no sino 🔔): primeira publicação,
--    primeiro seguidor, primeira mensagem recebida. Cada um só uma vez.
-- ============================================================

-- ---------- 1) Boas-vindas ----------
create or replace function public.boas_vindas()
returns trigger language plpgsql security definer set search_path = public as $$
declare nome text := coalesce(' ' || nullif(split_part(trim(new.full_name), ' ', 1), ''), '');
begin
  if new.id = 'a73d8f73-5b2c-4f03-9deb-17aa890287dd' or new.role in ('admin', 'equipa') then return new; end if;
  if new.idioma = 'en' then
    insert into messages (sender_id, receiver_id, content) values ('a73d8f73-5b2c-4f03-9deb-17aa890287dd', new.id,
      'Hello' || nome || '! 👋 Welcome to Feira Comercial — we are very happy to have you here.' || chr(10) || chr(10) ||
      'Here you can discover businesses and products in Mozambique, follow the ones you like and talk directly to sellers.' || chr(10) || chr(10) ||
      case when new.type = 'empresa'
        then '🏢 Yours is a business account: publish products, promotions and jobs, and complete your profile (logo, contacts, opening hours and location) to build trust.'
        else '👤 Add a profile photo and follow the businesses you like to see their news.' end
      || chr(10) || chr(10) ||
      '✅ On the home page you will find your "First steps" — it only takes 2 minutes.' || chr(10) ||
      'Any question? Just reply to this message, we are here to help.' || chr(10) || chr(10) ||
      'With care,' || chr(10) || 'Feira Comercial Team 💛' || chr(10) || chr(10) ||
      '🔒 We never ask for your password or codes by message.');
  else
    insert into messages (sender_id, receiver_id, content) values ('a73d8f73-5b2c-4f03-9deb-17aa890287dd', new.id,
      'Olá' || nome || '! 👋 Seja muito bem-vindo(a) à Feira Comercial — é uma alegria tê-lo(a) connosco.' || chr(10) || chr(10) ||
      'Aqui pode descobrir empresas e produtos em Moçambique, seguir quem lhe interessa e falar diretamente com os vendedores.' || chr(10) || chr(10) ||
      case when new.type = 'empresa'
        then '🏢 A sua conta é de empresa: publique produtos, promoções e vagas, e complete o perfil (logótipo, contactos, horário e localização) para inspirar confiança.' || chr(10) ||
             '🎬 Veja como em 30 segundos: https://www.feira-comercial.com/media/para-empresas.mp4'
        else '👤 Complete o seu perfil com uma foto e siga as empresas que lhe interessam para ver as novidades.' || chr(10) ||
             '🎬 Veja como funciona em 30 segundos: https://www.feira-comercial.com/media/conheca.mp4' end
      || chr(10) || chr(10) ||
      '✅ Na página inicial tem os seus "Primeiros passos" — leva só 2 minutos.' || chr(10) ||
      'Alguma dúvida? Responda a esta mensagem, estamos aqui para ajudar.' || chr(10) || chr(10) ||
      'Com carinho,' || chr(10) || 'Equipa Feira Comercial 💛' || chr(10) || chr(10) ||
      '🔒 Nunca lhe pedimos a palavra-passe nem códigos por mensagem.');
  end if;
  return new;
exception when others then
  return new;   -- a mensagem nunca impede a criação da conta
end $$;

-- ---------- 2) Primeiros passos ----------
create or replace function public.primeiros_passos()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'tipo',       p.type,
    'foto',       coalesce(nullif(p.avatar_url, ''), '') <> '',
    'local',      coalesce(nullif(trim(p.city), ''), nullif(trim(p.province), '')) is not null,
    'seguindo',   (select count(*) from followers f where f.follower_id = p.id),
    'publicacoes',(select count(*) from posts x where x.user_id = p.id),
    'gostos',     (select count(*) from likes l where l.user_id = p.id),
    'criado',     p.created_at)
  from perfis p where p.id = auth.uid();
$$;
revoke all on function public.primeiros_passos() from public, anon;
grant execute on function public.primeiros_passos() to authenticated;

-- ---------- 3) Sugestões para seguir ----------
create or replace function public.sugestoes_seguir(p_limite int default 6)
returns table (id uuid, full_name text, avatar_url text, city text, province text, sector text, seguidores bigint, oficial boolean)
language sql stable security definer set search_path = public as $$
  with eu as (select id, province from perfis where id = auth.uid())
  select p.id, p.full_name, p.avatar_url, p.city, p.province, p.sector,
         (select count(*) from followers f where f.following_id = p.id) as seguidores,
         p.role in ('admin', 'equipa') as oficial
  from perfis p, eu
  where p.id <> eu.id
    and (p.type = 'empresa' or p.role = 'equipa')
    and coalesce(p.bloqueado, false) = false
    and coalesce(p.visibility, 'publico') = 'publico'
    and not exists (select 1 from followers f where f.follower_id = eu.id and f.following_id = p.id)
    and not exists (select 1 from bloqueios b where (b.blocker_id = eu.id and b.blocked_id = p.id) or (b.blocker_id = p.id and b.blocked_id = eu.id))
  order by (p.role = 'equipa') desc,
           (p.province is not distinct from eu.province) desc,
           seguidores desc,
           (select max(created_at) from posts x where x.user_id = p.id) desc nulls last
  limit greatest(1, least(coalesce(p_limite, 6), 12));
$$;
revoke all on function public.sugestoes_seguir(int) from public, anon;
grant execute on function public.sugestoes_seguir(int) to authenticated;

-- ---------- 4) Parabéns nas primeiras vezes ----------
create table if not exists public.marcos (
  user_id uuid not null references public.perfis(id) on delete cascade,
  tipo    text not null,
  criado  timestamptz not null default now(),
  primary key (user_id, tipo)
);
alter table public.marcos enable row level security;
revoke all on public.marcos from anon, authenticated;

alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo in (
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio',
  'marco_publicacao','marco_seguidor','marco_mensagem'));

-- quem já tinha feito estas coisas não recebe parabéns atrasados
insert into public.marcos (user_id, tipo) select distinct user_id, 'marco_publicacao' from public.posts where user_id is not null on conflict do nothing;
insert into public.marcos (user_id, tipo) select distinct following_id, 'marco_seguidor' from public.followers on conflict do nothing;
insert into public.marcos (user_id, tipo) select distinct receiver_id, 'marco_mensagem' from public.messages
  where sender_id <> 'a73d8f73-5b2c-4f03-9deb-17aa890287dd' and receiver_id in (select id from public.perfis) on conflict do nothing;

create or replace function public.marcar_conquista(p_user uuid, p_tipo text, p_post bigint default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_user = 'a73d8f73-5b2c-4f03-9deb-17aa890287dd' then return; end if;
  insert into marcos (user_id, tipo) values (p_user, p_tipo) on conflict do nothing;
  if not found then return; end if;     -- já tinha recebido estes parabéns
  perform criar_notificacao(p_user, 'a73d8f73-5b2c-4f03-9deb-17aa890287dd', p_tipo, p_post);
exception when others then
  return;   -- nunca impede a publicação, o seguir ou a mensagem
end $$;
revoke all on function public.marcar_conquista(uuid, text, bigint) from public, anon, authenticated;

create or replace function public.marco_publicacao() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform marcar_conquista(new.user_id, 'marco_publicacao', new.id); return null; end $$;
drop trigger if exists trg_marco_publicacao on public.posts;
create trigger trg_marco_publicacao after insert on public.posts for each row execute function public.marco_publicacao();

create or replace function public.marco_seguidor() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform marcar_conquista(new.following_id, 'marco_seguidor'); return null; end $$;
drop trigger if exists trg_marco_seguidor on public.followers;
create trigger trg_marco_seguidor after insert on public.followers for each row execute function public.marco_seguidor();

create or replace function public.marco_mensagem() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- não conta a mensagem de boas-vindas nem mensagens da equipa
  if exists (select 1 from perfis where id = new.sender_id and role in ('admin', 'equipa')) then return null; end if;
  perform marcar_conquista(new.receiver_id, 'marco_mensagem');
  return null;
end $$;
drop trigger if exists trg_marco_mensagem on public.messages;
create trigger trg_marco_mensagem after insert on public.messages for each row execute function public.marco_mensagem();

revoke all on function public.marco_publicacao() from public, anon, authenticated;
revoke all on function public.marco_seguidor() from public, anon, authenticated;
revoke all on function public.marco_mensagem() from public, anon, authenticated;
