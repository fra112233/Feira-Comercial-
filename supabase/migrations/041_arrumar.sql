-- ============================================================
-- Feira Comercial — 041: Arrumação (revisão de 19/10)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- A função origem_inicial só serve ao registo de contas (gatilho); ninguém
-- precisa de a chamar diretamente pela API.
-- ============================================================
revoke all on function public.origem_inicial() from public, anon, authenticated;
revoke all on function public.proteger_origem() from public, anon, authenticated;
