-- ============================================================
-- Feira Comercial — 045: Aguentar muita gente ao mesmo tempo
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Resultado do teste de carga (50 000 pessoas simuladas):
-- • Publicar numa loja com 22 000 seguidores demorava 2–3,5 s (e podia falhar
--   pelo limite de 8 s). Agora publicar é imediato: os avisos saem por uma fila,
--   processada a cada minuto.
-- • Um só pedido por minuto ("estado_agora") dá o número de mensagens por ler,
--   notificações, lives a decorrer, ofertas perto e se há publicações novas.
--   Substitui 3 pedidos separados e as ligações em tempo real em todas as páginas.
-- • Lista de conversas completa (antes, lojas com muitas mensagens perdiam
--   conversas antigas da lista).
-- • "Ofertas perto de si" passa a vir de uma contagem guardada (a cada 5 min).
-- ============================================================

-- 1) Fila de avisos: publicar fica imediato
create table if not exists public.fila_avisos (
  post_id bigint primary key references public.posts(id) on delete cascade,
  criado timestamptz not null default now()
);
alter table public.fila_avisos enable row level security;
revoke all on public.fila_avisos from anon, authenticated;

create or replace function public.espalhar_publicacao(p_post bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  np posts;
  oferta boolean;
  hoje timestamptz := date_trunc('day', now() at time zone 'Africa/Maputo') at time zone 'Africa/Maputo';
  limite int;
  pequeno boolean;
  prov text;
  ja uuid[] := '{}';       -- já tinham um toque desta loja hoje (só se atualiza)
  toca uuid[] := '{}';     -- recebem toque no telemóvel (oferta)
  linha uuid[] := '{}';    -- entram na linha "lojas que publicaram hoje"
  feitos uuid[] := '{}';
begin
  select * into np from posts where id = p_post;
  if not found then return; end if;
  oferta := np.oferta_ate is not null and np.oferta_ate > now();
  select coalesce(nullif(valor, '')::int, 2000) into limite from config where chave = 'notificar_todos_ate';
  pequeno := (select greatest(reltuples, 0) from pg_class where oid = 'public.perfis'::regclass) <= coalesce(limite, 2000);   -- estimativa rápida
  select nullif(trim(province), '') into prov from perfis where id = np.user_id;

  if oferta then
    with u as (
      update notificacoes set post_id = np.id, texto = texto_oferta(np), criado = now(), lida = false
       where tipo = 'oferta_loja' and autor_id = np.user_id and criado >= hoje
      returning user_id)
    select coalesce(array_agg(user_id), '{}') into ja from u;
  end if;

  with alvo as (
    select p.id uid, p.avisos_lojas pref,
           exists (select 1 from followers f where f.follower_id = p.id and f.following_id = np.user_id) segue,
           (oferta and exists (select 1 from guardados g join posts x on x.id = g.post_id
                                where g.user_id = p.id and x.user_id = np.user_id)) guardou,
           (oferta and prov is not null and p.province = prov) perto
      from perfis p
     where p.id <> np.user_id
       and p.avisos_lojas <> 'nenhum' and p.role <> 'equipa'
       and coalesce(p.bloqueado, false) = false
       and not exists (select 1 from bloqueios b where b.blocker_id = p.id and b.blocked_id = np.user_id)
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
  select u, np.user_id, 'oferta_loja', np.id, texto_oferta(np) from unnest(toca) u;

  -- linha do dia (sem toque): atualiza a que já existe ou cria uma nova
  with u as (
    update notificacoes n
       set autor_id = np.user_id, post_id = np.id, criado = now(), lida = false,
           lojas = case when np.user_id = any (coalesce(n.lojas, '{}')) then n.lojas
                        else coalesce(n.lojas, '{}') || np.user_id end
     where n.tipo = 'lojas_hoje' and n.user_id = any (linha) and n.criado >= hoje
    returning n.user_id)
  select coalesce(array_agg(user_id), '{}') into feitos from u;

  insert into notificacoes (user_id, autor_id, tipo, post_id, lojas)
  select u, np.user_id, 'lojas_hoje', np.id, array[np.user_id]
    from unnest(linha) u where not (u = any (feitos));

end $$;

create or replace function public.notif_publicacao()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into fila_avisos (post_id) values (new.id) on conflict do nothing;
  return null;
exception when others then
  return null;
end $$;

create or replace function public.processar_fila_avisos()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select post_id from fila_avisos order by criado limit 300 for update skip locked loop
    begin
      perform espalhar_publicacao(r.post_id);
    exception when others then
      null;   -- um aviso que falha não para os outros
    end;
    delete from fila_avisos where post_id = r.post_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.espalhar_publicacao(bigint) from public, anon, authenticated;
revoke all on function public.processar_fila_avisos() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('fila-avisos') where exists (select 1 from cron.job where jobname = 'fila-avisos');
  perform cron.schedule('fila-avisos', '* * * * *', 'select public.processar_fila_avisos()');
end $$;

-- 2) Mensagens por ler: contagem rápida
create index if not exists messages_por_ler_idx on public.messages (receiver_id)
  where read_at is null and not deleted and not cleared_by_receiver;

-- 3) Ofertas perto: contagem por província, guardada a cada 5 minutos
create table if not exists public.cache_ofertas (
  province text primary key,
  n int not null,
  atualizado timestamptz not null default now()
);
alter table public.cache_ofertas enable row level security;
drop policy if exists cache_ofertas_ler on public.cache_ofertas;
create policy cache_ofertas_ler on public.cache_ofertas for select to authenticated using (true);
revoke all on public.cache_ofertas from anon;
grant select on public.cache_ofertas to authenticated;

