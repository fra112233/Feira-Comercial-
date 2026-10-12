-- ============================================================
-- Feira Comercial — 017: pequenos ajustes de segurança (alertas do Supabase)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- ============================================================

-- a função do gatilho das notificações não deve poder ser chamada por fora
revoke all on function public.notificar_mensagem() from public, anon, authenticated;

-- caminho de procura fixo na função que numera os recibos
alter function public.numerar_recibo() set search_path = public;
