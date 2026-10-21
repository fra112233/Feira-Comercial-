-- ============================================================
-- Feira Comercial — 046: Mais tarefas para a Equipa (Ajudante)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- 1) Lojas paradas: empresas sem publicar há 14 dias (ou que nunca publicaram)
--    ou sem foto. A Equipa envia uma mensagem de ajuda.
-- 2) Esconder conteúdo denunciado: publicação, vídeo ou comentário.
--    Esconder NÃO apaga: o dono continua a ver, os outros deixam de ver.
--    Pode ser desfeito. Fica registado quem escondeu. O dono recebe uma
--    mensagem da Equipa a explicar.
-- ============================================================

-- ─── 2) Esconder ───
alter table public.posts          add column if not exists oculto boolean not null default false;
alter table public.videos         add column if not exists oculto boolean not null default false;
alter table public.comments       add column if not exists oculto boolean not null default false;
alter table public.video_comments add column if not exists oculto boolean not null default false;

-- quem não é da Equipa não vê o que foi escondido (o dono continua a ver o seu)
drop policy if exists posts_ver on public.posts;
create policy posts_ver on public.posts for select to authenticated
  using (not oculto or user_id = (select auth.uid()) or (select sou_suporte()));
drop policy if exists videos_ver on public.videos;
create policy videos_ver on public.videos for select to authenticated
  using (not oculto or user_id = (select auth.uid()) or (select sou_suporte()));
drop policy if exists comments_ver on public.comments;
create policy comments_ver on public.comments for select to authenticated
  using (not oculto or user_id = (select auth.uid()) or (select sou_suporte()));
drop policy if exists vcom_ver on public.video_comments;
create policy vcom_ver on public.video_comments for select to authenticated
  using (not oculto or user_id = (select auth.uid()) or (select sou_suporte()));

-- o dono não pode "desesconder" sozinho ao editar
create or replace function public.proteger_oculto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.oculto is distinct from old.oculto and not coalesce(current_setting('fc.esconder', true), '') = '1' then
    new.oculto := old.oculto;
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_oculto on public.posts;
create trigger trg_proteger_oculto before update on public.posts for each row execute function public.proteger_oculto();
drop trigger if exists trg_proteger_oculto on public.videos;
create trigger trg_proteger_oculto before update on public.videos for each row execute function public.proteger_oculto();
-- ao criar, nunca começa escondido
create or replace function public.criar_visivel()
returns trigger language plpgsql set search_path = public as $$
begin new.oculto := false; return new; end $$;
do $$ declare t text; begin
  foreach t in array array['posts', 'videos', 'comments', 'video_comments'] loop
    execute format('drop trigger if exists trg_criar_visivel on public.%I', t);
    execute format('create trigger trg_criar_visivel before insert on public.%I for each row execute function public.criar_visivel()', t);
  end loop;
end $$;

-- a montra pública (sem conta) também não mostra fotos escondidas
do $$
declare def text;
begin
  def := pg_get_functiondef('public.montra_publica(uuid)'::regprocedure);
  if position('from posts where user_id = p.id order by' in def) > 0 then
    execute replace(def, 'from posts where user_id = p.id order by', 'from posts where user_id = p.id and not oculto order by');
  end if;
end $$;

