-- ============================================================
-- Feira Comercial — 040: 15 dias grátis e aviso quando acabam
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • Empresas novas passam a ter 15 dias grátis (as que já existem não mudam).
-- • Quando os dias grátis (ou a mensalidade) acabam, a empresa recebe UMA
--   notificação no sino e no telemóvel. A conta NÃO é bloqueada
--   (configuração 'bloquear_sem_pagamento' continua 'nao').
-- • Verifica a cada hora; cada fim de período só é avisado uma vez.
-- ============================================================

update public.config set valor = '15' where chave = 'dias_gratis';

alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio',
  'marco_publicacao','marco_seguidor','marco_mensagem','gratis_fim','mensalidade_fim']));

create or replace function public.avisar_fim_periodo()
returns int language plpgsql security definer set search_path = public as $$
declare
  equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
  p record; tipo text; n int := 0; valor text;
begin
  select coalesce(nullif(c.valor, ''), '100') into valor from config c where c.chave = 'mensalidade_valor';
  for p in
    select x.id, x.assinatura_ate from perfis x
     where x.type = 'empresa' and x.role not in ('admin', 'equipa')
       and coalesce(x.bloqueado, false) = false
       and x.assinatura_ate <= now() and x.assinatura_ate > now() - interval '3 days'
  loop
    -- cada fim de período só é avisado uma vez
    insert into marcos (user_id, tipo) values (p.id, 'fim_' || to_char(p.assinatura_ate, 'YYYYMMDDHH24MI')) on conflict do nothing;
    if not found then continue; end if;
    tipo := case when exists (select 1 from pagamentos g where g.empresa_id = p.id and g.estado = 'confirmado')
                 then 'mensalidade_fim' else 'gratis_fim' end;
    perform criar_notificacao(p.id, equipa, tipo, null, null, null,
      'Pague ' || coalesce(valor, '100') || ' MT para continuar a mostrar a sua loja.');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.avisar_fim_periodo() from public, anon, authenticated;

-- a cada hora, ao minuto 7
do $$ begin
  perform cron.unschedule('avisar-fim-periodo') where exists (select 1 from cron.job where jobname = 'avisar-fim-periodo');
  perform cron.schedule('avisar-fim-periodo', '7 * * * *', 'select public.avisar_fim_periodo()');
end $$;
