-- ============================================================
-- Feira Comercial — 021: correções do exame de 13/10/2026
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
-- ============================================================

-- 1) Desempenho: índice que faltava (contagem de visualizações por pessoa)
create index if not exists visualizacoes_user_idx on public.visualizacoes (user_id);

-- 2) Segurança: desligar a API GraphQL, que o site não usa.
--    Assim a lista de tabelas deixa de estar visível por esse caminho.
--    (O site usa só a API normal; nada muda para os utilizadores.)
drop extension if exists pg_graphql;
