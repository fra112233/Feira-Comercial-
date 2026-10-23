-- ============================================================
-- Feira Comercial — 056: Fechar as funções da equipa a quem não tem sessão
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- O verificador de segurança do Supabase avisou:
--   1) 13 funções do painel (admin_*) podiam ser CHAMADAS por quem não tem sessão.
--      Todas já recusavam ("só o administrador"), por isso nada vazou — mas a porta
--      fica fechada também por fora (só contas com sessão iniciada as podem chamar).
--   2) 8 funções sem "search_path" fixo: ficam presas ao esquema public, para que
--      ninguém as engane com uma tabela/função de outro esquema com o mesmo nome.
-- Ficam abertas a todos, de propósito: montra_publica (montra da loja para quem
-- não tem conta), selos (selos de verificação) e registar_erro (relatório de erros).
-- ============================================================

do $$
declare f record;
begin
  -- 1) funções da equipa: só para contas com sessão (e cada uma continua a verificar se é admin/suporte)
  for f in
    select p.oid::regprocedure as assinatura
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and (p.proname like 'admin\_%' or p.proname like 'suporte\_%' or p.proname like 'equipa\_%')
  loop
    execute format('revoke execute on function %s from public, anon', f.assinatura);
    execute format('grant execute on function %s to authenticated', f.assinatura);
  end loop;

  -- 2) search_path fixo
  for f in
    select p.oid::regprocedure as assinatura
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('nome_normalizado','proteger_revisto','numeros_em','sinal_burla','proteger_alerta',
                         'dia_maputo','hoje_maputo','inicio_mes_maputo')
  loop
    execute format('alter function %s set search_path = public', f.assinatura);
  end loop;
end $$;
