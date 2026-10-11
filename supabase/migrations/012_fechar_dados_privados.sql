-- ============================================================
-- Feira Comercial — 012: Fechar o acesso direto aos dados privados
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
--
-- IMPORTANTE: só correr DEPOIS de a 011 estar aplicada e de o site novo
-- (que lê perfis pela função perfil_completo) estar publicado.
-- Pode ser corrido mais de uma vez sem problema.
-- ============================================================

-- 0) Painel de administração: número de empresas com mensalidade em dia
create or replace function public.admin_empresas_em_dia()
returns integer language sql stable security definer set search_path = public as $$
  select case when public.sou_admin()
    then (select count(*)::int from public.perfis where type = 'empresa' and assinatura_ate > now())
  end;
$$;
revoke execute on function public.admin_empresas_em_dia() from public, anon;
grant execute on function public.admin_empresas_em_dia() to authenticated;

-- 1) Perfis: a tabela só entrega diretamente os campos públicos.
--    NUIT, e-mail, celular, WhatsApp, morada, coordenadas, papel e mensalidade
--    ficam acessíveis apenas pela função perfil_completo (o dono vê tudo;
--    das empresas aparecem os contactos comerciais).
revoke select on public.perfis from authenticated, anon;
grant select (id, username, full_name, avatar_url, type, sector, bio, visibility,
              created_at, gender, city, province, website, facebook, instagram, opening_hours)
  on public.perfis to authenticated;

-- 2) Ficheiros do chat: deixam de ter link público (abrem com links temporários)
update storage.buckets set public = false where id = 'chat-media';

-- 3) Comprovativos e ficheiros de anúncios antigos: limites de tamanho/tipo
update storage.buckets set file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','application/pdf']
  where id = 'arquivos_anuncios';

-- 4) Tabela antiga sem uso (as conversas vêm da tabela messages)
drop table if exists public.conversations;
