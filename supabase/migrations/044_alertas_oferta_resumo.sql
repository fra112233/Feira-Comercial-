-- ============================================================
-- Feira Comercial — 044: Notificações calmas (para não sufocar ninguém)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • Lojas que publicam → UMA linha por dia no sino, que se atualiza sozinha:
--   "Sapataria Boa e mais 10 lojas publicaram hoje". Não toca no telemóvel.
-- • O telemóvel só toca com ofertas ⚡ de lojas que a pessoa segue ou de que
--   guardou produtos (no máximo 2 por dia). Enquanto a Feira tiver até 2 000
--   pessoas, as ofertas de todas as lojas contam.
-- • Publicação guardada posta em oferta → aviso a quem a guardou.
-- • Avisos de lojas apagam-se ao fim de 3 dias (os pessoais ficam 60 dias).
-- • Cada pessoa escolhe: Avisos de lojas = Todos / Só ofertas / Nenhum.
-- • Domingo às 17h: UM resumo da semana.
-- • Até 2 000 pessoas entram todas as lojas; depois, só as que a pessoa
--   segue (e as ofertas da sua província). Valor em config 'notificar_todos_ate'.
-- ============================================================

-- preferências e números
alter table public.perfis add column if not exists avisos_lojas text not null default 'todos';
alter table public.perfis drop constraint if exists perfis_avisos_lojas_check;
alter table public.perfis add constraint perfis_avisos_lojas_check check (avisos_lojas in ('todos', 'ofertas', 'nenhum'));
insert into public.config (chave, valor) values ('notificar_todos_ate', '2000') on conflict (chave) do nothing;

-- a linha "lojas que publicaram hoje" guarda a lista das lojas
alter table public.notificacoes add column if not exists lojas uuid[];
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio',
  'marco_publicacao','marco_seguidor','marco_mensagem','gratis_fim','mensalidade_fim',
  'oferta_guardado','oferta_loja','resumo_semanal','lojas_hoje']));
create index if not exists notificacoes_tipo_dia_idx on public.notificacoes (tipo, autor_id, criado desc);

-- a linha das lojas não faz tocar o telemóvel
drop trigger if exists trg_push_notificacao on public.notificacoes;
create trigger trg_push_notificacao after insert on public.notificacoes
  for each row when (new.tipo <> 'lojas_hoje') execute function public.push_notificacao();

-- texto do preço: "⚡ 1 500 MT (antes 2 000 MT) · descrição"
create or replace function public.texto_oferta(p posts)
returns text language sql stable set search_path = public as $$
  select left('⚡ ' || replace(to_char(round(p.oferta_preco), 'FM999,999,990'), ',', ' ') || ' MT'
    || coalesce(' (antes ' || replace(to_char(round(p.oferta_preco_antigo), 'FM999,999,990'), ',', ' ') || ' MT)', '')
    || coalesce(' · ' || nullif(trim(p.content), ''), ''), 140);
$$;

-- quantos toques de oferta a pessoa já recebeu hoje
create or replace function public.ofertas_hoje(p_user uuid)
returns int language sql stable set search_path = public as $$
  select count(*)::int from notificacoes
   where user_id = p_user and tipo in ('oferta_loja', 'oferta_guardado')
     and criado >= date_trunc('day', now() at time zone 'Africa/Maputo') at time zone 'Africa/Maputo';
$$;

-- A) publicação guardada posta em oferta → avisa quem a guardou (máx. 2 toques por dia)
create or replace function public.notif_oferta_guardado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.oferta_ate is null or new.oferta_ate <= now() then return null; end if;
  if old.oferta_ate is not null and old.oferta_ate > now() then return null; end if;   -- já estava em oferta
  perform criar_notificacao(g.user_id, new.user_id, 'oferta_guardado', new.id, null, null, texto_oferta(new))
     from guardados g join perfis p on p.id = g.user_id
    where g.post_id = new.id and p.avisos_lojas <> 'nenhum' and ofertas_hoje(g.user_id) < 2;
  return null;
exception when others then
  return null;
end $$;
drop trigger if exists trg_oferta_guardado on public.posts;
create trigger trg_oferta_guardado after update of oferta_ate on public.posts
  for each row execute function public.notif_oferta_guardado();

-- B) publicação nova de uma loja
create or replace function public.notif_publicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  oferta boolean := new.oferta_ate is not null and new.oferta_ate > now();
  hoje timestamptz := date_trunc('day', now() at time zone 'Africa/Maputo') at time zone 'Africa/Maputo';
  limite int;
  pequeno boolean;
  prov text;
  ja uuid[] := '{}';       -- já tinham um toque desta loja hoje (só se atualiza)
  toca uuid[] := '{}';     -- recebem toque no telemóvel (oferta)
  linha uuid[] := '{}';    -- entram na linha "lojas que publicaram hoje"
  feitos uuid[] := '{}';
