-- ============================================================
-- 050 — Proteção contra burlões
--   1) Nomes falsos: ninguém pode usar um nome que imite a Equipa Feira Comercial
--      (também com truques como "F3ira", "Feira-Comercial", "Equipa Feira") nem o nome
--      de uma loja verificada (coroa dourada).
--   2) Travão automático: uma conta nova (menos de 30 dias, sem coroa) denunciada por
--      3 pessoas diferentes, que falaram com ela no chat, fica sem enviar mensagens nem
--      publicar até a equipa ver. A equipa recebe um aviso no sino.
-- ============================================================

-- ---------- 1) Nomes falsos ----------

-- "F3ira  Comércial!" → "feiracomercia" (minúsculas, sem acentos, números trocados por letras,
-- sem espaços nem sinais). O "l" passa a "i" para "Comercial" e "ComerciaI" serem iguais.
create or replace function public.nome_normalizado(t text)
returns text language sql immutable as $$
  select translate(regexp_replace(
           translate(lower(coalesce(t, '')),
             'áàâãäéèêëíìîïóòôõöúùûüçñ0134578@$!|',
             'aaaaaeeeeiiiiooooouuuucnoieastbasii'),
           '[^a-z0-9]', '', 'g'), 'l', 'i')
$$;

create or replace function public.impedir_nome_oficial()
returns trigger language plpgsql set search_path = public as $$
declare nome text; n text; utl text;
begin
  if coalesce(auth.role(), '') = 'service_role' then return new; end if;
  if new.role in ('admin', 'equipa') then return new; end if;
  if tg_op = 'UPDATE' and new.full_name is not distinct from old.full_name
                      and new.username  is not distinct from old.username then
    return new;
  end if;
  nome := translate(lower(coalesce(new.full_name, '')), 'áàâãéêíóôõúç', 'aaaaeeiooouc');
  n    := nome_normalizado(new.full_name);
  utl  := lower(coalesce(new.username, ''));
  if n ~ 'feiracomerc'
     or (n ~ 'feira' and n ~ '(equipa|suporte|oficia|apoio|admin|moderad|seguranc|atendiment)')
     or nome ~ '\m(administra\w*|admin|moderador\w*)\M'
     -- o utilizador (@) só é verificado quando a pessoa o muda (no registo é gerado a partir do e-mail)
     or (tg_op = 'UPDATE' and new.username is distinct from old.username
         and (nome_normalizado(utl) ~ 'feiracomerc' or utl ~ '^(admin|moderador)')) then
    raise exception 'Nome reservado: não pode usar "Feira Comercial", "Equipa", "Administrador" ou "Moderador" no nome.'
      using errcode = 'P0001';
  end if;
  -- nome igual ao de uma loja verificada (com coroa dourada), ou que o contém
  -- ("Loja Bom Preço!", "Loja Bom Preço Oficial"); aqui "!" e "|" são só sinais, não letras
  n := nome_normalizado(regexp_replace(coalesce(new.full_name, ''), '[!|]+', '', 'g'));
  if length(n) >= 4 and exists (
       select 1 from perfis p
         cross join lateral (select nome_normalizado(regexp_replace(coalesce(p.full_name, ''), '[!|]+', '', 'g')) as v) x
        where p.id <> new.id and p.verificada_em is not null and not coalesce(p.bloqueado, false)
          and (x.v = n or (length(x.v) >= 6 and position(x.v in n) > 0))) then
    raise exception 'Este nome pertence a uma loja verificada da Feira Comercial. Escolha outro nome.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

-- ---------- 2) Travão automático por denúncias ----------

-- quem foi denunciado (a Feira descobre-o a partir do link da denúncia; não se confia no que a app envia)
alter table public.reclamacoes add column if not exists denunciado uuid references public.perfis(id) on delete set null;
create index if not exists reclamacoes_denunciado_idx on public.reclamacoes (denunciado, created_at) where denunciado is not null;

-- quando a equipa tira a suspensão, as denúncias anteriores deixam de contar para o travão
alter table public.perfis add column if not exists revisto_em timestamptz;

create or replace function public.proteger_revisto()
returns trigger language plpgsql as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    new.revisto_em := old.revisto_em;
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_revisto on public.perfis;
create trigger trg_proteger_revisto before update on public.perfis
  for each row execute function public.proteger_revisto();

create or replace function public.denuncia_alvo()
returns trigger language plpgsql security definer set search_path = public as $$
declare l text := coalesce(new.link, ''); m text[]; alvo uuid;
begin
  new.denunciado := null;
  if new.tipo <> 'denuncia' then return new; end if;
  begin
    m := regexp_match(l, '[?&]com=(\d+)');
    if m is not null then select user_id into alvo from comments where id = m[1]::bigint; end if;
    if alvo is null then
      m := regexp_match(l, '[?&]vcom=(\d+)');
      if m is not null then select user_id into alvo from video_comments where id = m[1]::bigint; end if;
    end if;
    if alvo is null then
      m := regexp_match(l, '[?&]post=(\d+)');
      if m is not null then select user_id into alvo from posts where id = m[1]::bigint; end if;
    end if;
    if alvo is null then
      m := regexp_match(l, '(?:[?&]id=|/loja/)([0-9a-fA-F-]{36})');
      if m is not null then select id into alvo from perfis where id = m[1]::uuid; end if;
    end if;
  exception when others then alvo := null;
  end;
  if alvo is not null and alvo is distinct from new.user_id then new.denunciado := alvo; end if;
  return new;
