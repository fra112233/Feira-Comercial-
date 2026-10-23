-- ============================================================
-- Feira Comercial — 055: Os nomes de quem reagiu só para quem publicou
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- Antes: qualquer conta conseguia ver quem reagiu a qualquer publicação. Um burlão
-- ou um concorrente podia abrir a lista de uma loja popular e escrever aos clientes
-- interessados a fingir ser a loja ou a oferecer mais barato.
-- Agora cada pessoa só lê:
--   • as suas próprias reações (para o botão mostrar "já reagi");
--   • as reações às SUAS publicações (quem publicou vê os nomes);
--   • a equipa de suporte vê tudo (para investigar denúncias).
-- Os outros veem só os totais por reação ("👍 8 · ❤️ 3"), pela função reacoes_resumo.
-- ============================================================

drop policy if exists likes_ver on public.likes;
create policy likes_ver on public.likes for select to authenticated
  using (user_id = (select auth.uid())
         or exists (select 1 from public.posts p where p.id = post_id and p.user_id = (select auth.uid()))
         or (select sou_suporte()));
revoke select on public.likes from anon;

-- totais por reação de uma publicação, sem nomes (para quem não publicou)
create or replace function public.reacoes_resumo(p_post bigint)
returns table(reaction text, n bigint)
language sql stable security definer set search_path = public as $$
  select l.reaction, count(*) from likes l
   where l.post_id = p_post
     and exists (select 1 from posts p where p.id = p_post
                  and (not p.oculto or p.user_id = auth.uid() or sou_suporte()))
   group by l.reaction;
$$;
revoke all on function public.reacoes_resumo(bigint) from public, anon;
grant execute on function public.reacoes_resumo(bigint) to authenticated;
