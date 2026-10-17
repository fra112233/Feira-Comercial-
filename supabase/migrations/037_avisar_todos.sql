-- ============================================================
-- Feira Comercial — 037: Todos sabem quando uma empresa publica
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Antes: só os SEGUIDORES recebiam o aviso de publicação nova.
-- Agora:
--  • Ofertas relâmpago ⚡ → TODOS recebem, sempre.
--  • Publicação normal   → os seguidores recebem sempre; quem ainda não segue
--    a empresa recebe no máximo 1 aviso dessa empresa a cada 12 horas
--    (para ninguém receber dezenas de avisos e desligar as notificações).
--  • O aviso diz o que foi publicado (o texto, ou "📷 Foto" / "🎥 Vídeo").
--  • Contas bloqueadas e quem bloqueou a empresa não recebem.
-- ============================================================

create index if not exists notificacoes_autor_tipo_idx on public.notificacoes (user_id, autor_id, tipo, criado desc);

create or replace function public.notif_publicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  oferta boolean := new.oferta_ate is not null;
  m jsonb := case when jsonb_typeof(new.media) = 'array' then new.media else '[]'::jsonb end;
  txt text;
begin
  txt := case
    when oferta then '⚡ Oferta: ' || replace(to_char(round(new.oferta_preco), 'FM999,999,990'), ',', ' ') || ' MT'
                     || coalesce(' · ' || nullif(trim(new.content), ''), '')
    else coalesce(nullif(trim(new.content), ''),
                  case when m->0->>'type' = 'video' then '🎥 Vídeo'
                       when jsonb_array_length(m) > 0 or new.image_url is not null then '📷 Foto' end)
  end;

  insert into notificacoes (user_id, autor_id, tipo, post_id, texto)
  select p.id, new.user_id, 'publicacao', new.id, left(txt, 140)
    from perfis p
   where p.id <> new.user_id
     and coalesce(p.bloqueado, false) = false
     and not exists (select 1 from bloqueios b where b.blocker_id = p.id and b.blocked_id = new.user_id)
     and ( oferta
        or exists (select 1 from followers f where f.follower_id = p.id and f.following_id = new.user_id)
        or not exists (select 1 from notificacoes n
                        where n.user_id = p.id and n.autor_id = new.user_id and n.tipo = 'publicacao'
                          and n.criado > now() - interval '12 hours'));
  return null;
exception when others then
  return null;   -- um aviso que falha nunca impede a publicação
end $$;
