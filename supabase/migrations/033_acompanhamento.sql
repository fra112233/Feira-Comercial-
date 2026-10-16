-- ============================================================
-- Feira Comercial — 033: Acompanhamento de quem chegou
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Precisa da 031 e 032. Pode ser corrido mais de uma vez sem problema.
--
-- 1) Uma segunda mensagem da conta oficial, entre o 3.º e o 7.º dia, SÓ a quem
--    ficou parado: empresa que ainda não publicou, ou pessoa que ainda não segue ninguém.
--    Quem já está ativo não recebe nada. Cada conta recebe no máximo uma vez.
--    Corre todos os dias às 08:13 de Maputo.
-- 2) Administração → "Contas novas": quem chegou nos últimos dias, quanto já
--    avançou nos primeiros passos e se já lhe deu as boas-vindas pessoalmente.
-- ============================================================

-- ---------- 1) Mensagem do 3.º dia ----------
create or replace function public.acompanhamento_dia3()
returns int language plpgsql security definer set search_path = public as $$
declare
  equipa constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';
  p record; nome text; sugestoes text; n int := 0; pubs int; segue int;
begin
  for p in
    select x.* from perfis x
     where x.created_at <= now() - interval '3 days'
       and x.created_at >  now() - interval '7 days'
       and x.role not in ('admin', 'equipa')
       and coalesce(x.bloqueado, false) = false
       and not exists (select 1 from marcos m where m.user_id = x.id and m.tipo = 'msg_dia3')
  loop
    insert into marcos (user_id, tipo) values (p.id, 'msg_dia3') on conflict do nothing;   -- só uma vez
    nome := coalesce(' ' || nullif(split_part(trim(p.full_name), ' ', 1), ''), '');
    select count(*) into pubs from posts where user_id = p.id;
    select count(*) into segue from followers where follower_id = p.id;

    if p.type = 'empresa' and pubs = 0 then
      insert into messages (sender_id, receiver_id, content) values (equipa, p.id,
        case when p.idioma = 'en' then
          'Hello' || nome || '! 😊 How are your first days at Feira Comercial going?' || chr(10) || chr(10) ||
          'We noticed your business hasn''t posted yet. A post with a real photo of a product and its price is the best way to get your first customers.' || chr(10) || chr(10) ||
          '📸 Tip: on the home page, tap "Photos/Videos", choose the photo, write the price and tap "Publish". Your followers get an alert.' || chr(10) || chr(10) ||
          'Need help? Just reply here.' || chr(10) || chr(10) || 'With care,' || chr(10) || 'Feira Comercial Team 💛'
        else
          'Olá' || nome || '! 😊 Como estão a correr os primeiros dias na Feira Comercial?' || chr(10) || chr(10) ||
          'Reparámos que a sua empresa ainda não publicou nada. Uma publicação com uma foto real de um produto e o preço é a melhor forma de conquistar os primeiros clientes.' || chr(10) || chr(10) ||
          '📸 Dica: na página inicial, toque em "Fotos/Vídeos", escolha a foto, escreva o preço e toque em "Publicar". Quem o segue recebe um aviso.' || chr(10) ||
          '🎬 Veja como em 30 segundos: https://www.feira-comercial.com/media/para-empresas.mp4' || chr(10) || chr(10) ||
          'Precisa de ajuda? Responda aqui mesmo.' || chr(10) || chr(10) || 'Com carinho,' || chr(10) || 'Equipa Feira Comercial 💛'
        end);
      n := n + 1;

    elsif p.type <> 'empresa' and segue = 0 then
      select string_agg(e.full_name, ', ') into sugestoes from (
        select q.full_name from perfis q
         where q.type = 'empresa' and q.id <> p.id and coalesce(q.bloqueado, false) = false
           and coalesce(q.visibility, 'publico') = 'publico'
         order by (q.province is not distinct from p.province) desc,
                  (select count(*) from followers f where f.following_id = q.id) desc
         limit 3) e;
      insert into messages (sender_id, receiver_id, content) values (equipa, p.id,
        case when p.idioma = 'en' then
          'Hello' || nome || '! 😊 How are your first days at Feira Comercial going?' || chr(10) || chr(10) ||
          'Follow a few businesses to see their news, promotions and jobs in your feed.' ||
          coalesce(chr(10) || chr(10) || '⭐ Suggestions: ' || sugestoes || '.', '') || chr(10) || chr(10) ||
          '👉 See more in "Friends" → "Discover".' || chr(10) || chr(10) ||
          'Need help? Just reply here.' || chr(10) || chr(10) || 'With care,' || chr(10) || 'Feira Comercial Team 💛'
        else
          'Olá' || nome || '! 😊 Como estão a correr os primeiros dias na Feira Comercial?' || chr(10) || chr(10) ||
          'Siga algumas empresas para ver as novidades, promoções e vagas delas no seu feed.' ||
          coalesce(chr(10) || chr(10) || '⭐ Sugestões: ' || sugestoes || '.', '') || chr(10) || chr(10) ||
          '👉 Veja mais em "Amigos" → "Descobrir".' || chr(10) || chr(10) ||
          'Precisa de ajuda? Responda aqui mesmo.' || chr(10) || chr(10) || 'Com carinho,' || chr(10) || 'Equipa Feira Comercial 💛'
        end);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.acompanhamento_dia3() from public, anon, authenticated;

-- todos os dias às 06:13 UTC = 08:13 em Maputo
do $$ begin
  perform cron.unschedule('acompanhamento-dia3') where exists (select 1 from cron.job where jobname = 'acompanhamento-dia3');
  perform cron.schedule('acompanhamento-dia3', '13 6 * * *', 'select public.acompanhamento_dia3()');
end $$;

-- ---------- 2) Contas novas (Administração) ----------
create or replace function public.admin_contas_novas(p_dias int default 14)
returns table (id uuid, full_name text, avatar_url text, type text, city text, province text, idioma text,
               criado timestamptz, passos int, cumprimentado boolean, respondeu boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  select p.id, p.full_name, p.avatar_url, p.type, p.city, p.province, p.idioma, p.created_at,
         ( (coalesce(nullif(p.avatar_url, ''), '') <> '')::int
         + (coalesce(nullif(trim(p.city), ''), nullif(trim(p.province), '')) is not null)::int
         + ((select count(*) from followers f where f.follower_id = p.id) >= 3)::int
         + (case when p.type = 'empresa' then exists (select 1 from posts x where x.user_id = p.id)
                 else exists (select 1 from likes l where l.user_id = p.id) end)::int ),
         exists (select 1 from messages m where m.sender_id = auth.uid() and m.receiver_id = p.id),
         exists (select 1 from messages m join perfis e on e.id = m.receiver_id
                  where m.sender_id = p.id and e.role in ('admin', 'equipa'))
  from perfis p
  where p.created_at > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 14), 90)))
    and p.role not in ('admin', 'equipa')
  order by p.created_at desc;
end $$;
revoke all on function public.admin_contas_novas(int) from public, anon;
grant execute on function public.admin_contas_novas(int) to authenticated;
