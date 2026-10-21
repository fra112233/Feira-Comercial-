-- ============================================================
-- Feira Comercial — 049: Correções encontradas no teste geral (21/10/2026)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- 1) Ao CRIAR publicações, vídeos, comentários, mensagens, stories, avaliações,
--    lives, anúncios e pagamentos, a data e os contadores passam a ser sempre
--    os do servidor. Antes, alguém com conhecimentos técnicos podia:
--      • pôr uma data no futuro e ficar sempre no topo do feed;
--      • começar uma publicação já com 9 999 gostos ou visualizações;
--      • criar uma avaliação já com uma "resposta da loja" inventada;
--      • enviar um pagamento já com número de recibo.
-- 2) Se uma loja verificada passar a conta de Pessoa, perde a coroa.
-- 3) Três índices em falta (velocidade).
-- ============================================================

create or replace function public.valores_ao_criar()
returns trigger language plpgsql set search_path = public as $$
begin
  -- só para pedidos vindos da app (as funções da Equipa e do servidor não são afetadas)
  if current_user <> 'authenticated' then return new; end if;
  case TG_TABLE_NAME
    when 'posts' then
      new.created_at := now(); new.curtidas_count := 0; new.comentarios_count := 0;
    when 'videos' then
      new.created_at := now(); new.views := 0; new.likes_count := 0; new.comments_count := 0;
    when 'comments', 'video_comments', 'stories' then
      new.created_at := now();
    when 'messages' then
      new.created_at := now(); new.read_at := null; new.deleted := false;
      new.cleared_by_sender := false; new.cleared_by_receiver := false; new.reaction := null;
    when 'avaliacoes' then
      new.criado := now(); new.atualizado := now(); new.resposta := null;
    when 'lives' then
      new.started_at := now(); new.atualizado_em := now(); new.ended_at := null;
      new.espectadores := 0; new.pico_espectadores := 0; new.estado := 'ao_vivo';
    when 'vagas_anuncios' then
      new.data_publicacao := now(); new.views := 0;
    when 'pagamentos' then
      new.created_at := now(); new.numero_recibo := null;
    else null;
  end case;
  return new;
end $$;
revoke all on function public.valores_ao_criar() from public, anon, authenticated;

do $$ declare t text; begin
  foreach t in array array['posts','videos','comments','video_comments','stories','messages','avaliacoes','lives','vagas_anuncios','pagamentos'] loop
    execute format('drop trigger if exists aa_valores_ao_criar on public.%I', t);
    execute format('create trigger aa_valores_ao_criar before insert on public.%I for each row execute function public.valores_ao_criar()', t);
  end loop;
end $$;

-- 2) coroa: também sai se a conta deixar de ser empresa
create or replace function public.proteger_verificada()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('fc.verificar', true), '') = '1' then return new; end if;
  if new.verificada_em is distinct from old.verificada_em then
    new.verificada_em := old.verificada_em;
  end if;
  if old.verificada_em is not null
     and (new.full_name is distinct from old.full_name or new.type is distinct from old.type) then
    new.verificada_em := null;
  end if;
  return new;
end $$;

-- 3) índices
create index if not exists equipa_respostas_autor_idx on public.equipa_respostas (autor_id);
create index if not exists verificacoes_decidido_por_idx on public.verificacoes (decidido_por);
create index if not exists verificacoes_parecer_por_idx on public.verificacoes (parecer_por);

-- 4) esconder/mostrar um comentário acerta o número de comentários da publicação/vídeo
create or replace function public.contar_ao_esconder()
returns trigger language plpgsql security definer set search_path = public as $$
declare d int := case when new.oculto then -1 else 1 end;
begin
  if new.oculto is not distinct from old.oculto then return null; end if;
  if TG_TABLE_NAME = 'comments' then
    update posts set comentarios_count = greatest(0, coalesce(comentarios_count, 0) + d) where id = new.post_id;
  else
    update videos set comments_count = greatest(0, coalesce(comments_count, 0) + d) where id = new.video_id;
  end if;
  return null;
end $$;
revoke all on function public.contar_ao_esconder() from public, anon, authenticated;
drop trigger if exists trg_contar_ao_esconder on public.comments;
create trigger trg_contar_ao_esconder after update of oculto on public.comments for each row execute function public.contar_ao_esconder();
drop trigger if exists trg_contar_ao_esconder on public.video_comments;
create trigger trg_contar_ao_esconder after update of oculto on public.video_comments for each row execute function public.contar_ao_esconder();
