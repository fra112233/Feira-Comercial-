-- ============================================================
-- Feira Comercial — 010: Mensalidade das empresas + Live
-- Correr no Supabase: SQL Editor → New query → colar → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Regras:
--  • Só as EMPRESAS pagam (100 MT/mês). As contas pessoais são grátis.
--  • Cada empresa tem 30 dias grátis (as que já existem contam a partir de hoje).
--  • Sem pagar, a empresa recebe um aviso a cada 48 horas a dizer que vai ficar
--    sem acesso. Por agora NÃO é bloqueada (config 'bloquear_sem_pagamento' = 'nao').
--    Se um dia mudares para 'sim', sem mensalidade ativa a empresa deixa de publicar
--    no feed, criar anúncios/campanhas e fazer Live.
--  • O pagamento é manual (M-Pesa / e-Mola): a empresa envia o código da
--    transação e a equipa confirma em Table Editor → pagamentos → estado = confirmado.
-- ============================================================

-- 1) Configuração (preço, números para receber, servidor TURN do Live)
create table if not exists public.config (
  chave text primary key,
  valor text not null default '',
  descricao text
);
alter table public.config enable row level security;
drop policy if exists "config_ler" on public.config;
create policy "config_ler" on public.config for select to authenticated using (true);
grant select on public.config to authenticated;

insert into public.config (chave, valor, descricao) values
  ('mensalidade_valor', '100', 'Preço da mensalidade em MT'),
  ('dias_gratis', '30', 'Dias grátis para empresas novas'),
  ('bloquear_sem_pagamento', 'nao', 'sim = sem pagar a empresa fica sem acesso a publicar/anunciar/Live; nao = só recebe avisos'),
  ('mpesa_numero', '', 'Número M-Pesa que recebe os pagamentos (ex.: 84 123 4567)'),
  ('mpesa_nome', '', 'Nome do titular M-Pesa'),
  ('emola_numero', '', 'Número e-Mola que recebe os pagamentos (ex.: 86 123 4567)'),
  ('emola_nome', '', 'Nome do titular e-Mola'),
  ('turn_url', '', 'Opcional: servidor TURN para o Live (ex.: turn:global.relay.metered.ca:80)'),
  ('turn_user', '', 'Opcional: utilizador TURN'),
  ('turn_pass', '', 'Opcional: palavra-passe TURN')
on conflict (chave) do nothing;

-- 2) Validade da mensalidade no perfil
alter table public.perfis add column if not exists assinatura_ate timestamptz;

-- empresas que já existem: 30 dias grátis a partir de hoje
update public.perfis set assinatura_ate = now() + interval '30 days'
 where type = 'empresa' and assinatura_ate is null;

-- empresas novas: dias grátis automáticos
create or replace function public.dar_periodo_gratis()
returns trigger language plpgsql set search_path = public as $$
declare dias int;
begin
  if new.type = 'empresa' and new.assinatura_ate is null then
    select coalesce(nullif(valor, '')::int, 30) into dias from public.config where chave = 'dias_gratis';
    new.assinatura_ate := now() + make_interval(days => coalesce(dias, 30));
  end if;
  return new;
end $$;
drop trigger if exists perfis_periodo_gratis on public.perfis;
create trigger perfis_periodo_gratis before insert on public.perfis
  for each row execute function public.dar_periodo_gratis();

-- o utilizador não pode mudar a validade sozinho (nem tipo, papel, e-mail)
create or replace function public.bloquear_mudanca_tipo()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    new.type  := old.type;
    new.role  := old.role;
    new.email := old.email;
    new.id    := old.id;
    new.created_at := old.created_at;
    new.assinatura_ate := old.assinatura_ate;
  end if;
  new.updated_at := now();
  return new;
end $$;

-- empresa pode usar as funções pagas? (se o bloqueio estiver desligado, basta ser empresa)
create or replace function public.empresa_ativa()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis
                 where id = auth.uid() and type = 'empresa'
                   and (coalesce((select valor from public.config where chave = 'bloquear_sem_pagamento'), 'nao') <> 'sim'
                        or (assinatura_ate is not null and assinatura_ate > now())));
$$;
revoke execute on function public.empresa_ativa() from public, anon;
grant execute on function public.empresa_ativa() to authenticated;

-- 3) Publicar no feed, anunciar e criar campanhas: só empresas com mensalidade ativa
drop policy if exists "Allow insert for authenticated users" on public.posts;   -- regra antiga (qualquer pessoa)
drop policy if exists "posts_criar_se_empresa" on public.posts;
create policy "posts_criar_se_empresa" on public.posts for insert to authenticated
  with check (user_id = (select auth.uid()) and public.empresa_ativa());

drop policy if exists "vagas_criar_se_empresa" on public.vagas_anuncios;
create policy "vagas_criar_se_empresa" on public.vagas_anuncios for insert to authenticated
  with check (empresa_id = (select auth.uid()) and public.empresa_ativa());

drop policy if exists "campanhas_criar_se_empresa" on public.ad_campaigns;
create policy "campanhas_criar_se_empresa" on public.ad_campaigns for insert to authenticated
  with check (user_id = (select auth.uid()) and public.empresa_ativa());

