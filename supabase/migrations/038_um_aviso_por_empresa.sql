-- ============================================================
-- Feira Comercial — 038: Um só aviso por empresa por dia
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Substitui a 037 (não é preciso ter corrido a 037). Pode repetir.
--
-- Regra: cada pessoa recebe NO MÁXIMO 1 aviso de cada empresa por dia
-- (dia de Maputo), por mais publicações que a empresa faça nesse dia.
--  • 1.ª publicação do dia → aviso novo (o telemóvel toca), para TODOS.
--  • Publicações seguintes no mesmo dia → nenhum aviso novo; o aviso de hoje
--    passa a mostrar a publicação mais recente, sem tocar.
--  • Oferta relâmpago ⚡ no mesmo dia → o aviso de hoje passa a mostrar a oferta
--    e volta a ficar "por ler", também sem tocar.
--  • Quem bloqueou a empresa e as contas suspensas não recebem.
-- ============================================================

create index if not exists notificacoes_autor_tipo_idx on public.notificacoes (user_id, autor_id, tipo, criado desc);

create or replace function public.notif_publicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  oferta boolean := new.oferta_ate is not null;
  m jsonb := case when jsonb_typeof(new.media) = 'array' then new.media else '[]'::jsonb end;
  hoje timestamptz := date_trunc('day', now() at time zone 'Africa/Maputo') at time zone 'Africa/Maputo';
  txt text;
begin
  txt := left(case
    when oferta then '⚡ Oferta: ' || replace(to_char(round(new.oferta_preco), 'FM999,999,990'), ',', ' ') || ' MT'
                     || coalesce(' · ' || nullif(trim(new.content), ''), '')
    else coalesce(nullif(trim(new.content), ''),
                  case when m->0->>'type' = 'video' then '🎥 Vídeo'
                       when jsonb_array_length(m) > 0 or new.image_url is not null then '📷 Foto' end)
  end, 140);

  -- quem já recebeu hoje um aviso desta empresa: só se atualiza (sem tocar)
  if oferta then
    update notificacoes set post_id = new.id, texto = txt, criado = now(), lida = false
     where tipo = 'publicacao' and autor_id = new.user_id and criado >= hoje;
  else
    update notificacoes set post_id = new.id, texto = txt, criado = now()
     where tipo = 'publicacao' and autor_id = new.user_id and criado >= hoje and not lida
       and coalesce(texto, '') not like '⚡%';   -- não se esconde uma oferta com uma publicação normal
  end if;

  -- 1.º aviso do dia: para todos os que ainda não receberam nada desta empresa hoje
  insert into notificacoes (user_id, autor_id, tipo, post_id, texto)
  select p.id, new.user_id, 'publicacao', new.id, txt
    from perfis p
   where p.id <> new.user_id
     and coalesce(p.bloqueado, false) = false
     and not exists (select 1 from bloqueios b where b.blocker_id = p.id and b.blocked_id = new.user_id)
     and not exists (select 1 from notificacoes n
                      where n.user_id = p.id and n.autor_id = new.user_id and n.tipo = 'publicacao'
                        and n.criado >= hoje);
  return null;
exception when others then
  return null;   -- um aviso que falha nunca impede a publicação
end $$;
