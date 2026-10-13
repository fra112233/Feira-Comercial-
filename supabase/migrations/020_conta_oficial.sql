-- ============================================================
-- Feira Comercial — 020: Conta oficial "Feira Comercial" (estilo conta verificada)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • Perfil da conta oficial completo e profissional (Maputo, site, e-mail, setor)
-- • Selo "Oficial" ao lado do nome em todo o site
-- • Ninguém mais pode usar nomes como "Feira Comercial", "Administrador" ou
--   "Moderador" (evita contas falsas a fingir ser a equipa)
-- • Cada conta nova recebe uma mensagem de boas-vindas da conta oficial
-- ============================================================

-- 1) Perfil da conta oficial
update public.perfis set
  full_name = 'Feira Comercial',
  username  = 'feiracomercial',
  city      = 'Maputo',
  province  = 'Maputo Cidade',
  sector    = 'Plataforma digital · Comércio',
  website   = 'www.feira-comercial.com',
  email     = 'contacto@feira-comercial.com',
  bio       = 'Conta oficial da Feira Comercial, a rede social de pessoas e empresas em Moçambique. '
           || 'Aqui publicamos avisos, novidades e dicas para usar a plataforma. '
           || 'Precisa de ajuda? Envie-nos uma mensagem. Nunca pedimos a sua palavra-passe nem códigos.'
where id = 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';

-- 2) Texto do selo: "Oficial" (conta da equipa) e "Administrador"
create or replace function public.selos()
returns table (id uuid, selo text) language sql stable security definer set search_path = public as $$
  select p.id,
         case p.role when 'admin' then 'Administrador' when 'equipa' then 'Oficial' end
  from perfis p
  where p.role in ('admin', 'equipa');
$$;
revoke all on function public.selos() from public;
grant execute on function public.selos() to anon, authenticated;

-- 3) Impedir contas falsas a fingir ser a Feira Comercial
create or replace function public.impedir_nome_oficial()
returns trigger language plpgsql set search_path = public as $$
declare nome text; utl text;
begin
  if coalesce(auth.role(), '') = 'service_role' then return new; end if;
  if new.role in ('admin', 'equipa') then return new; end if;
  if tg_op = 'UPDATE' and new.full_name is not distinct from old.full_name
                      and new.username  is not distinct from old.username then
    return new;
  end if;
  nome := translate(lower(coalesce(new.full_name, '')), 'áàâãéêíóôõúç', 'aaaaeeiooouc');
  utl  := lower(coalesce(new.username, ''));
  if nome ~ 'feira\s*comercia' or nome ~ '\m(administra\w*|admin|moderador\w*)\M'
     -- o utilizador (@) só é verificado quando a pessoa o muda (no registo é gerado a partir do e-mail)
     or (tg_op = 'UPDATE' and new.username is distinct from old.username and utl ~ '(feira.?comercia|^admin|^moderador)') then
    raise exception 'Nome reservado: não pode usar "Feira Comercial", "Administrador" ou "Moderador" no nome.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_nome_oficial on public.perfis;
create trigger trg_nome_oficial before insert or update on public.perfis
  for each row execute function public.impedir_nome_oficial();
revoke all on function public.impedir_nome_oficial() from public, anon, authenticated;

-- 4) Mensagem de boas-vindas da conta oficial a cada conta nova
create or replace function public.boas_vindas()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.id = 'a73d8f73-5b2c-4f03-9deb-17aa890287dd' or new.role in ('admin', 'equipa') then return new; end if;
  insert into messages (sender_id, receiver_id, content) values (
    'a73d8f73-5b2c-4f03-9deb-17aa890287dd', new.id,
    'Olá' || coalesce(' ' || nullif(split_part(trim(new.full_name), ' ', 1), ''), '') || '! 👋 Bem-vindo(a) à Feira Comercial.' || chr(10) || chr(10) ||
    'Aqui pode descobrir empresas e produtos em Moçambique, seguir quem lhe interessa e falar diretamente com os vendedores.' || chr(10) || chr(10) ||
    case when new.type = 'empresa'
      then '🏢 A sua conta é de empresa: publique produtos, promoções e vagas, e complete o perfil (logótipo, contactos, horário e localização) para inspirar confiança.'
      else '👤 Complete o seu perfil com uma foto e siga as empresas que lhe interessam para ver as novidades.' end
    || chr(10) || chr(10) ||
    'Precisa de ajuda? Responda a esta mensagem.' || chr(10) ||
    '🔒 A Feira Comercial nunca lhe pede a palavra-passe nem códigos por mensagem.');
  return new;
exception when others then
  return new;   -- a mensagem nunca impede a criação da conta
end $$;
drop trigger if exists trg_boas_vindas on public.perfis;
create trigger trg_boas_vindas after insert on public.perfis
  for each row execute function public.boas_vindas();
revoke all on function public.boas_vindas() from public, anon, authenticated;
