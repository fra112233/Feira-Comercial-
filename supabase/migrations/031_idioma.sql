-- ============================================================
-- Feira Comercial — 031: idioma de cada conta (português / inglês)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • Cada conta guarda o idioma escolhido (pt ou en).
-- • A mensagem de boas-vindas e os avisos no telemóvel saem nesse idioma.
-- • Os e-mails usam o mesmo idioma (modelos no Supabase → Authentication → Emails).
-- ============================================================

alter table public.perfis add column if not exists idioma text not null default 'pt';
alter table public.perfis drop constraint if exists perfis_idioma_check;
alter table public.perfis add constraint perfis_idioma_check check (idioma in ('pt', 'en'));
grant update (idioma) on public.perfis to authenticated;

-- no registo, o idioma vem do formulário (dados da conta)
create or replace function public.idioma_inicial()
returns trigger language plpgsql security definer set search_path = public, auth as $$
declare l text;
begin
  select raw_user_meta_data->>'idioma' into l from auth.users where id = new.id;
  if l in ('pt', 'en') then new.idioma := l; end if;
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists trg_idioma_inicial on public.perfis;
create trigger trg_idioma_inicial before insert on public.perfis
  for each row execute function public.idioma_inicial();
revoke all on function public.idioma_inicial() from public, anon, authenticated;

-- boas-vindas no idioma da pessoa
create or replace function public.boas_vindas()
returns trigger language plpgsql security definer set search_path = public as $$
declare nome text := coalesce(' ' || nullif(split_part(trim(new.full_name), ' ', 1), ''), '');
begin
  if new.id = 'a73d8f73-5b2c-4f03-9deb-17aa890287dd' or new.role in ('admin', 'equipa') then return new; end if;
  if new.idioma = 'en' then
    insert into messages (sender_id, receiver_id, content) values ('a73d8f73-5b2c-4f03-9deb-17aa890287dd', new.id,
      'Hello' || nome || '! 👋 Welcome to Feira Comercial.' || chr(10) || chr(10) ||
      'Here you can discover businesses and products in Mozambique, follow the ones you like and talk directly to sellers.' || chr(10) || chr(10) ||
      case when new.type = 'empresa'
        then '🏢 Yours is a business account: publish products, promotions and jobs, and complete your profile (logo, contacts, opening hours and location) to build trust.'
        else '👤 Add a profile photo and follow the businesses you like to see their news.' end
      || chr(10) || chr(10) ||
      'Need help? Reply to this message.' || chr(10) ||
      '🔒 Feira Comercial never asks for your password or codes by message.');
  else
    insert into messages (sender_id, receiver_id, content) values ('a73d8f73-5b2c-4f03-9deb-17aa890287dd', new.id,
      'Olá' || nome || '! 👋 Bem-vindo(a) à Feira Comercial.' || chr(10) || chr(10) ||
      'Aqui pode descobrir empresas e produtos em Moçambique, seguir quem lhe interessa e falar diretamente com os vendedores.' || chr(10) || chr(10) ||
      case when new.type = 'empresa'
        then '🏢 A sua conta é de empresa: publique produtos, promoções e vagas, e complete o perfil (logótipo, contactos, horário e localização) para inspirar confiança.'
        else '👤 Complete o seu perfil com uma foto e siga as empresas que lhe interessam para ver as novidades.' end
      || chr(10) || chr(10) ||
      'Precisa de ajuda? Responda a esta mensagem.' || chr(10) ||
      '🔒 A Feira Comercial nunca lhe pede a palavra-passe nem códigos por mensagem.');
  end if;
  return new;
exception when others then
  return new;   -- a mensagem nunca impede a criação da conta
end $$;
