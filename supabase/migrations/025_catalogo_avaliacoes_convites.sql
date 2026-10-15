-- ============================================================
-- Feira Comercial — 025: Catálogo de produtos, Avaliações e Convide e ganhe
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Precisa da 022 (notificações). Pode ser corrido mais de uma vez sem problema.
--
-- 1) Produtos: cada empresa (com mensalidade em dia) mostra produtos com preço
--    e botão "Encomendar pelo WhatsApp". Até 100 produtos por empresa.
-- 2) Avaliações: cada pessoa dá 1 a 5 estrelas a uma empresa (uma avaliação por
--    pessoa, pode mudar). A empresa pode responder. Não se pode avaliar a si própria.
-- 3) Convide e ganhe: quem cria conta pelo link de convite fica ligado a quem
--    convidou. Quando a empresa convidada paga a 1.ª mensalidade, a empresa que
--    convidou ganha dias grátis (configuração 'dias_convite', por omissão 30).
-- ============================================================

-- ---------- avisos novos no sino ----------
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo in (
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio'));

-- ============================================================
-- 1) PRODUTOS
-- ============================================================
create table if not exists public.produtos (
  id          bigserial primary key,
  user_id     uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  nome        text not null check (char_length(btrim(nome)) between 1 and 80),
  descricao   text check (descricao is null or char_length(descricao) <= 500),
  preco       numeric(12,2) check (preco is null or preco >= 0),
  foto_url    text check (foto_url is null or foto_url ~ '^https://'),
  disponivel  boolean not null default true,
  ordem       int not null default 0,
  criado      timestamptz not null default now()
);
create index if not exists produtos_empresa_idx on public.produtos (user_id, ordem, criado desc);
alter table public.produtos enable row level security;
revoke all on public.produtos from anon, authenticated;
grant select, insert, update, delete on public.produtos to authenticated;
grant usage on sequence public.produtos_id_seq to authenticated;

drop policy if exists produtos_ver on public.produtos;
create policy produtos_ver on public.produtos for select to authenticated
  using (disponivel or user_id = (select auth.uid()));
drop policy if exists produtos_criar on public.produtos;
create policy produtos_criar on public.produtos for insert to authenticated
  with check (user_id = (select auth.uid()) and (select empresa_ativa()));
drop policy if exists produtos_mudar on public.produtos;
create policy produtos_mudar on public.produtos for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and (select sou_empresa()));
drop policy if exists produtos_apagar on public.produtos;
create policy produtos_apagar on public.produtos for delete to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.limitar_produtos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from produtos where user_id = new.user_id) >= 100 then
    raise exception 'Chegou ao limite de 100 produtos. Apague alguns antes de juntar mais.' using errcode = 'P0001';
  end if;
  new.nome := btrim(new.nome);
  return new;
end $$;
revoke all on function public.limitar_produtos() from public, anon, authenticated;
drop trigger if exists trg_limitar_produtos on public.produtos;
create trigger trg_limitar_produtos before insert on public.produtos for each row execute function public.limitar_produtos();
drop trigger if exists trg_suspenso on public.produtos;
create trigger trg_suspenso before insert on public.produtos for each row execute function public.impedir_se_suspenso();

-- ============================================================
-- 2) AVALIAÇÕES
-- ============================================================
create table if not exists public.avaliacoes (
  empresa_id  uuid not null references public.perfis(id) on delete cascade,
  user_id     uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  estrelas    smallint not null check (estrelas between 1 and 5),
  comentario  text check (comentario is null or char_length(comentario) <= 500),
  resposta    text check (resposta is null or char_length(resposta) <= 500),
  criado      timestamptz not null default now(),
  atualizado  timestamptz not null default now(),
  primary key (empresa_id, user_id)
);
create index if not exists avaliacoes_user_idx on public.avaliacoes (user_id);
create index if not exists avaliacoes_empresa_idx on public.avaliacoes (empresa_id, atualizado desc);
alter table public.avaliacoes enable row level security;
revoke all on public.avaliacoes from anon, authenticated;
grant select, insert, update, delete on public.avaliacoes to authenticated;

