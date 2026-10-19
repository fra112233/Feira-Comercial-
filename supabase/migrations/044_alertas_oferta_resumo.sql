-- ============================================================
-- Feira Comercial — 044: Alerta de oferta e Resumo da semana
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • Uma empresa põe em oferta uma publicação → quem a GUARDOU recebe aviso.
-- • Uma empresa publica uma oferta nova → quem guardou produtos dessa loja
--   recebe um aviso especial ("fez uma oferta para si"), uma vez por dia.
-- • Domingo às 17h (Maputo): cada pessoa recebe UM resumo da semana
--   ("Esta semana: 12 publicações novas · 3 ofertas · 5 perto de si").
--   Só se houve novidades. No idioma da pessoa.
-- ============================================================

alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio',
  'marco_publicacao','marco_seguidor','marco_mensagem','gratis_fim','mensalidade_fim',
  'oferta_guardado','oferta_loja','resumo_semanal']));

-- texto do preço: "⚡ 1 500 MT (antes 2 000 MT) · descrição"
create or replace function public.texto_oferta(p posts)
returns text language sql stable set search_path = public as $$
  select left('⚡ ' || replace(to_char(round(p.oferta_preco), 'FM999,999,990'), ',', ' ') || ' MT'
    || coalesce(' (antes ' || replace(to_char(round(p.oferta_preco_antigo), 'FM999,999,990'), ',', ' ') || ' MT)', '')
    || coalesce(' · ' || nullif(trim(p.content), ''), ''), 140);
$$;

-- A) publicação guardada posta em oferta → avisa quem a guardou
create or replace function public.notif_oferta_guardado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.oferta_ate is null or new.oferta_ate <= now() then return null; end if;
  if old.oferta_ate is not null and old.oferta_ate > now() then return null; end if;   -- já estava em oferta
  perform criar_notificacao(g.user_id, new.user_id, 'oferta_guardado', new.id, null, null, texto_oferta(new))
     from guardados g where g.post_id = new.id;
  return null;
exception when others then
  return null;
end $$;
drop trigger if exists trg_oferta_guardado on public.posts;
create trigger trg_oferta_guardado after update of oferta_ate on public.posts
  for each row execute function public.notif_oferta_guardado();

-- B) publicação nova: igual a antes (um aviso por empresa por dia), mas numa oferta
--    quem guardou produtos desta loja recebe "fez uma oferta para si"
create or replace function public.notif_publicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  oferta boolean := new.oferta_ate is not null;
  m jsonb := case when jsonb_typeof(new.media) = 'array' then new.media else '[]'::jsonb end;
  hoje timestamptz := date_trunc('day', now() at time zone 'Africa/Maputo') at time zone 'Africa/Maputo';
  txt text;
  fas uuid[] := '{}';
begin
  txt := left(case
    when oferta then '⚡ Oferta: ' || replace(to_char(round(new.oferta_preco), 'FM999,999,990'), ',', ' ') || ' MT'
                     || coalesce(' · ' || nullif(trim(new.content), ''), '')
    else coalesce(nullif(trim(new.content), ''),
                  case when m->0->>'type' = 'video' then '🎥 Vídeo'
                       when jsonb_array_length(m) > 0 or new.image_url is not null then '📷 Foto' end)
  end, 140);

  if oferta then
    -- quem guardou produtos desta loja
    select coalesce(array_agg(distinct g.user_id), '{}') into fas
      from guardados g join posts x on x.id = g.post_id
     where x.user_id = new.user_id and g.user_id <> new.user_id;

    update notificacoes set post_id = new.id, texto = texto_oferta(new), criado = now(), lida = false
     where tipo = 'oferta_loja' and autor_id = new.user_id and criado >= hoje;
    perform criar_notificacao(u, new.user_id, 'oferta_loja', new.id, null, null, texto_oferta(new))
       from unnest(fas) u
      where not exists (select 1 from notificacoes n where n.user_id = u and n.autor_id = new.user_id
                          and n.tipo = 'oferta_loja' and n.criado >= hoje);

    update notificacoes set post_id = new.id, texto = txt, criado = now(), lida = false
     where tipo = 'publicacao' and autor_id = new.user_id and criado >= hoje and not (user_id = any (fas));
  else
    update notificacoes set post_id = new.id, texto = txt, criado = now()
     where tipo = 'publicacao' and autor_id = new.user_id and criado >= hoje and not lida
       and coalesce(texto, '') not like '⚡%';
  end if;

  insert into notificacoes (user_id, autor_id, tipo, post_id, texto)
  select p.id, new.user_id, 'publicacao', new.id, txt
    from perfis p
   where p.id <> new.user_id
     and not (p.id = any (fas))
     and coalesce(p.bloqueado, false) = false
     and not exists (select 1 from bloqueios b where b.blocker_id = p.id and b.blocked_id = new.user_id)
     and not exists (select 1 from notificacoes n
                      where n.user_id = p.id and n.autor_id = new.user_id and n.tipo = 'publicacao'
                        and n.criado >= hoje);
  return null;