-- 4) Pagamentos (M-Pesa / e-Mola, confirmados à mão pela equipa)
create table if not exists public.pagamentos (
  id bigint generated always as identity primary key,
  empresa_id uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  metodo text not null check (metodo in ('mpesa', 'emola')),
  meses int not null default 1 check (meses between 1 and 12),
  valor numeric(10,2) not null default 0,
  codigo_transacao text not null check (char_length(btrim(codigo_transacao)) between 4 and 40),
  telefone text not null check (char_length(btrim(telefone)) between 8 and 20),
  estado text not null default 'pendente' check (estado in ('pendente', 'confirmado', 'rejeitado')),
  nota_admin text,
  created_at timestamptz not null default now(),
  confirmado_em timestamptz
);
create unique index if not exists pagamentos_codigo_unico on public.pagamentos (upper(btrim(codigo_transacao)));
create index if not exists pagamentos_empresa_idx on public.pagamentos (empresa_id, created_at desc);

alter table public.pagamentos enable row level security;
drop policy if exists "pagamentos_enviar" on public.pagamentos;
create policy "pagamentos_enviar" on public.pagamentos for insert to authenticated
  with check (empresa_id = (select auth.uid()) and public.sou_empresa()
              and estado = 'pendente' and nota_admin is null and confirmado_em is null);
drop policy if exists "pagamentos_ver_os_meus" on public.pagamentos;
create policy "pagamentos_ver_os_meus" on public.pagamentos for select to authenticated
  using (empresa_id = (select auth.uid()));
grant select, insert on public.pagamentos to authenticated;

-- ao enviar: o valor é calculado aqui (não se confia no telemóvel) + limite anti-spam
create or replace function public.preparar_pagamento()
returns trigger language plpgsql security definer set search_path = public as $$
declare preco numeric;
begin
  if (select count(*) from public.pagamentos where empresa_id = new.empresa_id and estado = 'pendente') >= 3 then
    raise exception 'Já tem 3 pagamentos à espera de confirmação. Aguarde a confirmação da equipa.';
  end if;
  select coalesce(nullif(valor, '')::numeric, 100) into preco from public.config where chave = 'mensalidade_valor';
  new.valor := coalesce(preco, 100) * new.meses;
  new.codigo_transacao := upper(btrim(new.codigo_transacao));
  new.telefone := btrim(new.telefone);
  return new;
end $$;
revoke execute on function public.preparar_pagamento() from public, anon, authenticated;
drop trigger if exists pagamentos_preparar on public.pagamentos;
create trigger pagamentos_preparar before insert on public.pagamentos
  for each row execute function public.preparar_pagamento();

-- quando a equipa muda o estado para "confirmado": prolonga a mensalidade
create or replace function public.confirmar_pagamento()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.estado = 'confirmado' and old.estado <> 'confirmado' then
    new.confirmado_em := now();
    update public.perfis
       set assinatura_ate = greatest(coalesce(assinatura_ate, now()), now()) + make_interval(days => 30 * new.meses)
     where id = new.empresa_id;
  end if;
  return new;
end $$;
revoke execute on function public.confirmar_pagamento() from public, anon, authenticated;
drop trigger if exists pagamentos_confirmar on public.pagamentos;
create trigger pagamentos_confirmar before update on public.pagamentos
  for each row execute function public.confirmar_pagamento();

-- 5) Lives
create table if not exists public.lives (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  titulo text not null check (char_length(btrim(titulo)) between 1 and 120),
  estado text not null default 'ao_vivo' check (estado in ('ao_vivo', 'terminada')),
  pico_espectadores int not null default 0,
  started_at timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  ended_at timestamptz
);
create index if not exists lives_estado_idx on public.lives (estado, atualizado_em desc);

alter table public.lives enable row level security;
drop policy if exists "lives_ver" on public.lives;
create policy "lives_ver" on public.lives for select to authenticated using (true);
drop policy if exists "lives_iniciar" on public.lives;
create policy "lives_iniciar" on public.lives for insert to authenticated
  with check (user_id = (select auth.uid()) and public.empresa_ativa());
drop policy if exists "lives_atualizar" on public.lives;
create policy "lives_atualizar" on public.lives for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "lives_apagar" on public.lives;
create policy "lives_apagar" on public.lives for delete to authenticated
  using (user_id = (select auth.uid()));
grant select, insert, update, delete on public.lives to authenticated;

-- uma live só pode ser marcada como "terminada" (não volta a "ao vivo")
create or replace function public.proteger_live()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.user_id := old.user_id; new.started_at := old.started_at;
    if old.estado = 'terminada' then new.estado := 'terminada'; end if;
    if new.estado = 'terminada' and old.estado <> 'terminada' then new.ended_at := now(); end if;
  end if;
  return new;
end $$;
drop trigger if exists lives_proteger on public.lives;
create trigger lives_proteger before update on public.lives
  for each row execute function public.proteger_live();

-- lista "Ao vivo agora" atualiza sozinha
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'lives') then
    alter publication supabase_realtime add table public.lives;
  end if;
end $$;

-- a página de mensalidade atualiza sozinha quando a equipa confirma
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'pagamentos') then
    alter publication supabase_realtime add table public.pagamentos;
  end if;
end $$;
