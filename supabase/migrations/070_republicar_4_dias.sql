-- 070: "Republicar" passa de 7 para 4 dias.
-- As publicações só ficam 4 dias no feed; com 7 dias, uma publicação ficava 3 dias fora do feed
-- sem poder voltar. Agora: logo que sai do feed, o dono pode voltar a pô-la no topo.

create or replace function public.validar_republicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare o posts%rowtype; raiz bigint; ultima timestamptz;
begin
  if new.republicado_de is null then return new; end if;
  select * into o from posts where id = new.republicado_de;
  if not found or o.user_id is distinct from new.user_id then
    raise exception 'Só pode republicar as suas próprias publicações.';
  end if;
  raiz := coalesce(o.republicado_de, o.id);
  select max(created_at) into ultima from posts where user_id = new.user_id and (id = raiz or republicado_de = raiz);
  if ultima > now() - interval '4 days' then
    raise exception 'Esta publicação ainda está no feed. Pode voltar ao topo a partir de %.', to_char((ultima + interval '4 days') at time zone 'Africa/Maputo', 'DD/MM "às" HH24:MI');
  end if;
  new.republicado_de := raiz;
  new.media := o.media;              -- as mesmas fotos e vídeos (não se pode trocar por outros)
  new.image_url := o.image_url;
  new.oferta_preco := null; new.oferta_preco_antigo := null; new.oferta_ate := null;   -- a oferta antiga não passa
  return new;
end $$;