create or replace function public.atualizar_cache_ofertas()
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from cache_ofertas;
  insert into cache_ofertas (province, n)
  select a.province, count(*)::int
    from posts p join perfis a on a.id = p.user_id
   where p.oferta_ate > now() and nullif(trim(a.province), '') is not null and coalesce(a.bloqueado, false) = false
   group by a.province;
end $$;
revoke all on function public.atualizar_cache_ofertas() from public, anon, authenticated;
select public.atualizar_cache_ofertas();
do $$ begin
  perform cron.unschedule('cache-ofertas') where exists (select 1 from cron.job where jobname = 'cache-ofertas');
  perform cron.schedule('cache-ofertas', '*/5 * * * *', 'select public.atualizar_cache_ofertas()');
end $$;

-- 4) Um só pedido por minuto com tudo o que o ecrã precisa
create or replace function public.estado_agora()
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'mensagens', (select count(*) from messages
                   where receiver_id = auth.uid() and read_at is null and not deleted and not cleared_by_receiver),
    'notificacoes', (select count(*) from notificacoes where user_id = auth.uid() and not lida),
    'lives', coalesce((select jsonb_agg(x) from (
               select l.id, l.user_id, l.titulo, jsonb_build_object('full_name', a.full_name, 'avatar_url', a.avatar_url) autor
                 from lives l join perfis a on a.id = l.user_id
                where l.estado = 'ao_vivo' and l.atualizado_em > now() - interval '150 seconds' and l.user_id <> auth.uid()
                order by l.started_at desc limit 6) x), '[]'::jsonb),
    'ultimo_post', (select max(id) from posts),
    'ofertas_perto', coalesce((select c.n from cache_ofertas c
                                where c.province = (select province from perfis where id = auth.uid())), 0)
  );
$$;
revoke all on function public.estado_agora() from public, anon;
grant execute on function public.estado_agora() to authenticated;

-- 5) Lista de conversas: a última mensagem de cada pessoa + quantas por ler
create or replace function public.minhas_conversas(p_limite int default 150)
returns table (outro uuid, ultima jsonb, por_ler int)
language sql stable security invoker set search_path = public as $$
  with m as (
    select x.receiver_id o, x.* from messages x where x.sender_id = auth.uid() and not x.cleared_by_sender
    union all
    select x.sender_id o, x.* from messages x where x.receiver_id = auth.uid() and not x.cleared_by_receiver
  ), ult as (
    select distinct on (o) * from m order by o, created_at desc
  ), pl as (
    select x.sender_id o, count(*)::int n from messages x
     where x.receiver_id = auth.uid() and x.read_at is null and not x.deleted and not x.cleared_by_receiver
     group by 1
  )
  select u.o, to_jsonb(u) - 'o', coalesce(pl.n, 0)
    from ult u left join pl on pl.o = u.o
   order by u.created_at desc
   limit greatest(1, least(coalesce(p_limite, 150), 500));
$$;
revoke all on function public.minhas_conversas(int) from public, anon;
grant execute on function public.minhas_conversas(int) to authenticated;
