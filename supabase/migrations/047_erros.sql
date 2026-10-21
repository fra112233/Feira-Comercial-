-- ============================================================
-- Feira Comercial — 047: Aviso automático de erros
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Quando algo falha no telemóvel de alguém, fica registado (página, erro,
-- aparelho). Só o administrador vê, em Administração → Números → Erros.
-- • O mesmo erro no mesmo dia não repete linha: só aumenta o contador.
-- • Máximo de 1 000 erros diferentes por dia (protege contra abusos).
-- • Apagam-se sozinhos ao fim de 30 dias.
-- • Não guarda mensagens, contactos nem nada escrito pelas pessoas.
-- ============================================================

create table if not exists public.erros_cliente (
  id bigint generated always as identity primary key,
  dia date not null default (now() at time zone 'Africa/Maputo')::date,
  chave text not null,                 -- identifica o mesmo erro (mensagem + página + sítio)
  pagina text, mensagem text, fonte text, linha int, pilha text,
  aparelho text, versao text,
  vezes int not null default 1,
  pessoas uuid[] not null default '{}',
  primeiro timestamptz not null default now(),
  ultimo timestamptz not null default now(),
  unique (dia, chave)
);
alter table public.erros_cliente enable row level security;
revoke all on public.erros_cliente from anon, authenticated;
create index if not exists erros_cliente_ultimo_idx on public.erros_cliente (ultimo desc);

create or replace function public.registar_erro(p_pagina text, p_mensagem text, p_fonte text default null, p_linha int default null,
                                               p_pilha text default null, p_aparelho text default null, p_versao text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  hoje date := (now() at time zone 'Africa/Maputo')::date;
  m text := left(btrim(coalesce(p_mensagem, '')), 300);
  pg text := left(regexp_replace(coalesce(p_pagina, ''), '[?#].*$', ''), 80);   -- sem parâmetros (podem ter dados)
  f text := left(regexp_replace(coalesce(p_fonte, ''), '[?#].*$', ''), 160);
  k text;
  eu uuid := auth.uid();
begin
  if m = '' then return; end if;
  k := md5(m || '|' || pg || '|' || f || '|' || coalesce(p_linha, 0));
  update erros_cliente
     set vezes = vezes + 1, ultimo = now(),
         pessoas = case when eu is null or eu = any (pessoas) or cardinality(pessoas) >= 50 then pessoas else pessoas || eu end
   where dia = hoje and chave = k;
  if found then return; end if;
  if (select count(*) from erros_cliente where dia = hoje) >= 1000 then return; end if;
  insert into erros_cliente (dia, chave, pagina, mensagem, fonte, linha, pilha, aparelho, versao, pessoas)
  values (hoje, k, pg, m, f, p_linha, left(p_pilha, 1500), left(p_aparelho, 200), left(p_versao, 40),
          case when eu is null then '{}' else array[eu] end)
  on conflict (dia, chave) do update set vezes = erros_cliente.vezes + 1, ultimo = now();
end $$;
revoke all on function public.registar_erro(text, text, text, int, text, text, text) from public;
grant execute on function public.registar_erro(text, text, text, int, text, text, text) to anon, authenticated;

-- lista para o administrador: o mesmo erro junta os vários dias
create or replace function public.admin_erros(p_dias int default 7)
returns table (chave text, pagina text, mensagem text, fonte text, linha int, pilha text, aparelho text, versao text,
               vezes bigint, pessoas int, dias int, primeiro timestamptz, ultimo timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  select e.chave, max(e.pagina), max(e.mensagem), max(e.fonte), max(e.linha),
         (array_agg(e.pilha order by e.ultimo desc))[1], (array_agg(e.aparelho order by e.ultimo desc))[1],
         (array_agg(e.versao order by e.ultimo desc))[1],
         sum(e.vezes), (select count(distinct u)::int from erros_cliente x, unnest(x.pessoas) u where x.chave = e.chave),
         count(*)::int, min(e.primeiro), max(e.ultimo)
    from erros_cliente e
   where e.ultimo > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 30)))
   group by e.chave
   order by max(e.ultimo) desc
   limit 200;
end $$;
revoke all on function public.admin_erros(int) from public, anon;
grant execute on function public.admin_erros(int) to authenticated;

-- "Já resolvi": apaga esse erro (se voltar a acontecer, aparece de novo)
create or replace function public.admin_erro_resolvido(p_chave text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  delete from erros_cliente where chave = p_chave;
end $$;
revoke all on function public.admin_erro_resolvido(text) from public, anon;
grant execute on function public.admin_erro_resolvido(text) to authenticated;

-- limpeza: 30 dias
do $$ begin
  perform cron.unschedule('limpar-erros') where exists (select 1 from cron.job where jobname = 'limpar-erros');
  perform cron.schedule('limpar-erros', '17 3 * * *', $c$delete from public.erros_cliente where ultimo < now() - interval '30 days'$c$);
end $$;
