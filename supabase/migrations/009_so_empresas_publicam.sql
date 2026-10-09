-- ============================================================
-- Feira Comercial — 009: só as EMPRESAS fazem publicações no feed
-- As contas pessoais continuam a poder publicar stories e vídeos,
-- gostar, comentar, seguir e enviar mensagens.
-- As publicações antigas de contas pessoais ficam como estão.
-- ============================================================
drop policy if exists "Allow insert for authenticated users" on public.posts;
drop policy if exists "posts_criar_se_empresa" on public.posts;
create policy "posts_criar_se_empresa" on public.posts for insert to authenticated
  with check (user_id = (select auth.uid()) and public.sou_empresa());
