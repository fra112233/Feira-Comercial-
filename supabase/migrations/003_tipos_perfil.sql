-- ============================================================
-- Feira Comercial — 003: perfis de EMPRESA e de PESSOA
-- Correr UMA vez no Supabase: SQL Editor → New query → colar → Run
-- (depois do 002_feed.sql). É seguro correr de novo.
-- ============================================================

-- ---------- Campos novos ----------
alter table public.perfis
  add column if not exists gender        text,            -- pessoa
  add column if not exists city          text,            -- cidade / distrito
  add column if not exists province      text,            -- província
  add column if not exists whatsapp      text,            -- empresa
  add column if not exists website       text,
  add column if not exists facebook      text,
  add column if not exists instagram     text,
  add column if not exists nuit          text,
  add column if not exists latitude      double precision,
  add column if not exists longitude     double precision,
  -- horário: {"seg":{"aberto":true,"de":"08:00","ate":"17:00"}, "ter":{...}, ... "dom":{"aberto":false}}
  add column if not exists opening_hours jsonb;

-- tipo de conta: 'singular' (pessoa) ou 'empresa'
update public.perfis set type = 'singular' where type is null or type not in ('singular', 'empresa');
alter table public.perfis alter column type set default 'singular';
alter table public.perfis alter column type set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'perfis_type_check') then
    alter table public.perfis add constraint perfis_type_check check (type in ('singular', 'empresa'));
  end if;
end $$;

-- ---------- Registo: copiar TODOS os dados do formulário para o perfil ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  tipo text := case when m->>'type' = 'empresa' then 'empresa' else 'singular' end;
begin
  insert into public.perfis (
    id, username, full_name, email, type,
    phone, whatsapp, gender, morada, city, province,
    sector, nuit, bio, website, latitude, longitude, opening_hours
  )
  values (
    new.id,
    split_part(new.email, '@', 1) || '_' || substr(new.id::text, 1, 6),
    coalesce(nullif(m->>'full_name', ''), split_part(new.email, '@', 1)),
    new.email,
    tipo,
    nullif(m->>'phone', ''),
    nullif(m->>'whatsapp', ''),
    nullif(m->>'gender', ''),
    nullif(m->>'morada', ''),
    nullif(m->>'city', ''),
    nullif(m->>'province', ''),
    nullif(m->>'sector', ''),
    nullif(m->>'nuit', ''),
    nullif(m->>'bio', ''),
    nullif(m->>'website', ''),
    nullif(m->>'latitude', '')::double precision,
    nullif(m->>'longitude', '')::double precision,
    case when jsonb_typeof(m->'opening_hours') = 'object' then m->'opening_hours' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- ---------- O tipo de conta não pode ser mudado pelo próprio utilizador ----------
-- (evita que uma pessoa se transforme em "empresa" para publicar anúncios)
create or replace function public.bloquear_mudanca_tipo()
returns trigger language plpgsql as $$
begin
  if new.type is distinct from old.type and coalesce(auth.role(), '') <> 'service_role' and current_user <> 'postgres' then
    new.type := old.type;
  end if;
  new.updated_at := now();
  return new;
end; $$;

drop trigger if exists perfis_bloquear_tipo on public.perfis;
create trigger perfis_bloquear_tipo before update on public.perfis
  for each row execute function public.bloquear_mudanca_tipo();

-- ---------- Função de ajuda: o utilizador atual é uma empresa? ----------
create or replace function public.sou_empresa()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and type = 'empresa');
$$;
revoke execute on function public.sou_empresa() from public, anon;
grant execute on function public.sou_empresa() to authenticated;

-- ---------- Privacidade: só quem tem conta vê os perfis ----------
-- (antes qualquer pessoa na internet, mesmo sem conta, podia ler telefones e moradas)
drop policy if exists "Enable read access for all users" on public.perfis;
drop policy if exists "perfis_ver_autenticados" on public.perfis;
create policy "perfis_ver_autenticados" on public.perfis
  for select to authenticated using (true);

-- ---------- Só EMPRESAS publicam vagas, anúncios e campanhas ----------
drop policy if exists "Apenas empresas podem publicar vagas" on public.vagas_anuncios;
drop policy if exists "vagas_criar_se_empresa" on public.vagas_anuncios;
create policy "vagas_criar_se_empresa" on public.vagas_anuncios
  for insert to authenticated
  with check (empresa_id = auth.uid() and public.sou_empresa());
drop policy if exists "vagas_mudar_as_minhas" on public.vagas_anuncios;
create policy "vagas_mudar_as_minhas" on public.vagas_anuncios
  for update to authenticated using (empresa_id = auth.uid()) with check (empresa_id = auth.uid());
drop policy if exists "vagas_apagar_as_minhas" on public.vagas_anuncios;
create policy "vagas_apagar_as_minhas" on public.vagas_anuncios
  for delete to authenticated using (empresa_id = auth.uid());

drop policy if exists "campanhas_ver" on public.ad_campaigns;
create policy "campanhas_ver" on public.ad_campaigns
  for select to authenticated using (true);
drop policy if exists "campanhas_criar_se_empresa" on public.ad_campaigns;
create policy "campanhas_criar_se_empresa" on public.ad_campaigns
  for insert to authenticated
  with check (user_id = auth.uid() and public.sou_empresa());
drop policy if exists "campanhas_mudar_as_minhas" on public.ad_campaigns;
create policy "campanhas_mudar_as_minhas" on public.ad_campaigns
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "campanhas_apagar_as_minhas" on public.ad_campaigns;
create policy "campanhas_apagar_as_minhas" on public.ad_campaigns
  for delete to authenticated using (user_id = auth.uid());

-- Posts normais: pessoas E empresas podem publicar (regra "Allow insert for authenticated users").
-- Esta regra antiga era enganadora (não impedia nada), por isso sai:
drop policy if exists "Apenas empresas podem publicar" on public.posts;

-- ---------- Seguidores: regras que faltavam (a tabela não deixava ler nem gravar) ----------
drop policy if exists "seguidores_ver" on public.followers;
create policy "seguidores_ver" on public.followers
  for select to authenticated using (true);
drop policy if exists "seguir_como_eu" on public.followers;
create policy "seguir_como_eu" on public.followers
  for insert to authenticated with check (follower_id = auth.uid() and following_id <> auth.uid());
drop policy if exists "deixar_de_seguir" on public.followers;
create policy "deixar_de_seguir" on public.followers
  for delete to authenticated using (follower_id = auth.uid());
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'followers_unico') then
    alter table public.followers add constraint followers_unico unique (follower_id, following_id);
  end if;
end $$;