begin
  select coalesce(nullif(valor, '')::int, 2000) into limite from config where chave = 'notificar_todos_ate';
  pequeno := (select count(*) from perfis) <= coalesce(limite, 2000);
  select nullif(trim(province), '') into prov from perfis where id = new.user_id;

  if oferta then
    with u as (
      update notificacoes set post_id = new.id, texto = texto_oferta(new), criado = now(), lida = false
       where tipo = 'oferta_loja' and autor_id = new.user_id and criado >= hoje
      returning user_id)
    select coalesce(array_agg(user_id), '{}') into ja from u;
  end if;

  with alvo as (
    select p.id uid, p.avisos_lojas pref,
           exists (select 1 from followers f where f.follower_id = p.id and f.following_id = new.user_id) segue,
           (oferta and exists (select 1 from guardados g join posts x on x.id = g.post_id
                                where g.user_id = p.id and x.user_id = new.user_id)) guardou,
           (oferta and prov is not null and p.province = prov) perto
      from perfis p
     where p.id <> new.user_id
       and p.avisos_lojas <> 'nenhum' and p.role <> 'equipa'
       and coalesce(p.bloqueado, false) = false
       and not exists (select 1 from bloqueios b where b.blocker_id = p.id and b.blocked_id = new.user_id)
       and not (p.id = any (ja))
  ), c as (
    select uid,
           (oferta and (pequeno or segue or guardou) and ofertas_hoje(uid) < 2) t,
           ((pequeno or segue or guardou or perto) and (pref = 'todos' or oferta)) l
      from alvo
  )
  select coalesce(array_agg(uid) filter (where t), '{}'),
         coalesce(array_agg(uid) filter (where l and not t), '{}')
    into toca, linha from c;

  -- toque no telemóvel: "Sapataria Boa fez uma oferta para si ⚡"
  insert into notificacoes (user_id, autor_id, tipo, post_id, texto)
  select u, new.user_id, 'oferta_loja', new.id, texto_oferta(new) from unnest(toca) u;

  -- linha do dia (sem toque): atualiza a que já existe ou cria uma nova
  with u as (
    update notificacoes n
       set autor_id = new.user_id, post_id = new.id, criado = now(), lida = false,
           lojas = case when new.user_id = any (coalesce(n.lojas, '{}')) then n.lojas
                        else coalesce(n.lojas, '{}') || new.user_id end
     where n.tipo = 'lojas_hoje' and n.user_id = any (linha) and n.criado >= hoje
    returning n.user_id)
  select coalesce(array_agg(user_id), '{}') into feitos from u;

  insert into notificacoes (user_id, autor_id, tipo, post_id, lojas)
  select u, new.user_id, 'lojas_hoje', new.id, array[new.user_id]
    from unnest(linha) u where not (u = any (feitos));

  return null;
exception when others then
  return null;
end $$;

-- C) avisos de lojas apagam-se ao fim de 3 dias; os pessoais ao fim de 60
create or replace function public.limpar_notificacoes()
returns void language sql security definer set search_path = public as $$
  delete from notificacoes
   where criado < now() - interval '3 days'
     and tipo in ('lojas_hoje', 'publicacao', 'oferta_loja', 'oferta_guardado', 'resumo_semanal');
  delete from notificacoes where criado < now() - interval '60 days';
$$;

-- D) Resumo da semana (domingo) — contas feitas uma só vez (rápido mesmo com muitas pessoas)
create or replace function public.resumo_semanal()
returns int language plpgsql security definer set search_path = public as $$
declare
  equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
  semana text := to_char(now() at time zone 'Africa/Maputo', 'IYYY-IW');
  r record; t text; en boolean; partes text[]; n int := 0;
begin
  for r in
    with novas as (
      select x.user_id, x.oferta_ate is not null oferta, nullif(trim(a.province), '') province
        from posts x join perfis a on a.id = x.user_id
       where x.created_at > now() - interval '7 days' and coalesce(a.bloqueado, false) = false
    ), tot as (
      select count(*) pubs, count(*) filter (where oferta) ofertas from novas
    ), por_prov as (
      select province, count(*) n from novas where province is not null group by province
    ), minhas as (
      select user_id, count(*) pubs, count(*) filter (where oferta) ofertas from novas group by user_id
    )
    select p.id, p.idioma,
           tot.pubs - coalesce(m.pubs, 0) pubs,
           tot.ofertas - coalesce(m.ofertas, 0) ofertas,
           coalesce(pp.n, 0) - case when pp.n is not null then coalesce(m.pubs, 0) else 0 end perto
      from perfis p
      cross join tot
      left join minhas m on m.user_id = p.id
      left join por_prov pp on pp.province = nullif(trim(p.province), '')
     where coalesce(p.bloqueado, false) = false and p.role <> 'equipa'
  loop
    if r.pubs <= 0 then continue; end if;
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
revoke all on function public.ofertas_hoje(uuid) from public, anon, authenticated;

-- domingo às 17:03 em Maputo (15:03 UTC)
do $$ begin
  perform cron.unschedule('resumo-semanal') where exists (select 1 from cron.job where jobname = 'resumo-semanal');
  perform cron.schedule('resumo-semanal', '3 15 * * 0', 'select public.resumo_semanal()');
end $$;