end $$;
drop trigger if exists trg_denuncia_alvo on public.reclamacoes;
create trigger trg_denuncia_alvo before insert on public.reclamacoes
  for each row execute function public.denuncia_alvo();

alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto', 'comentario', 'resposta', 'seguir', 'publicacao', 'video', 'gosto_video', 'comentario_video',
  'live', 'avaliacao', 'resposta_avaliacao', 'convite_aceite', 'convite_premio', 'marco_publicacao',
  'marco_seguidor', 'marco_mensagem', 'gratis_fim', 'mensalidade_fim', 'oferta_guardado', 'oferta_loja',
  'resumo_semanal', 'lojas_hoje', 'travao']));

create or replace function public.travao_denuncias()
returns trigger language plpgsql security definer set search_path = public as $$
declare a perfis%rowtype; quantos int; desde timestamptz;
begin
  if new.tipo <> 'denuncia' or new.denunciado is null or new.user_id is null then return null; end if;
  select * into a from perfis where id = new.denunciado;
  if not found or coalesce(a.bloqueado, false) or a.role in ('admin', 'equipa', 'ajudante')
     or a.verificada_em is not null or a.created_at < now() - interval '30 days' then
    return null;
  end if;
  desde := greatest(now() - interval '30 days', coalesce(a.revisto_em, '-infinity'));
  -- pessoas diferentes, com conta há mais de 1 dia, que trocaram mensagens com a conta denunciada
  select count(distinct r.user_id) into quantos
    from reclamacoes r join perfis q on q.id = r.user_id
   where r.denunciado = a.id and r.tipo = 'denuncia' and r.created_at >= desde
     and q.created_at < now() - interval '1 day'
     and exists (select 1 from messages mm
                  where (mm.sender_id = r.user_id and mm.receiver_id = a.id)
                     or (mm.sender_id = a.id and mm.receiver_id = r.user_id));
  if quantos < 3 then return null; end if;

  update perfis set bloqueado = true,
         bloqueio_motivo = 'Em revisão: várias pessoas denunciaram esta conta. A equipa vai analisar em breve.'
   where id = a.id;
  insert into registo_admin (admin_id, acao, conta_a, motivo)
  values ('a73d8f73-5b2c-4f03-9deb-17aa890287dd', 'travao_automatico', a.id, quantos || ' denúncias de pessoas diferentes');
  insert into notificacoes (user_id, autor_id, tipo, texto)
  select p.id, a.id, 'travao', coalesce(a.full_name, 'Uma conta') || ' ficou em revisão: ' || quantos || ' denúncias'
    from perfis p where p.role in ('admin', 'ajudante');
  return null;
end $$;
drop trigger if exists trg_travao_denuncias on public.reclamacoes;
create trigger trg_travao_denuncias after insert on public.reclamacoes
  for each row execute function public.travao_denuncias();

-- tirar a suspensão marca a conta como revista (as denúncias antigas deixam de contar)
create or replace function public.admin_suspender(p_uid uuid, p_suspender boolean, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_uid = auth.uid() then raise exception 'não pode suspender a própria conta'; end if;
  update perfis set bloqueado = p_suspender,
         bloqueio_motivo = case when p_suspender then left(nullif(trim(p_motivo), ''), 300) else null end,
         revisto_em = case when p_suspender then revisto_em else now() end
  where id = p_uid;
end $$;

revoke execute on function public.denuncia_alvo() from public, anon, authenticated;
revoke execute on function public.travao_denuncias() from public, anon, authenticated;
revoke execute on function public.impedir_nome_oficial() from public, anon, authenticated;

-- ---------- 3) Saber se uma conta está suspensa (para avisar os clientes) ----------
-- só o sim/não; o motivo continua privado
grant select (bloqueado) on public.perfis to authenticated;

create or replace function public.perfil_completo(pid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.perfis; r jsonb;
begin
  if auth.uid() is null then return null; end if;
  select * into p from public.perfis where id = pid;
  if not found then return null; end if;
  if p.id = auth.uid() or public.sou_admin() then return to_jsonb(p); end if;

  r := jsonb_build_object(
    'id', p.id, 'username', p.username, 'full_name', p.full_name, 'avatar_url', p.avatar_url,
    'type', p.type, 'sector', p.sector, 'bio', p.bio, 'visibility', p.visibility,
    'created_at', p.created_at, 'gender', p.gender, 'city', p.city, 'province', p.province,
    'website', p.website, 'facebook', p.facebook, 'instagram', p.instagram,
    'opening_hours', p.opening_hours, 'bloqueado', coalesce(p.bloqueado, false));
  if p.type = 'empresa' then
    r := r || jsonb_build_object('phone', p.phone, 'whatsapp', p.whatsapp, 'email', p.email,
      'morada', p.morada, 'latitude', p.latitude, 'longitude', p.longitude);
  end if;
  return r;
end $$;
