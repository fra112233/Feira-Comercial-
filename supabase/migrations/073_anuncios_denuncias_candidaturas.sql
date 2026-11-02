-- 073: anúncios mais seguros + candidaturas organizadas
--
-- A. DENUNCIAR ANÚNCIOS
--    • Qualquer pessoa pode denunciar um anúncio (1 vez por anúncio, até 5 por dia).
--    • Cada denúncia chega à Equipa como reclamação (tipo "denuncia", com o link do anúncio).
--    • Com 3 denúncias de contas diferentes (contas com mais de 3 dias e não suspensas), o
--      anúncio fica escondido "em revisão" até a Equipa decidir; a empresa é avisada.
--    • Um anúncio com um número da lista de burlas (no contacto, título ou descrição) fica
--      logo em revisão e a Equipa é avisada. A empresa não pode tirar o anúncio da revisão.
--
-- B. CANDIDATURAS A VAGAS
--    • Nas vagas, as pessoas candidatam-se dentro da Feira Comercial: nome, telefone,
--      mensagem curta e CV (PDF, Word ou foto). Nada de CVs espalhados pelo chat/WhatsApp.
--    • A empresa vê as candidaturas organizadas por vaga (nova / vista / selecionada / rejeitada).
--    • 1 candidatura por pessoa e vaga, até 10 por dia. O CV fica numa pasta privada: só o
--      candidato, a empresa daquela vaga e a Equipa o podem abrir.
--    • A empresa recebe UM aviso por vaga (atualizado com o número de candidaturas novas),
--      não um aviso por cada candidatura.

-- ───────────────────────── tipos de aviso novos ─────────────────────────
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio','marco_publicacao','marco_seguidor',
  'marco_mensagem','gratis_fim','mensalidade_fim','oferta_guardado','oferta_loja','resumo_semanal','lojas_hoje',
  'travao','numero_proibido','cobranca','gosto_story','numero_denunciado','numero_no_perfil','mesmo_aparelho',
  'gosto_retirado','candidatura','anuncio_revisao']));

-- ───────────────────────── A. denúncias ─────────────────────────
alter table public.vagas_anuncios add column if not exists em_revisao boolean not null default false;

-- escondido em revisão: só a empresa dona e a Equipa o veem
drop policy if exists vagas_ver on public.vagas_anuncios;
create policy vagas_ver on public.vagas_anuncios for select to authenticated
  using ((ativo and not em_revisao) or empresa_id = (select auth.uid()) or (select sou_suporte()));

-- a empresa não pode tirar o anúncio da revisão
create or replace function public.proteger_anuncio()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.views := old.views;
    new.empresa_id := old.empresa_id;
    new.data_publicacao := old.data_publicacao;
    new.em_revisao := old.em_revisao or new.em_revisao;   -- pode entrar em revisão, não pode sair
  end if;
  return new;
end $$;

-- número da lista de burlas num anúncio → em revisão + aviso à Equipa
create or replace function public.anuncio_numero_burla()
returns trigger language plpgsql security definer set search_path = public as $$
declare n text;
begin
  if auth.uid() is null then return new; end if;   -- só pedidos vindos da app (não scripts da Equipa)
  if tg_op = 'UPDATE' and new.contacto is not distinct from old.contacto and new.titulo is not distinct from old.titulo
     and new.descricao is not distinct from old.descricao then return new; end if;
  select np.numero into n from numeros_proibidos np
   where np.numero = any (numeros_em(coalesce(new.contacto, '') || ' ' || coalesce(new.titulo, '') || ' ' || coalesce(new.descricao, '')))
     and np.conta is distinct from new.empresa_id and coalesce(np.origem, '') <> 'mensagem'
   limit 1;
  if n is null then return new; end if;
  new.em_revisao := true;
  if not exists (select 1 from notificacoes where tipo = 'numero_no_perfil' and texto like '%' || n || '%'
                  and criado > now() - interval '1 day') then
    insert into notificacoes (user_id, autor_id, tipo, texto)
    select a.id, new.empresa_id, 'numero_no_perfil', 'pôs num anúncio o número ' || n || ' (anúncio escondido para revisão)'
      from perfis a where a.role = 'admin';
  end if;
  return new;
end $$;

drop trigger if exists ab_anuncio_numero_burla on public.vagas_anuncios;
create trigger ab_anuncio_numero_burla before insert or update on public.vagas_anuncios
  for each row execute function public.anuncio_numero_burla();

