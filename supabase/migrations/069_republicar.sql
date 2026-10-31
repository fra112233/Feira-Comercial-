-- 069: "Republicar" — a empresa volta a pôr no topo uma publicação sua, com as mesmas fotos/vídeos
-- (já guardados: publica na hora, sem enviar nada). O texto pode mudar; as fotos/vídeos não.
-- A mesma publicação só pode voltar ao topo uma vez a cada 7 dias (contado desde a última vez).

alter table public.posts add column if not exists republicado_de bigint references public.posts(id) on delete set null;
create index if not exists posts_republicado_de_idx on public.posts (republicado_de) where republicado_de is not null;

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
  if ultima > now() - interval '7 days' then
    raise exception 'Esta publicação pode voltar ao topo a partir de %.', to_char((ultima + interval '7 days') at time zone 'Africa/Maputo', 'DD/MM "às" HH24:MI');
  end if;
  new.republicado_de := raiz;
  new.media := o.media;              -- as mesmas fotos e vídeos (não se pode trocar por outros)
  new.image_url := o.image_url;
  new.oferta_preco := null; new.oferta_preco_antigo := null; new.oferta_ate := null;   -- a oferta antiga não passa
  return new;
end $$;
revoke all on function public.validar_republicacao() from public, anon, authenticated;

drop trigger if exists ab_republicar on public.posts;
create trigger ab_republicar before insert on public.posts
  for each row execute function public.validar_republicacao();
