-- ============================================================
-- Feira Comercial — 036: Mensagens automáticas mais curtas
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- As pessoas não gostam de ler textos longos. A mensagem de boas-vindas e a
-- do 3.º dia passam a ter só o essencial: uma saudação, UMA ação e a assinatura.
-- ============================================================

-- ---------- 1) Boas-vindas ----------
create or replace function public.boas_vindas()
returns trigger language plpgsql security definer set search_path = public as $$
declare nome text := coalesce(' ' || nullif(split_part(trim(new.full_name), ' ', 1), ''), '');
begin
  if new.id = 'a73d8f73-5b2c-4f03-9deb-17aa890287dd' or new.role in ('admin', 'equipa') then return new; end if;
  if new.idioma = 'en' then
    insert into messages (sender_id, receiver_id, content) values ('a73d8f73-5b2c-4f03-9deb-17aa890287dd', new.id,
      'Hello' || nome || '! 👋 Welcome to Feira Comercial.' || chr(10) || chr(10) ||
      case when new.type = 'empresa'
        then '📸 Start now: publish your first product with a photo and price.'
        else '⭐ Start now: follow a few businesses to see their news.' end
      || chr(10) || chr(10) ||
      'Questions? Reply here.' || chr(10) ||
      'Feira Comercial Team 💛' || chr(10) || chr(10) ||
      '🔒 We never ask for your password.');
  else
    insert into messages (sender_id, receiver_id, content) values ('a73d8f73-5b2c-4f03-9deb-17aa890287dd', new.id,
      'Olá' || nome || '! 👋 Bem-vindo(a) à Feira Comercial.' || chr(10) || chr(10) ||
      case when new.type = 'empresa'
        then '📸 Comece já: publique o seu 1.º produto com foto e preço.' || chr(10) ||
             '🎬 Veja como (30 s): https://www.feira-comercial.com/media/para-empresas.mp4'
        else '⭐ Comece já: siga algumas empresas para ver as novidades.' || chr(10) ||
             '🎬 Veja como (30 s): https://www.feira-comercial.com/media/conheca.mp4' end
      || chr(10) || chr(10) ||
      'Dúvidas? Responda aqui.' || chr(10) ||
      'Equipa Feira Comercial 💛' || chr(10) || chr(10) ||
      '🔒 Nunca pedimos a sua palavra-passe.');
  end if;
  return new;
exception when others then
  return new;   -- a mensagem nunca impede a criação da conta
end $$;

-- ---------- 2) Mensagem do 3.º dia ----------
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
          'Hello' || nome || '! 😊 Your business hasn''t posted yet.' || chr(10) || chr(10) ||
          '📸 Post 1 product with a photo and price — that''s how customers find you.' || chr(10) || chr(10) ||
          'Feira Comercial Team 💛'
        else
          'Olá' || nome || '! 😊 A sua empresa ainda não publicou.' || chr(10) || chr(10) ||
          '📸 Publique 1 produto com foto e preço — é assim que chegam os clientes.' || chr(10) ||
          '🎬 Veja como: https://www.feira-comercial.com/media/para-empresas.mp4' || chr(10) || chr(10) ||
          'Equipa Feira Comercial 💛'
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
          'Hello' || nome || '! 😊 Follow a few businesses to see promotions and jobs.' ||
          coalesce(chr(10) || chr(10) || '⭐ Try: ' || sugestoes, '') || chr(10) || chr(10) ||
          'Feira Comercial Team 💛'
        else
          'Olá' || nome || '! 😊 Siga algumas empresas para ver promoções e vagas.' ||
          coalesce(chr(10) || chr(10) || '⭐ Experimente: ' || sugestoes, '') || chr(10) || chr(10) ||
          'Equipa Feira Comercial 💛'
        end);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.acompanhamento_dia3() from public, anon, authenticated;
