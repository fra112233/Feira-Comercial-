-- ============================================================
-- Feira Comercial — 023: Estatísticas para empresas
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Conta (sem repetir a mesma pessoa): visitas ao perfil, vistas das publicações e
-- cliques em WhatsApp / Ligar / E-mail / Site. A empresa vê os números na página
-- Estatísticas. Ninguém consegue ler os eventos de outra empresa.
-- ============================================================

create table if not exists public.eventos (
  id            bigserial primary key,
  empresa_id    uuid not null references public.perfis(id) on delete cascade,
  visitante_id  uuid references public.perfis(id) on delete set null,
  tipo          text not null check (tipo in ('perfil','publicacao','whatsapp','ligar','email','site','anuncio')),
  alvo          text,
  criado        timestamptz not null default now()
);
create index if not exists eventos_empresa_idx on public.eventos (empresa_id, criado desc);
create index if not exists eventos_dedup_idx on public.eventos (empresa_id, visitante_id, tipo, alvo, criado desc);
create index if not exists eventos_visitante_idx on public.eventos (visitante_id);
alter table public.eventos enable row level security;
revoke all on public.eventos from anon, authenticated;   -- só pelas funções abaixo

-- registar um evento (o próprio dono não conta; a mesma pessoa só conta 1x por período)
create or replace function public.registar_evento(p_empresa uuid, p_tipo text, p_alvo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare janela interval;
begin
  if auth.uid() is null or p_empresa is null or p_empresa = auth.uid() then return; end if;
  if p_tipo not in ('perfil','publicacao','whatsapp','ligar','email','site','anuncio') then return; end if;
  if not exists (select 1 from perfis where id = p_empresa and type = 'empresa') then return; end if;
  janela := case when p_tipo in ('perfil','publicacao','anuncio') then interval '6 hours' else interval '10 minutes' end;
  if exists (select 1 from eventos
              where empresa_id = p_empresa and visitante_id = auth.uid() and tipo = p_tipo
                and alvo is not distinct from p_alvo and criado > now() - janela) then
    return;
  end if;
  insert into eventos (empresa_id, visitante_id, tipo, alvo) values (p_empresa, auth.uid(), p_tipo, left(p_alvo, 80));
end $$;
revoke all on function public.registar_evento(uuid, text, text) from public, anon;
grant execute on function public.registar_evento(uuid, text, text) to authenticated;

-- publicações que apareceram no ecrã (o feed envia várias de uma vez)
create or replace function public.registar_vistas(p_posts bigint[])
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if auth.uid() is null or p_posts is null then return; end if;
  for r in select p.id, p.user_id from posts p join perfis e on e.id = p.user_id and e.type = 'empresa'
            where p.id = any(p_posts[1:30]) and p.user_id <> auth.uid() loop
    perform registar_evento(r.user_id, 'publicacao', r.id::text);
  end loop;
end $$;
revoke all on function public.registar_vistas(bigint[]) from public, anon;
grant execute on function public.registar_vistas(bigint[]) to authenticated;

-- números da MINHA empresa nos últimos p_dias (com comparação ao período anterior)
create or replace function public.minhas_estatisticas(p_dias int default 7)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  eu uuid := auth.uid();
  d int := greatest(1, least(coalesce(p_dias, 7), 90));
  ini timestamptz := now() - make_interval(days => d);
  ant timestamptz := now() - make_interval(days => 2 * d);
  r jsonb;
begin
  if eu is null then return null; end if;
  select jsonb_build_object(
    'dias', d,
    'atual', (select jsonb_object_agg(tipo, n) from (select tipo, count(*) n from eventos where empresa_id = eu and criado >= ini group by tipo) x),
    'anterior', (select jsonb_object_agg(tipo, n) from (select tipo, count(*) n from eventos where empresa_id = eu and criado >= ant and criado < ini group by tipo) x),
    'visitantes', (select count(distinct visitante_id) from eventos where empresa_id = eu and criado >= ini),
    'visitantes_ant', (select count(distinct visitante_id) from eventos where empresa_id = eu and criado >= ant and criado < ini),
    'gostos', (select count(*) from likes l join posts p on p.id = l.post_id where p.user_id = eu and l.created_at >= ini and l.user_id <> eu),
    'gostos_ant', (select count(*) from likes l join posts p on p.id = l.post_id where p.user_id = eu and l.created_at >= ant and l.created_at < ini and l.user_id <> eu),
    'comentarios', (select count(*) from comments c join posts p on p.id = c.post_id where p.user_id = eu and c.created_at >= ini and c.user_id <> eu),
    'comentarios_ant', (select count(*) from comments c join posts p on p.id = c.post_id where p.user_id = eu and c.created_at >= ant and c.created_at < ini and c.user_id <> eu),
    'conversas', (select count(distinct sender_id) from messages where receiver_id = eu and created_at >= ini),
    'conversas_ant', (select count(distinct sender_id) from messages where receiver_id = eu and created_at >= ant and created_at < ini),
    'seguidores', (select count(*) from followers where following_id = eu),
    'seguidores_novos', (select count(*) from followers where following_id = eu and created_at >= extract(epoch from ini) * 1000),
    'seguidores_novos_ant', (select count(*) from followers where following_id = eu and created_at >= extract(epoch from ant) * 1000 and created_at < extract(epoch from ini) * 1000),
    'por_dia', (
      select jsonb_agg(jsonb_build_object('dia', g.dia, 'perfil', coalesce(v.perfil, 0), 'publicacao', coalesce(v.publicacao, 0), 'contactos', coalesce(v.contactos, 0)) order by g.dia)
      from generate_series((now() - make_interval(days => d - 1))::date, now()::date, interval '1 day') as g(dia)
      left join (
        select criado::date dia,
               count(*) filter (where tipo = 'perfil') perfil,
               count(*) filter (where tipo = 'publicacao') publicacao,
               count(*) filter (where tipo in ('whatsapp','ligar','email','site')) contactos
          from eventos where empresa_id = eu and criado >= ini group by 1) v on v.dia = g.dia::date),
    'top', (
      select jsonb_agg(t order by t.vistas desc, t.gostos desc) from (
        select p.id, left(coalesce(p.content, ''), 90) texto, p.created_at, p.curtidas_count gostos, p.comentarios_count comentarios,
               coalesce(p.media->0->>'url', p.image_url) foto, coalesce(p.media->0->>'type', 'image') foto_tipo,
               (select count(*) from eventos e where e.empresa_id = eu and e.tipo = 'publicacao' and e.alvo = p.id::text and e.criado >= ini) vistas
          from posts p where p.user_id = eu and p.created_at >= ant
          order by vistas desc, p.curtidas_count desc limit 5) t)
  ) into r;
  return r;
end $$;
revoke all on function public.minhas_estatisticas(int) from public, anon;
grant execute on function public.minhas_estatisticas(int) to authenticated;

-- limpeza: eventos com mais de 180 dias
create or replace function public.limpar_eventos() returns void
language sql security definer set search_path = public as $$
  delete from eventos where criado < now() - interval '180 days';
$$;
revoke all on function public.limpar_eventos() from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'limpar-eventos';
select cron.schedule('limpar-eventos', '27 3 * * *', 'select public.limpar_eventos()');
