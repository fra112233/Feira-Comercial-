-- ============================================================
-- Feira Comercial — 014: Limpeza automática de conteúdo expirado
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Todas as noites às 03:15 (Maputo) chama a função "limpeza-expirados", que
-- apaga publicações e stories com mais de 48 h (já invisíveis desde as 36 h)
-- e os ficheiros que só elas usavam. Não toca em perfis, anúncios, vídeos,
-- chat nem comprovativos. A chave usada é a chave pública (anon) do site.
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- simulação imediata: mostra o que seria apagado, sem apagar nada
-- (o resultado fica em net._http_response)
select net.http_get(
  url := 'https://bljnkwrhqnpawclybqrw.supabase.co/functions/v1/limpeza-expirados?simular=1',
  headers := jsonb_build_object('Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJsam5rd3JocW5wYXdjbHlicXJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3Njg1OTMsImV4cCI6MjA5MTM0NDU5M30.CX2UVsuUllQuqDWDfTop2Bb3f8IM9OzdGM3jUKToO78')
);

-- agendamento diário: 01:15 UTC = 03:15 em Maputo
select cron.unschedule(jobid) from cron.job where jobname = 'limpeza-expirados';
select cron.schedule(
  'limpeza-expirados',
  '15 1 * * *',
  $$ select net.http_post(
       url := 'https://bljnkwrhqnpawclybqrw.supabase.co/functions/v1/limpeza-expirados',
       headers := jsonb_build_object(
         'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJsam5rd3JocW5wYXdjbHlicXJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3Njg1OTMsImV4cCI6MjA5MTM0NDU5M30.CX2UVsuUllQuqDWDfTop2Bb3f8IM9OzdGM3jUKToO78',
         'Content-Type', 'application/json'),
       body := '{}'::jsonb,
       timeout_milliseconds := 60000
     ) $$
);