-- esconder / mostrar (administrador ou ajudante)
create or replace function public.suporte_esconder(p_tipo text, p_id bigint, p_sim boolean, p_motivo text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
  dono uuid; nome text; novo bigint;
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  perform set_config('fc.esconder', '1', true);
  if p_tipo = 'post' then
    update posts set oculto = p_sim where id = p_id returning user_id into dono; nome := 'publicação';
  elsif p_tipo = 'video' then
    update videos set oculto = p_sim where id = p_id returning user_id into dono; nome := 'vídeo';
  elsif p_tipo = 'comentario' then
    update comments set oculto = p_sim where id = p_id returning user_id into dono; nome := 'comentário';
  elsif p_tipo = 'comentario_video' then
    update video_comments set oculto = p_sim where id = p_id returning user_id into dono; nome := 'comentário';
  else
    raise exception 'tipo inválido';
  end if;
  perform set_config('fc.esconder', '', true);
  if dono is null then raise exception 'não encontrado (pode já ter sido apagado)'; end if;

  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
    values (auth.uid(), case when p_sim then 'esconder_' else 'mostrar_' end || p_tipo, dono, null,
            p_tipo || ' ' || p_id || coalesce(' · ' || nullif(btrim(p_motivo), ''), ''));

  -- avisar o dono (só ao esconder)
  if p_sim and dono <> equipa then
    insert into messages (sender_id, receiver_id, content)
    values (equipa, dono,
      case when (select idioma from perfis where id = dono) = 'en' then
        'Hello! One of your ' || case p_tipo when 'post' then 'posts' when 'video' then 'videos' else 'comments' end ||
        ' was hidden after a report, because it does not follow the Feira Comercial rules. Only you can still see it. If you think this was a mistake, just reply here 🙏' || E'\nFeira Comercial Team'
      else
        'Olá! ' || case when p_tipo in ('post') then 'Uma publicação sua foi escondida' when p_tipo = 'video' then 'Um vídeo seu foi escondido'
                        else 'Um comentário seu foi escondido' end ||
        ' depois de uma denúncia, porque não cumpre as regras da Feira Comercial. Só você continua a vê-lo. Se acha que foi engano, responda aqui 🙏' || E'\nEquipa Feira Comercial'
      end)
    returning id into novo;
    insert into equipa_respostas (mensagem_id, autor_id) values (novo, auth.uid());
  end if;
  return p_sim;
end $$;
revoke all on function public.suporte_esconder(text, bigint, boolean, text) from public, anon;
grant execute on function public.suporte_esconder(text, bigint, boolean, text) to authenticated;
revoke all on function public.proteger_oculto() from public, anon, authenticated;

-- ─── 1) Lojas paradas ───
create or replace function public.suporte_lojas_paradas()
returns table (id uuid, full_name text, avatar_url text, city text, province text, idioma text, criado timestamptz,
               n_pubs int, ultima_pub timestamptz, sem_foto boolean, contactado_em timestamptz, respondeu boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  return query
  with pubs as (            -- uma só passagem pelas publicações
    select x.user_id, count(*)::int n, max(x.created_at) ult from posts x group by x.user_id
  ), contacto as (          -- última mensagem pessoal da Equipa (escrita por alguém, não automática)
    select m.receiver_id, max(m.created_at) cont
      from equipa_respostas r join messages m on m.id = r.mensagem_id
     where m.sender_id = equipa group by m.receiver_id
  ), lojas as (
    select p.*, coalesce(b.n, 0) n, b.ult, c.cont
      from perfis p
      left join pubs b on b.user_id = p.id
      left join contacto c on c.receiver_id = p.id
     where p.type = 'empresa' and p.role not in ('admin', 'equipa')
       and coalesce(p.bloqueado, false) = false
       and p.created_at < now() - interval '3 days'
  )
  select l.id, l.full_name, l.avatar_url, l.city, l.province, l.idioma, l.created_at,
         l.n, l.ult, coalesce(nullif(l.avatar_url, ''), '') = '', l.cont,
         l.cont is not null and exists (select 1 from messages m where m.sender_id = l.id and m.receiver_id = equipa and m.created_at > l.cont)
    from lojas l
   where l.n = 0 or l.ult < now() - interval '14 days' or coalesce(nullif(l.avatar_url, ''), '') = ''
   order by (l.cont is null or l.cont < now() - interval '14 days') desc,   -- por contactar primeiro
            (l.n = 0) desc, l.created_at desc
   limit 300;
end $$;
revoke all on function public.suporte_lojas_paradas() from public, anon;
grant execute on function public.suporte_lojas_paradas() to authenticated;
