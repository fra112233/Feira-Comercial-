-- ============================================================
-- Feira Comercial — 027: Administrador e equipa também publicam
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- As contas com papel 'admin' ou 'equipa' podem publicar no feed, criar anúncios,
-- fazer Live e gerir produtos como uma empresa, sem precisar de mensalidade.
-- ============================================================

create or replace function public.empresa_ativa()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.perfis
     where id = auth.uid()
       and (role in ('admin', 'equipa')
            or (type = 'empresa'
                and (coalesce((select valor from public.config where chave = 'bloquear_sem_pagamento'), 'nao') <> 'sim'
                     or (assinatura_ate is not null and assinatura_ate > now())))));
$$;

create or replace function public.sou_empresa()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and (type = 'empresa' or role in ('admin', 'equipa')));
$$;
