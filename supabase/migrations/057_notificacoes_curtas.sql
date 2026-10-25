-- Notificações não ficam guardadas muito tempo (pedido de 25/10/2026):
--   • já vistas (lidas) com mais de 3 dias → apagadas
--   • qualquer notificação com mais de 5 dias → apagada (mesmo não vista)
--   • avisos de lojas/ofertas/resumo continuam a sair aos 3 dias, vistos ou não
-- Corre todas as noites às 03:17 (tarefa "limpar-notificacoes", já existente).
create or replace function public.limpar_notificacoes()
returns void
language sql
security definer
set search_path to 'public'
as $$
  delete from notificacoes
   where criado < now() - interval '3 days'
     and (lida or tipo in ('lojas_hoje', 'publicacao', 'oferta_loja', 'oferta_guardado', 'resumo_semanal'));
  delete from notificacoes where criado < now() - interval '5 days';
$$;

revoke all on function public.limpar_notificacoes() from public, anon, authenticated;