drop policy if exists avaliacoes_ver on public.avaliacoes;
create policy avaliacoes_ver on public.avaliacoes for select to authenticated using (true);
drop policy if exists avaliacoes_criar on public.avaliacoes;
create policy avaliacoes_criar on public.avaliacoes for insert to authenticated
  with check (user_id = (select auth.uid()) and empresa_id <> (select auth.uid())
              and exists (select 1 from perfis e where e.id = empresa_id and e.type = 'empresa'));
drop policy if exists avaliacoes_mudar on public.avaliacoes;
create policy avaliacoes_mudar on public.avaliacoes for update to authenticated
  using (user_id = (select auth.uid()) or empresa_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) or empresa_id = (select auth.uid()));
drop policy if exists avaliacoes_apagar on public.avaliacoes;
create policy avaliacoes_apagar on public.avaliacoes for delete to authenticated
  using (user_id = (select auth.uid()));

-- quem avaliou só muda estrelas/comentário; a empresa só muda a resposta
create or replace function public.proteger_avaliacao() returns trigger
language plpgsql set search_path = public as $$
begin
  new.empresa_id := old.empresa_id; new.user_id := old.user_id; new.criado := old.criado;
  if coalesce(auth.role(), '') = 'service_role' or current_user in ('postgres', 'supabase_admin') then return new; end if;
  if auth.uid() = old.empresa_id then
    new.estrelas := old.estrelas; new.comentario := old.comentario; new.atualizado := old.atualizado;
    new.resposta := nullif(btrim(new.resposta), '');
  else
    new.resposta := old.resposta;
    new.atualizado := now();
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_avaliacao on public.avaliacoes;
create trigger trg_proteger_avaliacao before update on public.avaliacoes for each row execute function public.proteger_avaliacao();
drop trigger if exists trg_suspenso on public.avaliacoes;
create trigger trg_suspenso before insert on public.avaliacoes for each row execute function public.impedir_se_suspenso();

create or replace function public.notif_avaliacao() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.estrelas is distinct from old.estrelas or new.comentario is distinct from old.comentario then
    perform criar_notificacao(new.empresa_id, new.user_id, 'avaliacao', null, null, null,
      repeat('★', new.estrelas) || repeat('☆', 5 - new.estrelas) || coalesce(' · ' || nullif(btrim(new.comentario), ''), ''));
  end if;
  if tg_op = 'UPDATE' and new.resposta is not null and new.resposta is distinct from old.resposta then
    perform criar_notificacao(new.user_id, new.empresa_id, 'resposta_avaliacao', null, null, null, new.resposta);
  end if;
  return null;
end $$;
revoke all on function public.notif_avaliacao() from public, anon, authenticated;
drop trigger if exists trg_notif_avaliacao on public.avaliacoes;
create trigger trg_notif_avaliacao after insert or update on public.avaliacoes for each row execute function public.notif_avaliacao();

-- resumo (média e número) de várias empresas de uma vez — para cartões e perfis
create or replace function public.resumo_avaliacoes(ids uuid[])
returns table (empresa_id uuid, media numeric, total bigint)
language sql stable security definer set search_path = public as $$
  select a.empresa_id, round(avg(a.estrelas)::numeric, 1), count(*)
    from avaliacoes a where a.empresa_id = any(ids[1:200]) group by a.empresa_id;
$$;
revoke all on function public.resumo_avaliacoes(uuid[]) from public, anon;
grant execute on function public.resumo_avaliacoes(uuid[]) to authenticated;

-- ============================================================
-- 3) CONVIDE E GANHE
-- ============================================================
alter table public.perfis add column if not exists convidado_por uuid references public.perfis(id) on delete set null;
create index if not exists perfis_convidado_por_idx on public.perfis (convidado_por);
insert into public.config (chave, valor) values ('dias_convite', '30') on conflict (chave) do nothing;

-- ninguém muda quem o convidou depois de criar a conta
create or replace function public.proteger_convite() returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    new.convidado_por := old.convidado_por;
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_convite on public.perfis;
create trigger trg_proteger_convite before update on public.perfis for each row execute function public.proteger_convite();

