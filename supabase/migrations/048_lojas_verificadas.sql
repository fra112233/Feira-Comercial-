-- ============================================================
-- Feira Comercial — 048: Lojas verificadas (coroa dourada 👑)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • A empresa pede a verificação: documento (alvará, certidão, NUIT ou BI),
--   foto da loja e telefone.
-- • A Equipa (Ajudante) liga e dá o parecer: "Parece real" ou "Suspeito".
-- • Só o administrador aprova. A coroa 👑 aparece ao lado do nome.
-- • Documentos privados: só a Equipa os vê. Nunca são públicos.
-- • Se a loja mudar de nome, a coroa sai (tem de pedir de novo).
-- • O administrador pode retirar a coroa (ex.: burla confirmada).
-- ============================================================

alter table public.perfis add column if not exists verificada_em timestamptz;

-- a coroa só muda pelas funções da Equipa; mudar de nome tira a coroa
create or replace function public.proteger_verificada()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('fc.verificar', true), '') = '1' then return new; end if;
  if new.verificada_em is distinct from old.verificada_em then
    new.verificada_em := old.verificada_em;
  end if;
  if old.verificada_em is not null and new.full_name is distinct from old.full_name then
    new.verificada_em := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_verificada on public.perfis;
create trigger trg_proteger_verificada before update on public.perfis
  for each row execute function public.proteger_verificada();
revoke all on function public.proteger_verificada() from public, anon, authenticated;

-- pedidos de verificação
create table if not exists public.verificacoes (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references public.perfis(id) on delete cascade,
  estado text not null default 'pendente' check (estado in ('pendente', 'aprovada', 'recusada')),
  documento_tipo text not null check (documento_tipo in ('alvara', 'certidao', 'nuit', 'bi', 'outro')),
  documento text not null,           -- caminho no bucket privado "verificacoes"
  foto text not null,                -- caminho no bucket privado "verificacoes"
  telefone text not null,
  parecer text check (parecer in ('real', 'suspeito')),
  parecer_nota text,
  parecer_por uuid references public.perfis(id) on delete set null,
  parecer_em timestamptz,
  decidido_por uuid references public.perfis(id) on delete set null,
  decidido_em timestamptz,
  motivo text,                       -- motivo da recusa (a empresa vê)
  criado timestamptz not null default now()
);
create index if not exists verificacoes_empresa_idx on public.verificacoes (empresa_id, criado desc);
create unique index if not exists verificacoes_uma_pendente on public.verificacoes (empresa_id) where estado = 'pendente';
alter table public.verificacoes enable row level security;
revoke all on public.verificacoes from anon, authenticated;
grant select on public.verificacoes to authenticated;
drop policy if exists verificacoes_ver on public.verificacoes;
create policy verificacoes_ver on public.verificacoes for select to authenticated
  using (empresa_id = (select auth.uid()) or (select sou_suporte()));

-- ficheiros privados
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verificacoes', 'verificacoes', false, 6291456, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "verificacoes_enviar" on storage.objects;
create policy "verificacoes_enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'verificacoes' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "verificacoes_ver" on storage.objects;
create policy "verificacoes_ver" on storage.objects for select to authenticated
  using (bucket_id = 'verificacoes' and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.sou_suporte())));

-- 1) a empresa pede
create or replace function public.pedir_verificacao(p_tipo text, p_documento text, p_foto text, p_telefone text)
returns bigint language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); novo bigint; t text := regexp_replace(coalesce(p_telefone, ''), '[^0-9+ ]', '', 'g');
begin
  if eu is null then raise exception 'sem sessão'; end if;
  if not exists (select 1 from perfis where id = eu and type = 'empresa') then raise exception 'só para empresas'; end if;
  if exists (select 1 from perfis where id = eu and verificada_em is not null) then raise exception 'a sua loja já está verificada'; end if;
  if exists (select 1 from verificacoes where empresa_id = eu and estado = 'pendente') then raise exception 'já tem um pedido em análise'; end if;
  if split_part(coalesce(p_documento, ''), '/', 1) <> eu::text or split_part(coalesce(p_foto, ''), '/', 1) <> eu::text then raise exception 'ficheiros inválidos'; end if;
  if length(regexp_replace(t, '\D', '', 'g')) < 9 then raise exception 'telefone inválido'; end if;
  insert into verificacoes (empresa_id, documento_tipo, documento, foto, telefone)
  values (eu, p_tipo, p_documento, p_foto, left(btrim(t), 20)) returning id into novo;
  return novo;
end $$;
revoke all on function public.pedir_verificacao(text, text, text, text) from public, anon;
grant execute on function public.pedir_verificacao(text, text, text, text) to authenticated;

