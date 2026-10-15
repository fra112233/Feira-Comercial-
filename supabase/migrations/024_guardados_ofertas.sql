-- ============================================================
-- Feira Comercial — 024: Guardar publicações e Ofertas relâmpago
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- 1) Cada pessoa pode guardar publicações (🔖) para ver mais tarde.
-- 2) As empresas podem marcar uma publicação como Oferta relâmpago:
--    preço, preço antes (opcional) e hora a que termina (até 7 dias).
-- ============================================================

-- ---------- 1) Guardados ----------
create table if not exists public.guardados (
  user_id  uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  post_id  bigint not null references public.posts(id) on delete cascade,
  criado   timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index if not exists guardados_post_idx on public.guardados (post_id);
alter table public.guardados enable row level security;
revoke all on public.guardados from anon, authenticated;
grant select, insert, delete on public.guardados to authenticated;

drop policy if exists guardados_ver on public.guardados;
create policy guardados_ver on public.guardados for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists guardados_criar on public.guardados;
create policy guardados_criar on public.guardados for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists guardados_apagar on public.guardados;
create policy guardados_apagar on public.guardados for delete to authenticated using (user_id = (select auth.uid()));

-- ---------- 2) Ofertas relâmpago ----------
alter table public.posts add column if not exists oferta_preco        numeric(12,2);
alter table public.posts add column if not exists oferta_preco_antigo numeric(12,2);
alter table public.posts add column if not exists oferta_ate          timestamptz;
create index if not exists posts_oferta_idx on public.posts (oferta_ate) where oferta_ate is not null;

create or replace function public.validar_oferta() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.oferta_ate is null then
    new.oferta_preco := null; new.oferta_preco_antigo := null;
    return new;
  end if;
  if new.oferta_preco is null or new.oferta_preco <= 0 then
    raise exception 'Indique o preço da oferta.' using errcode = 'P0001';
  end if;
  if new.oferta_preco_antigo is not null and new.oferta_preco_antigo <= new.oferta_preco then
    raise exception 'O preço antes deve ser maior do que o preço da oferta.' using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' or new.oferta_ate is distinct from old.oferta_ate then
    if new.oferta_ate <= now() or new.oferta_ate > now() + interval '7 days 5 minutes' then
      raise exception 'A oferta deve terminar entre agora e 7 dias.' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_validar_oferta on public.posts;
create trigger trg_validar_oferta before insert or update of oferta_preco, oferta_preco_antigo, oferta_ate on public.posts
  for each row execute function public.validar_oferta();

-- o aviso aos seguidores diz que é uma oferta (só se a migração 022 já estiver aplicada)
do $$ begin
  if to_regprocedure('public.notificar_seguidores(uuid, text, bigint, bigint, uuid, text)') is not null then
    execute $f$
      create or replace function public.notif_publicacao() returns trigger
      language plpgsql security definer set search_path = public as $b$
      begin
        perform notificar_seguidores(new.user_id, 'publicacao', new.id, null, null,
          case when new.oferta_ate is not null
               then '⚡ Oferta: ' || replace(to_char(round(new.oferta_preco), 'FM999,999,990'), ',', ' ') || ' MT' || coalesce(' · ' || nullif(trim(new.content), ''), '')
               else new.content end);
        return null;
      end $b$;
    $f$;
    revoke all on function public.notif_publicacao() from public, anon, authenticated;
  end if;
end $$;
