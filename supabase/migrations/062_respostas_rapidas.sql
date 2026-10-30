-- ============================================================
-- Feira Comercial — 062: Respostas rápidas no chat
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Cada conta guarda frases prontas para o chat (preço, entrega, horário…)
-- e usa-as com um toque (botão ⚡ ou "/" na caixa de mensagem).
--  • Cada pessoa só vê, cria, muda e apaga as SUAS respostas.
--  • No máximo 30 respostas por conta, cada uma até 1000 caracteres.
--  • Antes desta migração, o chat guarda as respostas só no aparelho.
-- ============================================================

create table if not exists public.respostas_rapidas (
  id bigint generated always as identity primary key,
  dono uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  texto text not null check (char_length(btrim(texto)) between 1 and 1000),
  ordem int not null default 0,
  criado timestamptz not null default now()
);
create index if not exists respostas_rapidas_dono_idx on public.respostas_rapidas (dono, ordem, id);

alter table public.respostas_rapidas enable row level security;
revoke all on public.respostas_rapidas from anon, authenticated;
grant select, insert, delete on public.respostas_rapidas to authenticated;
grant update (texto, ordem) on public.respostas_rapidas to authenticated;   -- o dono nunca muda

drop policy if exists respostas_rapidas_dono on public.respostas_rapidas;
create policy respostas_rapidas_dono on public.respostas_rapidas
  for all to authenticated
  using (dono = (select auth.uid()))
  with check (dono = (select auth.uid()));

-- no máximo 30 por conta
create or replace function public.respostas_rapidas_limite()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtext('respostas_rapidas:' || new.dono::text));
  if (select count(*) from public.respostas_rapidas where dono = new.dono) >= 30 then
    raise exception 'Pode guardar no máximo 30 respostas rápidas.';
  end if;
  return new;
end $$;
revoke all on function public.respostas_rapidas_limite() from public, anon, authenticated;

drop trigger if exists respostas_rapidas_limite on public.respostas_rapidas;
create trigger respostas_rapidas_limite before insert on public.respostas_rapidas
  for each row execute function public.respostas_rapidas_limite();

-- ver se ficou bem: deve mostrar 1 linha "respostas_rapidas | t"
select c.relname as tabela, c.relrowsecurity as protegida
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'respostas_rapidas';
