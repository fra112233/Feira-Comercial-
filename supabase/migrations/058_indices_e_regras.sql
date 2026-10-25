-- ============================================================
-- Feira Comercial — 058: base de dados mais rápida (sem mudar o que cada pessoa pode ver)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- 1) Índices nas ligações entre tabelas que ainda não os tinham
--    (cobranças, registo das cobranças e números proibidos — páginas da equipa).
-- 2) Regras de acesso repetidas juntas numa só por ação. O Postgres corria cada regra
--    em separado para cada linha; agora corre uma. Quem vê / altera o quê fica igual:
--    • pagamentos: a empresa vê os seus; o administrador vê todos.
--    • reclamações: cada pessoa vê as suas; a equipa (administrador e ajudantes) vê e responde a todas.
--      (sou_suporte() já inclui o administrador.)
-- ============================================================

-- 1) Índices
create index if not exists cobrancas_responsavel_idx      on public.cobrancas (responsavel);
create index if not exists cobrancas_registo_por_idx      on public.cobrancas_registo (por);
create index if not exists numeros_proibidos_conta_idx    on public.numeros_proibidos (conta);

-- 2) Pagamentos: ver
drop policy if exists pagamentos_admin_ver    on public.pagamentos;
drop policy if exists pagamentos_ver_os_meus  on public.pagamentos;
drop policy if exists pagamentos_ver          on public.pagamentos;
create policy pagamentos_ver on public.pagamentos for select to authenticated
  using (empresa_id = (select auth.uid()) or (select sou_admin()));

-- 2) Reclamações: ver
drop policy if exists reclamacoes_admin_ver     on public.reclamacoes;
drop policy if exists reclamacoes_ajudante_ver  on public.reclamacoes;
drop policy if exists reclamacoes_ver_proprias  on public.reclamacoes;
drop policy if exists reclamacoes_ver           on public.reclamacoes;
create policy reclamacoes_ver on public.reclamacoes for select to authenticated
  using (user_id = (select auth.uid()) or (select sou_suporte()));

-- 2) Reclamações: responder
drop policy if exists reclamacoes_admin_responder     on public.reclamacoes;
drop policy if exists reclamacoes_ajudante_responder  on public.reclamacoes;
drop policy if exists reclamacoes_responder           on public.reclamacoes;
create policy reclamacoes_responder on public.reclamacoes for update to authenticated
  using ((select sou_suporte())) with check ((select sou_suporte()));
