-- ============================================================
-- Feira Comercial — 007: Livro de Reclamações e Sugestões
-- Correr UMA vez no Supabase: SQL Editor → New query → colar → Run
-- (já aplicado pelo Claude através do MCP)
-- ============================================================

create table if not exists public.reclamacoes (
  id          bigint generated always as identity primary key,
  user_id     uuid default auth.uid() references public.perfis(id) on delete set null,
  nome        text not null check (char_length(btrim(nome)) between 2 and 120),
  email       text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 200),
  telefone    text check (telefone is null or char_length(telefone) <= 30),
  tipo        text not null default 'sugestao'
              check (tipo in ('sugestao', 'reclamacao', 'problema', 'denuncia', 'elogio')),
  assunto     text not null check (char_length(btrim(assunto)) between 3 and 150),
  mensagem    text not null check (char_length(btrim(mensagem)) between 10 and 4000),
  link        text check (link is null or char_length(link) <= 500),   -- página/publicação em causa
  estado      text not null default 'recebida'
              check (estado in ('recebida', 'em_analise', 'resolvida', 'arquivada')),
  resposta    text,                                                 -- resposta da equipa
  respondido_em timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists reclamacoes_user_idx on public.reclamacoes (user_id, created_at desc);
create index if not exists reclamacoes_email_idx on public.reclamacoes (lower(email), created_at desc);

alter table public.reclamacoes enable row level security;

-- Qualquer pessoa (com ou sem conta) pode enviar.
-- Se tiver sessão, o pedido fica ligado à conta; ninguém pode pôr o id de outra pessoa.
drop policy if exists "reclamacoes_inserir" on public.reclamacoes;
create policy "reclamacoes_inserir" on public.reclamacoes
  for insert to anon, authenticated
  with check (
    (user_id is null or user_id = (select auth.uid()))
    and estado = 'recebida' and resposta is null and respondido_em is null
  );

-- Cada utilizador só vê os seus próprios pedidos (e a resposta da equipa).
drop policy if exists "reclamacoes_ver_proprias" on public.reclamacoes;
create policy "reclamacoes_ver_proprias" on public.reclamacoes
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Sem políticas de update/delete: só a equipa (no painel do Supabase) muda o estado e responde.

-- Anti-spam: no máximo 5 pedidos por hora do mesmo e-mail ou da mesma conta.
create or replace function public.limitar_reclamacoes()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.reclamacoes
      where created_at > now() - interval '1 hour'
        and (lower(email) = lower(new.email) or (new.user_id is not null and user_id = new.user_id))) >= 5 then
    raise exception 'Demasiados pedidos seguidos. Tente novamente daqui a uma hora.' using errcode = 'P0001';
  end if;
  new.email := lower(btrim(new.email));
  new.nome := btrim(new.nome);
  return new;
end $$;
revoke execute on function public.limitar_reclamacoes() from public, anon, authenticated;

drop trigger if exists limitar_reclamacoes on public.reclamacoes;
create trigger limitar_reclamacoes before insert on public.reclamacoes
  for each row execute function public.limitar_reclamacoes();

-- Quando a equipa escreve uma resposta no painel, regista a data automaticamente.
create or replace function public.marcar_resposta()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.resposta is distinct from old.resposta and new.resposta is not null then
    new.respondido_em := now();
  end if;
  return new;
end $$;
revoke execute on function public.marcar_resposta() from public, anon, authenticated;

drop trigger if exists marcar_resposta on public.reclamacoes;
create trigger marcar_resposta before update on public.reclamacoes
  for each row execute function public.marcar_resposta();

grant insert on public.reclamacoes to anon, authenticated;
grant select on public.reclamacoes to authenticated;