-- 2) lista para a Equipa
create or replace function public.suporte_verificacoes()
returns table (id bigint, empresa_id uuid, nome text, avatar_url text, city text, province text, criado_conta timestamptz,
               n_pubs int, estado text, documento_tipo text, documento text, foto text, telefone text,
               parecer text, parecer_nota text, parecer_por_nome text, parecer_em timestamptz, motivo text, criado timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  return query
  select v.id, v.empresa_id, p.full_name, p.avatar_url, p.city, p.province, p.created_at,
         (select count(*)::int from posts x where x.user_id = p.id),
         v.estado, v.documento_tipo, v.documento, v.foto, v.telefone,
         v.parecer, v.parecer_nota, (select split_part(trim(a.full_name), ' ', 1) from perfis a where a.id = v.parecer_por),
         v.parecer_em, v.motivo, v.criado
    from verificacoes v join perfis p on p.id = v.empresa_id
   where v.estado = 'pendente' or v.criado > now() - interval '30 days'
   order by (v.estado = 'pendente') desc, v.criado desc
   limit 200;
end $$;
revoke all on function public.suporte_verificacoes() from public, anon;
grant execute on function public.suporte_verificacoes() to authenticated;

-- 3) parecer da Equipa (depois de ligar)
create or replace function public.suporte_parecer_verificacao(p_id bigint, p_parecer text, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  if p_parecer not in ('real', 'suspeito') then raise exception 'parecer inválido'; end if;
  update verificacoes set parecer = p_parecer, parecer_nota = left(nullif(btrim(p_nota), ''), 500), parecer_por = auth.uid(), parecer_em = now()
   where id = p_id and estado = 'pendente';
  if not found then raise exception 'pedido não encontrado ou já decidido'; end if;
end $$;
revoke all on function public.suporte_parecer_verificacao(bigint, text, text) from public, anon;
grant execute on function public.suporte_parecer_verificacao(bigint, text, text) to authenticated;

-- 4) decisão (só o administrador)
create or replace function public.admin_decidir_verificacao(p_id bigint, p_aprovar boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
  v verificacoes; en boolean; novo bigint;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  select * into v from verificacoes where id = p_id and estado = 'pendente' for update;
  if not found then raise exception 'pedido não encontrado ou já decidido'; end if;
  if not p_aprovar and nullif(btrim(p_motivo), '') is null then raise exception 'escreva o motivo da recusa'; end if;
  update verificacoes set estado = case when p_aprovar then 'aprovada' else 'recusada' end,
         decidido_por = auth.uid(), decidido_em = now(), motivo = case when p_aprovar then null else left(btrim(p_motivo), 500) end
   where id = p_id;
  if p_aprovar then
    perform set_config('fc.verificar', '1', true);
    update perfis set verificada_em = now() where id = v.empresa_id;
    perform set_config('fc.verificar', '', true);
  end if;
  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
    values (auth.uid(), case when p_aprovar then 'verificar_sim' else 'verificar_nao' end, v.empresa_id, null, p_motivo);
  en := (select idioma from perfis where id = v.empresa_id) = 'en';
  insert into messages (sender_id, receiver_id, content) values (equipa, v.empresa_id,
    case when p_aprovar then
      case when en then 'Congratulations! 👑 Your shop is now verified. The golden crown appears next to your name, so customers know they can trust you.' || E'\nFeira Comercial Team'
           else 'Parabéns! 👑 A sua loja está verificada. A coroa dourada aparece ao lado do seu nome e os clientes sabem que podem confiar em si.' || E'\nEquipa Feira Comercial' end
    else
      case when en then 'We could not verify your shop yet. Reason: ' || btrim(p_motivo) || E'\nYou can send a new request in your profile. Need help? Just reply here.\nFeira Comercial Team'
           else 'Ainda não conseguimos verificar a sua loja. Motivo: ' || btrim(p_motivo) || E'\nPode enviar um novo pedido no seu perfil. Precisa de ajuda? Responda aqui.\nEquipa Feira Comercial' end
    end) returning id into novo;
  insert into equipa_respostas (mensagem_id, autor_id) values (novo, auth.uid());
end $$;
revoke all on function public.admin_decidir_verificacao(bigint, boolean, text) from public, anon;
grant execute on function public.admin_decidir_verificacao(bigint, boolean, text) to authenticated;

-- 5) retirar a coroa (só o administrador)
create or replace function public.admin_retirar_coroa(p_uid uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  perform set_config('fc.verificar', '1', true);
  update perfis set verificada_em = null where id = p_uid;
  perform set_config('fc.verificar', '', true);
  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo) values (auth.uid(), 'verificar_retirar', p_uid, null, p_motivo);
end $$;
revoke all on function public.admin_retirar_coroa(uuid, text) from public, anon;
grant execute on function public.admin_retirar_coroa(uuid, text) to authenticated;

-- 6) os selos que aparecem ao lado dos nomes: oficiais + lojas verificadas
do $$
begin
  drop function if exists public.selos();
  create function public.selos()
  returns table (id uuid, selo text, desde timestamptz)
  language sql stable security definer set search_path = public as $f$
    select p.id,
           case when p.role = 'admin' then 'Administrador' when p.role = 'equipa' then 'Oficial' else 'verificada' end,
           p.verificada_em
      from perfis p
     where p.role in ('admin', 'equipa') or (p.verificada_em is not null and coalesce(p.bloqueado, false) = false);
  $f$;
  revoke all on function public.selos() from public;
  grant execute on function public.selos() to anon, authenticated;   -- a montra pública (sem conta) também mostra a coroa
end $$;

-- montra pública: diz se a loja é verificada
do $$
declare def text;
begin
  def := pg_get_functiondef('public.montra_publica(uuid)'::regprocedure);
  if position('''verificada''' in def) = 0 then
    execute replace(def, '''oficial'', p.role in (''admin'', ''equipa''),', '''oficial'', p.role in (''admin'', ''equipa''), ''verificada'', p.verificada_em,');
  end if;
end $$;
