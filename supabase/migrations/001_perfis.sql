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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3) Criar perfis para contas que já existem e ainda não têm
insert into public.perfis (id, username, full_name, email)
select u.id,
       split_part(u.email, '@', 1) || '_' || substr(u.id::text, 1, 6),
       coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
       u.email
from auth.users u
left join public.perfis p on p.id = u.id
where p.id is null;

-- 4) Segurança (RLS): qualquer utilizador com sessão vê perfis;
--    cada um só altera o seu.
alter table public.perfis enable row level security;

drop policy if exists "perfis_ver_autenticados" on public.perfis;
create policy "perfis_ver_autenticados" on public.perfis
  for select to authenticated using (true);

drop policy if exists "perfis_editar_o_meu" on public.perfis;
create policy "perfis_editar_o_meu" on public.perfis
  for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);
