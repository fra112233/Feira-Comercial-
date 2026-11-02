-- 074: as funções de gatilho das migrações 072 e 073 não podem ser chamadas pela app
-- (só correm como gatilho; isto só arruma o aviso do verificador de segurança).
revoke all on function public.herdar_reacoes() from public, anon, authenticated;
revoke all on function public.notif_gosto_retirado() from public, anon, authenticated;
revoke all on function public.anuncio_numero_burla() from public, anon, authenticated;