create table if not exists public.convites_premios (
  convidado      uuid primary key references public.perfis(id) on delete cascade,
  quem_convidou  uuid not null references public.perfis(id) on delete cascade,
  dias           int not null,
  criado         timestamptz not null default now()
);
create index if not exists convites_premios_quem_idx on public.convites_premios (quem_convidou);
alter table public.convites_premios enable row level security;
revoke all on public.convites_premios from anon, authenticated;

-- criação do perfil: guarda quem convidou (vem do link Formulario.html?convite=<id>)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  tipo text := case when m->>'type' = 'empresa' then 'empresa' else 'singular' end;
  quem uuid := null;
begin
  if coalesce(m->>'convidado_por', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select id into quem from public.perfis where id = (m->>'convidado_por')::uuid and id <> new.id;
  end if;
  insert into public.perfis (
    id, username, full_name, email, type,
    phone, whatsapp, gender, morada, city, province,
    sector, nuit, bio, website, latitude, longitude, opening_hours, convidado_por
  )
  values (
    new.id,
    split_part(new.email, '@', 1) || '_' || substr(new.id::text, 1, 6),
    coalesce(nullif(m->>'full_name', ''), split_part(new.email, '@', 1)),
    new.email,
    tipo,
    nullif(m->>'phone', ''),
    nullif(m->>'whatsapp', ''),
    nullif(m->>'gender', ''),
    nullif(m->>'morada', ''),
    nullif(m->>'city', ''),
    nullif(m->>'province', ''),
    nullif(m->>'sector', ''),
    nullif(m->>'nuit', ''),
    nullif(m->>'bio', ''),
    nullif(m->>'website', ''),
    nullif(m->>'latitude', '')::double precision,
    nullif(m->>'longitude', '')::double precision,
    case when jsonb_typeof(m->'opening_hours') = 'object' then m->'opening_hours' end,
    quem
  )
  on conflict (id) do nothing;
  if quem is not null then
    perform public.criar_notificacao(quem, new.id, 'convite_aceite');
  end if;
  return new;
end;
$$;

-- pagamento confirmado: renova a mensalidade e, na 1.ª vez, dá o prémio a quem convidou
create or replace function public.confirmar_pagamento()
returns trigger language plpgsql security definer set search_path = public as $$
declare quem uuid; dias int;
begin
  if new.estado = 'confirmado' and old.estado <> 'confirmado' then
    new.confirmado_em := now();
    update public.perfis
       set assinatura_ate = greatest(coalesce(assinatura_ate, now()), now()) + make_interval(days => 30 * new.meses)
     where id = new.empresa_id;

    select p.convidado_por into quem from public.perfis p where p.id = new.empresa_id;
    if quem is not null
       and exists (select 1 from public.perfis where id = quem and type = 'empresa')
       and not exists (select 1 from public.convites_premios where convidado = new.empresa_id) then
      select coalesce(nullif(valor, '')::int, 30) into dias from public.config where chave = 'dias_convite';
      dias := coalesce(dias, 30);
      insert into public.convites_premios (convidado, quem_convidou, dias) values (new.empresa_id, quem, dias);
      update public.perfis
         set assinatura_ate = greatest(coalesce(assinatura_ate, now()), now()) + make_interval(days => dias)
       where id = quem;
      perform public.criar_notificacao(quem, new.empresa_id, 'convite_premio', null, null, null, '+' || dias || ' dias de mensalidade grátis 🎁');
    end if;
  end if;
  return new;
end $$;

-- os meus números de convites
create or replace function public.meus_convites()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'contas',   (select count(*) from perfis where convidado_por = auth.uid()),
    'empresas', (select count(*) from perfis where convidado_por = auth.uid() and type = 'empresa'),
    'premios',  (select count(*) from convites_premios where quem_convidou = auth.uid()),
    'dias',     (select coalesce(sum(dias), 0) from convites_premios where quem_convidou = auth.uid()),
    'dias_por_convite', (select coalesce(nullif(valor, '')::int, 30) from config where chave = 'dias_convite'))
  where auth.uid() is not null;
$$;
revoke all on function public.meus_convites() from public, anon;
grant execute on function public.meus_convites() to authenticated;
