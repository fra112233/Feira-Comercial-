-- ============================================================
-- Feira Comercial — 038: Um só aviso por empresa
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Substitui a 037 (pode correr esta mesmo sem ter corrido a 037). Pode repetir.
--
-- Se uma empresa publica várias vezes, a pessoa NÃO recebe vários avisos:
--  • enquanto o aviso dessa empresa não for lido, ele é só ATUALIZADO para a
--    publicação mais recente (sem novo toque no telemóvel);
--  • depois de lido, a próxima publicação gera um aviso novo;
--  • quem não segue a empresa recebe no máximo 1 aviso dela a cada 12 horas;
--  • oferta relâmpago ⚡: substitui o aviso antigo dessa empresa e avisa todos.
-- ============================================================

create index if not exists notificacoes_autor_tipo_idx on public.notificacoes (user_id, autor_id, tipo, criado desc);

create or replace function public.notif_publicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  oferta boolean := new.oferta_ate is not null;
  m jsonb := case when jsonb_typeof(new.media) = 'array' then new.media else '[]'::jsonb end;
  txt text;
begin
  txt := left(case
    when oferta then '⚡ Oferta: ' || replace(to_char(round(new.oferta_preco), 'FM999,999,990'), ',', ' ') || ' MT'
                     || coalesce(' · ' || nullif(trim(new.content), ''), '')
    else coalesce(nullif(trim(new.content), ''),
                  case when m->0->>'type' = 'video' then '🎥 Vídeo'
                       when jsonb_array_length(m) > 0 or new.image_url is not null then '📷 Foto' end)
  end, 140);

  if oferta then
    -- a oferta substitui o aviso antigo (ainda por ler) desta empresa
    delete from notificacoes where tipo = 'publicacao' and autor_id = new.user_id and not lida;
  else
    -- quem ainda não leu o aviso desta empresa: só se atualiza (sem novo toque),
    -- exceto se esse aviso for de uma oferta (não se apaga uma oferta com uma publicação normal)
    update notificacoes set post_id = new.id, texto = txt, criado = now()
     where tipo = 'publicacao' and autor_id = new.user_id and not lida
       and coalesce(texto, '') not like '⚡%';
  end if;

  insert into notificacoes (user_id, autor_id, tipo, post_id, texto)
  select p.id, new.user_id, 'publicacao', new.id, txt
    from perfis p
   where p.id <> new.user_id
     and coalesce(p.bloqueado, false) = false
     and not exists (select 1 from bloqueios b where b.blocker_id = p.id and b.blocked_id = new.user_id)
     -- já tem um aviso desta empresa por ler → não recebe outro
     and not exists (select 1 from notificacoes n
                      where n.user_id = p.id and n.autor_id = new.user_id and n.tipo = 'publicacao' and not n.lida)
     and ( oferta
        or exists (select 1 from followers f where f.follower_id = p.id and f.following_id = new.user_id)
        or not exists (select 1 from notificacoes n
                        where n.user_id = p.id and n.autor_id = new.user_id and n.tipo = 'publicacao'
                          and n.criado > now() - interval '12 hours'));
  return null;
exception when others then
  return null;   -- um aviso que falha nunca impede a publicação
end $$;
