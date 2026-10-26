-- ============================================================
-- 059 — "Pegar" um caso: evita que dois membros da equipa
-- respondam à mesma pessoa ou à mesma reclamação ao mesmo tempo.
--
--   • Caixa da Equipa: quem abre a conversa fica com ela enquanto
--     a tiver aberta (a app renova a cada 15 s; larga após 2 min sem sinal).
--   • Reclamações: quem começa a escrever fica com ela 15 minutos
--     ou até guardar.
--   • Os outros veem "🔒 <nome> está a tratar" e podem tomar o caso
--     se for preciso (fica registado quem respondeu, como antes).
-- ============================================================

create table if not exists public.equipa_casos (
  tipo   text        not null check (tipo in ('caixa', 'reclamacao')),
  alvo   text        not null,
  por    uuid        not null references public.perfis (id) on delete cascade,
  desde  timestamptz not null default now(),
  primary key (tipo, alvo)
);
create index if not exists equipa_casos_por_idx on public.equipa_casos (por);
alter table public.equipa_casos enable row level security;
-- sem políticas: só se mexe através das funções abaixo

create or replace function public.equipa_caso_validade(p_tipo text)
returns interval language sql immutable set search_path to '' as $$
  select case when p_tipo = 'caixa' then interval '2 minutes' else interval '15 minutes' end;
$$;

-- Pegar (ou renovar) um caso. Devolve o primeiro nome de quem já o tem,
-- ou null se ficou meu.
create or replace function public.equipa_pegar(p_tipo text, p_alvo text, p_forcar boolean default false)
returns text language plpgsql security definer set search_path to 'public' as $$
declare outro uuid; nome text;
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  if p_tipo not in ('caixa', 'reclamacao') or nullif(btrim(p_alvo), '') is null then raise exception 'caso inválido'; end if;
  select c.por into outro from equipa_casos c
   where c.tipo = p_tipo and c.alvo = p_alvo and c.por <> auth.uid()
     and c.desde > now() - equipa_caso_validade(p_tipo)
   for update;
  if found and not coalesce(p_forcar, false) then
    select split_part(btrim(full_name), ' ', 1) into nome from perfis where id = outro;
    return coalesce(nullif(nome, ''), 'Outro membro');
  end if;
  insert into equipa_casos (tipo, alvo, por, desde) values (p_tipo, p_alvo, auth.uid(), now())
    on conflict (tipo, alvo) do update set por = excluded.por, desde = excluded.desde;
  return null;
end $$;

-- Largar um caso meu.
create or replace function public.equipa_largar(p_tipo text, p_alvo text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  delete from equipa_casos where tipo = p_tipo and alvo = p_alvo and por = auth.uid();
end $$;

-- Casos que estão a ser tratados agora (para mostrar 🔒 nas listas).
create or replace function public.equipa_casos_ativos()
returns table (tipo text, alvo text, nome text, meu boolean)
language plpgsql stable security definer set search_path to 'public' as $$
#variable_conflict use_column
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  return query
  select c.tipo, c.alvo, split_part(btrim(p.full_name), ' ', 1), c.por = auth.uid()
    from equipa_casos c join perfis p on p.id = c.por
   where c.desde > now() - equipa_caso_validade(c.tipo);
end $$;

-- limpeza: casos antigos não servem para nada
delete from public.equipa_casos where desde < now() - interval '1 day';

revoke execute on function public.equipa_pegar(text, text, boolean) from public, anon;
revoke execute on function public.equipa_largar(text, text)          from public, anon;
revoke execute on function public.equipa_casos_ativos()              from public, anon;
revoke execute on function public.equipa_caso_validade(text)         from public, anon;
grant  execute on function public.equipa_pegar(text, text, boolean) to authenticated;
grant  execute on function public.equipa_largar(text, text)          to authenticated;
grant  execute on function public.equipa_casos_ativos()              to authenticated;
grant  execute on function public.equipa_caso_validade(text)         to authenticated;
