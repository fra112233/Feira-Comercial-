-- 071: as reações mais escolhidas aparecem por baixo de cada publicação ("😂❤️👍 7").
-- Antes, a linha de resumo mostrava só a MINHA reação (ou 👍 se eu não tinha reagido), por isso
-- quem não reagiu não sabia que reações as outras pessoas tinham escolhido.
-- Agora cada publicação guarda as 3 reações mais escolhidas, calculadas pelo servidor sempre que
-- alguém reage, troca de reação ou tira a reação. Só os tipos e a ordem, sem nomes: quem reagiu
-- continua a ser visto só por quem publicou (migração 055).

alter table public.posts add column if not exists reacoes_top text[] not null default '{}';

-- contadores + 3 reações mais escolhidas (empate: a mais recente primeiro)
create or replace function public.atualizar_contadores_post()
returns trigger language plpgsql security definer set search_path = public as $$
declare pid bigint := coalesce(new.post_id, old.post_id);
begin
  update public.posts set
    curtidas_count    = (select count(*) from public.likes    where post_id = pid),
    comentarios_count = (select count(*) from public.comments where post_id = pid),
    reacoes_top       = coalesce((
      select array_agg(r order by n desc, ultimo desc) from (
        select coalesce(reaction, 'Curtir') r, count(*) n, max(created_at) ultimo
          from public.likes where post_id = pid
         group by 1 order by n desc, ultimo desc limit 3) t), '{}')
  where id = pid;
  return null;
end $$;

-- trocar de reação (😂 → ❤️) é um UPDATE: antes não recontava nada
drop trigger if exists likes_contar on public.likes;
create trigger likes_contar after insert or delete or update of reaction on public.likes
  for each row execute function public.atualizar_contadores_post();

-- a app não pode escrever estas reações à mão (como já acontece com os contadores)
create or replace function public.proteger_post()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.curtidas_count    := old.curtidas_count;
    new.comentarios_count := old.comentarios_count;
    new.reacoes_top       := old.reacoes_top;
    new.user_id    := old.user_id;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;

create or replace function public.valores_ao_criar()
returns trigger language plpgsql set search_path = public as $$
begin
  -- só para pedidos vindos da app (as funções da Equipa e do servidor não são afetadas)
  if current_user <> 'authenticated' then return new; end if;
  case TG_TABLE_NAME
    when 'posts' then
      new.created_at := now(); new.curtidas_count := 0; new.comentarios_count := 0; new.reacoes_top := '{}';
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

-- publicações que já existem
update public.posts p set reacoes_top = coalesce((
  select array_agg(r order by n desc, ultimo desc) from (
    select coalesce(reaction, 'Curtir') r, count(*) n, max(created_at) ultimo
      from public.likes where post_id = p.id
     group by 1 order by n desc, ultimo desc limit 3) t), '{}');
