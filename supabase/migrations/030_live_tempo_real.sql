-- ============================================================
-- Feira Comercial — 030: Live em tempo real, com a hora do servidor
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- 1. Quando alguém entra em direto, TODAS as contas recebem a notificação
--    no mesmo instante (sino + aviso no telemóvel de quem os ligou).
-- 2. Quando a live termina, a notificação muda sozinha para "Terminou"
--    com a data e a hora — também em tempo real.
-- 3. A hora vem sempre do servidor (certa), nunca do relógio do telemóvel.
-- 4. Se o telemóvel de quem transmite desligar ou perder a rede,
--    o servidor fecha a live sozinho ao fim de 2 minutos sem sinal.
-- ============================================================

-- hora certa do servidor (as páginas acertam o relógio do aparelho com esta)
create or replace function public.agora() returns timestamptz
language sql stable as $$ select now() $$;
grant execute on function public.agora() to anon, authenticated;

-- o "ainda estou em direto" passa a usar a hora do servidor
create or replace function public.proteger_live()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.user_id := old.user_id; new.started_at := old.started_at;
    new.atualizado_em := now();
    if old.estado = 'terminada' then new.estado := 'terminada'; new.ended_at := old.ended_at; end if;
    if new.estado = 'terminada' and old.estado <> 'terminada' then new.ended_at := now(); new.espectadores := 0; end if;
  end if;
  return new;
end $$;

-- entrar em direto: avisa todas as contas (menos quem bloqueou esta empresa e contas suspensas)
create or replace function public.notif_live()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.estado is distinct from 'ao_vivo' then return null; end if;
  insert into notificacoes (user_id, autor_id, tipo, live_id, texto)
  select p.id, new.user_id, 'live', new.id, left(nullif(trim(new.titulo), ''), 140)
    from perfis p
   where p.id <> new.user_id
     and not coalesce(p.bloqueado, false)
     and not exists (select 1 from bloqueios b where b.blocker_id = p.id and b.blocked_id = new.user_id);
  return null;
exception when others then
  return null;   -- um aviso que falha nunca impede a live de começar
end $$;
revoke all on function public.notif_live() from public, anon, authenticated;

-- terminar: "toca" nas notificações desta live para os sinos abertos se atualizarem na hora
create or replace function public.notif_live_terminou()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.estado = 'terminada' and old.estado is distinct from 'terminada' then
    update notificacoes set texto = texto where live_id = new.id;
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.notif_live_terminou() from public, anon, authenticated;
drop trigger if exists trg_notif_live_fim on public.lives;
create trigger trg_notif_live_fim after update of estado on public.lives
  for each row execute function public.notif_live_terminou();

-- fecha lives sem sinal há mais de 2 minutos (telemóvel desligado, sem rede, aba fechada à força)
create or replace function public.fechar_lives_paradas()
returns void language sql security definer set search_path = public as $$
  update lives set estado = 'terminada', ended_at = atualizado_em, espectadores = 0
   where estado = 'ao_vivo' and atualizado_em < now() - interval '2 minutes';
$$;
revoke all on function public.fechar_lives_paradas() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'fechar-lives-paradas';
  perform cron.schedule('fechar-lives-paradas', '* * * * *', 'select public.fechar_lives_paradas()');
end $$;

-- lives antigas que ficaram "em direto" por engano
select public.fechar_lives_paradas();
