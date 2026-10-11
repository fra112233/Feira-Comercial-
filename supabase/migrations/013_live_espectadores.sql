-- ============================================================
-- Feira Comercial — 013: Número de pessoas a ver cada Live
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- A empresa que está em direto atualiza este número quando alguém entra
-- ou sai. A lista de lives mostra "12/15" e avisa quando a live está cheia.
-- ============================================================

alter table public.lives add column if not exists espectadores int not null default 0
  check (espectadores >= 0 and espectadores <= 1000);

-- ao terminar, deixa de contar espectadores
create or replace function public.proteger_live()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.user_id := old.user_id; new.started_at := old.started_at;
    if old.estado = 'terminada' then new.estado := 'terminada'; end if;
    if new.estado = 'terminada' and old.estado <> 'terminada' then new.ended_at := now(); new.espectadores := 0; end if;
  end if;
  return new;
end $$;