create table if not exists public.denuncias_anuncios (
  id bigint generated always as identity primary key,
  anuncio_id uuid not null references public.vagas_anuncios(id) on delete cascade,
  autor uuid not null references public.perfis(id) on delete cascade,
  motivo text not null check (motivo in ('burla', 'pede_dinheiro', 'falso', 'ofensivo', 'outro')),
  detalhe text check (detalhe is null or char_length(detalhe) <= 500),
  criado timestamptz not null default now(),
  unique (anuncio_id, autor)
);
create index if not exists denuncias_anuncios_autor_idx on public.denuncias_anuncios (autor, criado);
alter table public.denuncias_anuncios enable row level security;   -- sem políticas: só pelas funções abaixo
revoke all on public.denuncias_anuncios from anon, authenticated;

create or replace function public.denunciar_anuncio(p_anuncio uuid, p_motivo text, p_detalhe text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  eu uuid := auth.uid();
  me perfis%rowtype;
  a vagas_anuncios%rowtype;
  total int;
  ja_revisao boolean;
  nomes constant jsonb := '{"burla":"Parece burla","pede_dinheiro":"Pede dinheiro adiantado","falso":"Informação falsa ou enganosa","ofensivo":"Conteúdo ofensivo","outro":"Outro motivo"}';
  det text := nullif(left(btrim(coalesce(p_detalhe, '')), 500), '');
begin
  if eu is null then raise exception 'Entre na sua conta para denunciar um anúncio.' using errcode = 'P0001'; end if;
  select * into me from perfis where id = eu;
  if not found or coalesce(me.bloqueado, false) then raise exception 'A sua conta não pode fazer denúncias.' using errcode = 'P0001'; end if;
  if p_motivo is null or not (nomes ? p_motivo) then raise exception 'Escolha o motivo da denúncia.' using errcode = 'P0001'; end if;
  select * into a from vagas_anuncios where id = p_anuncio;
  if not found or (not a.ativo and not sou_suporte()) then raise exception 'Este anúncio já não existe.' using errcode = 'P0001'; end if;
  if a.empresa_id = eu then raise exception 'Não pode denunciar o seu próprio anúncio.' using errcode = 'P0001'; end if;
  if exists (select 1 from denuncias_anuncios where anuncio_id = p_anuncio and autor = eu) then
    raise exception 'Já denunciou este anúncio. Obrigado — a Equipa vai analisar.' using errcode = 'P0001';
  end if;
  if (select count(*) from denuncias_anuncios where autor = eu and criado > now() - interval '1 day') >= 5 then
    raise exception 'Já fez 5 denúncias hoje. Pode continuar amanhã.' using errcode = 'P0001';
  end if;

  insert into denuncias_anuncios (anuncio_id, autor, motivo, detalhe) values (p_anuncio, eu, p_motivo, det);

  -- chega à Equipa na lista de reclamações (com o link do anúncio)
  begin
    insert into reclamacoes (user_id, nome, email, tipo, assunto, mensagem, link, denunciado)
    values (eu,
            case when char_length(btrim(coalesce(me.full_name, ''))) >= 2 then left(btrim(me.full_name), 120) else 'Utilizador' end,
            coalesce(nullif(me.email, ''), (select email from auth.users where id = eu), 'sem-email@feira-comercial.com'),
            'denuncia',
            left('Anúncio denunciado: ' || a.titulo, 150),
            'Motivo: ' || (nomes ->> p_motivo) || '.' || coalesce(E'\n' || det, ''),
            'anuncio.html?a=' || p_anuncio,
            a.empresa_id);
  exception when others then null;   -- a denúncia fica guardada mesmo que a reclamação falhe
  end;

  select count(distinct d.autor)::int into total
    from denuncias_anuncios d join perfis p on p.id = d.autor
   where d.anuncio_id = p_anuncio and p.created_at < now() - interval '3 days' and not coalesce(p.bloqueado, false);

  ja_revisao := a.em_revisao;
  if total >= 3 and not a.em_revisao then
    update vagas_anuncios set em_revisao = true where id = p_anuncio;
    insert into notificacoes (user_id, autor_id, tipo, texto) values (a.empresa_id, a.empresa_id, 'anuncio_revisao', 'Anúncio «' || left(a.titulo, 80) || '»');
    ja_revisao := true;
  end if;
  return jsonb_build_object('ok', true, 'em_revisao', ja_revisao);
end $$;

-- a Equipa decide: mostrar outra vez ou manter escondido
create or replace function public.suporte_rever_anuncio(p_anuncio uuid, p_mostrar boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a vagas_anuncios%rowtype;
begin
  if not sou_suporte() then raise exception 'Só a Equipa pode rever anúncios.' using errcode = 'P0001'; end if;
  select * into a from vagas_anuncios where id = p_anuncio;
  if not found then raise exception 'Este anúncio já não existe.' using errcode = 'P0001'; end if;
  update vagas_anuncios set em_revisao = not p_mostrar where id = p_anuncio;
  insert into registo_admin (admin_id, acao, conta_a, motivo)
  values (auth.uid(), case when p_mostrar then 'anuncio_mostrar' else 'anuncio_esconder' end, a.empresa_id,
          left(coalesce(nullif(btrim(p_motivo), ''), a.titulo), 300));
end $$;

-- ───────────────────────── B. candidaturas ─────────────────────────
create table if not exists public.candidaturas (
  id bigint generated always as identity primary key,
  anuncio_id uuid not null references public.vagas_anuncios(id) on delete cascade,
  empresa_id uuid not null references public.perfis(id) on delete cascade,
  candidato uuid not null references public.perfis(id) on delete cascade,
  nome text not null check (char_length(btrim(nome)) between 2 and 120),
  telefone text not null check (char_length(telefone) <= 30),
  mensagem text check (mensagem is null or char_length(mensagem) <= 1000),
  cv text check (cv is null or char_length(cv) <= 300),
  estado text not null default 'nova' check (estado in ('nova', 'vista', 'selecionada', 'rejeitada')),
  criado timestamptz not null default now(),
  unique (anuncio_id, candidato)
);
create index if not exists candidaturas_empresa_idx on public.candidaturas (empresa_id, anuncio_id);
create index if not exists candidaturas_candidato_idx on public.candidaturas (candidato, criado);
alter table public.candidaturas enable row level security;
revoke all on public.candidaturas from anon, authenticated;
grant select, delete on public.candidaturas to authenticated;

-- o candidato vê as suas; a empresa vê as das suas vagas; a Equipa vê tudo
drop policy if exists candidaturas_ver on public.candidaturas;
create policy candidaturas_ver on public.candidaturas for select to authenticated
  using (candidato = (select auth.uid()) or empresa_id = (select auth.uid()) or (select sou_suporte()));
-- o candidato pode retirar a sua candidatura quando quiser
drop policy if exists candidaturas_retirar on public.candidaturas;
create policy candidaturas_retirar on public.candidaturas for delete to authenticated
  using (candidato = (select auth.uid()));

-- um aviso por vaga, atualizado com o número de candidaturas novas (não um aviso por candidatura)
create or replace function public.avisar_candidaturas(p_anuncio uuid, p_autor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a vagas_anuncios%rowtype; novas int; txt text; nid bigint;
begin
  select * into a from vagas_anuncios where id = p_anuncio;
  if not found then return; end if;
  select count(*) into novas from candidaturas where anuncio_id = p_anuncio and estado = 'nova';
  if novas = 0 then return; end if;
  txt := case when novas = 1 then '1 candidatura nova' else novas || ' candidaturas novas' end
         || ' · Vaga «' || left(a.titulo, 80) || '»';
  select id into nid from notificacoes
   where user_id = a.empresa_id and tipo = 'candidatura' and not lida
     and texto like '%· Vaga «' || left(a.titulo, 80) || '»'
   order by criado desc limit 1;
  if nid is not null then
    update notificacoes set texto = txt, autor_id = p_autor, criado = now() where id = nid;   -- sem novo aviso no telemóvel
  else
    insert into notificacoes (user_id, autor_id, tipo, texto) values (a.empresa_id, p_autor, 'candidatura', txt);
  end if;
exception when others then
  return;   -- o aviso nunca impede a candidatura
end $$;

create or replace function public.candidatar(p_anuncio uuid, p_nome text, p_telefone text,
  p_mensagem text default null, p_cv text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  eu uuid := auth.uid();
  me perfis%rowtype;
  a vagas_anuncios%rowtype;
  n text := (numeros_em(p_telefone))[1];
  novo bigint;
begin
  if eu is null then raise exception 'Entre na sua conta para se candidatar.' using errcode = 'P0001'; end if;
  select * into me from perfis where id = eu;
  if not found or coalesce(me.bloqueado, false) then raise exception 'Conta suspensa: contacte a equipa da Feira Comercial.' using errcode = 'P0001'; end if;
  select * into a from vagas_anuncios where id = p_anuncio;
  if not found or not a.ativo or a.em_revisao then raise exception 'Esta vaga já não está disponível.' using errcode = 'P0001'; end if;
  if a.tipo <> 'vaga' then raise exception 'Só é possível candidatar-se a vagas de emprego.' using errcode = 'P0001'; end if;
  if a.validade is not null and a.validade < (now() at time zone 'Africa/Maputo')::date then
    raise exception 'As candidaturas para esta vaga já terminaram.' using errcode = 'P0001';
  end if;
  if a.empresa_id = eu then raise exception 'Não se pode candidatar à sua própria vaga.' using errcode = 'P0001'; end if;
  if char_length(btrim(coalesce(p_nome, ''))) < 2 then raise exception 'Escreva o seu nome.' using errcode = 'P0001'; end if;
  if n is null then raise exception 'Indique um telefone de Moçambique (82 a 87 + 7 algarismos).' using errcode = 'P0001'; end if;
  if exists (select 1 from numeros_proibidos where numero = n and conta is distinct from eu and coalesce(origem, '') <> 'mensagem') then
    raise exception 'Este número não pode ser usado. Se acha que é um erro, fale com a Equipa.' using errcode = 'P0001';
  end if;
  if p_cv is not null and (p_cv not like eu::text || '/%'
     or not exists (select 1 from storage.objects where bucket_id = 'cvs' and name = p_cv)) then
    raise exception 'O CV não foi enviado. Escolha o ficheiro outra vez.' using errcode = 'P0001';
  end if;
  if exists (select 1 from candidaturas where anuncio_id = p_anuncio and candidato = eu) then
    raise exception 'Já se candidatou a esta vaga. A empresa já tem a sua candidatura.' using errcode = 'P0001';
  end if;
  if (select count(*) from candidaturas where candidato = eu and criado > now() - interval '1 day') >= 10 then
    raise exception 'Já enviou 10 candidaturas hoje. Pode continuar amanhã.' using errcode = 'P0001';
  end if;

  insert into candidaturas (anuncio_id, empresa_id, candidato, nome, telefone, mensagem, cv)
  values (p_anuncio, a.empresa_id, eu, left(btrim(p_nome), 120), n,
          nullif(left(btrim(coalesce(p_mensagem, '')), 1000), ''), p_cv)
  returning id into novo;
  perform avisar_candidaturas(p_anuncio, eu);
  return novo;
end $$;

-- a empresa muda o estado de uma candidatura
create or replace function public.candidatura_estado(p_id bigint, p_estado text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_estado not in ('nova', 'vista', 'selecionada', 'rejeitada') then raise exception 'Estado inválido.' using errcode = 'P0001'; end if;
  update candidaturas set estado = p_estado where id = p_id and (empresa_id = auth.uid() or sou_suporte());
  if not found then raise exception 'Candidatura não encontrada.' using errcode = 'P0001'; end if;
end $$;

-- a empresa abriu a lista de uma vaga: as novas passam a vistas e o aviso fica lido
create or replace function public.candidaturas_vistas(p_anuncio uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t text;
begin
  select titulo into t from vagas_anuncios where id = p_anuncio and empresa_id = auth.uid();
  if t is null then return; end if;
  update candidaturas set estado = 'vista' where anuncio_id = p_anuncio and estado = 'nova';
  update notificacoes set lida = true
   where user_id = auth.uid() and tipo = 'candidatura' and not lida and texto like '%· Vaga «' || left(t, 80) || '»';
end $$;

revoke all on function public.denunciar_anuncio(uuid, text, text) from public, anon;
revoke all on function public.suporte_rever_anuncio(uuid, boolean, text) from public, anon;
revoke all on function public.candidatar(uuid, text, text, text, text) from public, anon;
revoke all on function public.candidatura_estado(bigint, text) from public, anon;
revoke all on function public.candidaturas_vistas(uuid) from public, anon;
revoke all on function public.avisar_candidaturas(uuid, uuid) from public, anon, authenticated;
revoke all on function public.anuncio_numero_burla() from public, anon, authenticated;
grant execute on function public.denunciar_anuncio(uuid, text, text) to authenticated;
grant execute on function public.suporte_rever_anuncio(uuid, boolean, text) to authenticated;
grant execute on function public.candidatar(uuid, text, text, text, text) to authenticated;
grant execute on function public.candidatura_estado(bigint, text) to authenticated;
grant execute on function public.candidaturas_vistas(uuid) to authenticated;

-- ───────────────────────── pasta privada dos CVs ─────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cvs', 'cvs', false, 5242880, array[
  'application/pdf', 'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists cvs_enviar on storage.objects;
create policy cvs_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'cvs' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists cvs_ver on storage.objects;
create policy cvs_ver on storage.objects for select to authenticated
  using (bucket_id = 'cvs' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (select 1 from public.candidaturas c where c.cv = name and c.empresa_id = (select auth.uid()))
    or (select public.sou_suporte())));
drop policy if exists cvs_apagar on storage.objects;
create policy cvs_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'cvs' and (storage.foldername(name))[1] = (select auth.uid())::text);
