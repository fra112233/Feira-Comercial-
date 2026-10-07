-- ============================================================
-- Feira Comercial — 001: tabela "perfis" alinhada com o site
-- Correr UMA vez no Supabase: SQL Editor → New query → colar → Run
-- É seguro correr de novo (usa "if not exists" / "or replace").
-- ============================================================

-- 1) Colunas que as páginas (registo, perfil, amigos) já usam
alter table public.perfis
  add column if not exists email      text,
  add column if not exists phone      text,
  add column if not exists type       text,
  add column if not exists sector     text,
  add column if not exists bio        text,
  add column if not exists morada     text,
  add column if not exists visibility text        not null default 'publico',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- 2) Criar o perfil automaticamente quando alguém se regista.
--    Funciona mesmo com confirmação de e-mail ativa (o site não precisa
--    de sessão para isso), e evita perfis em falta.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfis (id, username, full_name, email, type)
  values (
    new.id,
    split_part(new.email, '@', 1) || '_' || substr(new.id::text, 1, 6),
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.email,
    new.raw_user_meta_data->>'type'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- a função só deve ser chamada pelo trigger, nunca diretamente pelo site
revoke execute on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3) Criar perfis para contas que já existem e ainda não têm
insert into public.perfis (id, username, full_name, email, type)
select u.id,
       split_part(u.email, '@', 1) || '_' || substr(u.id::text, 1, 6),
       coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
       u.email,
       u.raw_user_meta_data->>'type'
from auth.users u
left join public.perfis p on p.id = u.id
where p.id is null;

-- 4) Segurança: as políticas RLS de "perfis" já existem no projeto
--    (todos veem perfis; cada um só edita o seu), por isso não são recriadas.