exception when others then
  return null;
end $$;

-- C) Resumo da semana (domingo)
create or replace function public.resumo_semanal()
returns int language plpgsql security definer set search_path = public as $$
declare
  equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
  semana text := to_char(now() at time zone 'Africa/Maputo', 'IYYY-IW');
  r record; t text; en boolean; partes text[]; n int := 0;
begin
  for r in
    with novas as (
      select x.user_id, x.oferta_ate is not null oferta, a.province
        from posts x join perfis a on a.id = x.user_id
       where x.created_at > now() - interval '7 days' and coalesce(a.bloqueado, false) = false
    )
    select p.id, p.idioma,
           count(v.*) pubs,
           count(v.*) filter (where v.oferta) ofertas,
           count(v.*) filter (where nullif(trim(p.province), '') is not null and v.province = p.province) perto
      from perfis p
      left join novas v on v.user_id <> p.id
           and not exists (select 1 from bloqueios b where b.blocker_id = p.id and b.blocked_id = v.user_id)
     where coalesce(p.bloqueado, false) = false and p.role <> 'equipa'
     group by p.id, p.idioma
  loop
    if r.pubs = 0 then continue; end if;
    insert into marcos (user_id, tipo) values (r.id, 'resumo_' || semana) on conflict do nothing;
    if not found then continue; end if;          -- já recebeu o desta semana
    en := r.idioma = 'en';
    partes := array[r.pubs || case when en then (case when r.pubs = 1 then ' new post' else ' new posts' end)
                                        else (case when r.pubs = 1 then ' publicação nova' else ' publicações novas' end) end];
    if r.ofertas > 0 then partes := partes || (r.ofertas || case when en then (case when r.ofertas = 1 then ' offer ⚡' else ' offers ⚡' end)
                                                                   else (case when r.ofertas = 1 then ' oferta ⚡' else ' ofertas ⚡' end) end); end if;
    if r.perto > 0 then partes := partes || (r.perto || case when en then ' near you 📍' else ' perto de si 📍' end); end if;
    t := case when en then 'This week: ' else 'Esta semana: ' end || array_to_string(partes, ' · ')
         || case when en then '. See what you missed 👀' else '. Veja o que perdeu 👀' end;
    perform criar_notificacao(r.id, equipa, 'resumo_semanal', null, null, null, t);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.resumo_semanal() from public, anon, authenticated;
revoke all on function public.notif_oferta_guardado() from public, anon, authenticated;

-- domingo às 17:03 em Maputo (15:03 UTC)
do $$ begin
  perform cron.unschedule('resumo-semanal') where exists (select 1 from cron.job where jobname = 'resumo-semanal');
  perform cron.schedule('resumo-semanal', '3 15 * * 0', 'select public.resumo_semanal()');
end $$;
