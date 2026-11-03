-- 076: links perigosos (Google Web Risk)
-- Quando uma mensagem ou um anúncio tem um link, a base de dados pede à função
-- "verificar-links" que pergunte à Google se o link é de burla, vírus ou programa indesejado.
--   • mensagem → alerta = 'link_perigoso' (aviso vermelho no chat de quem a recebe)
--   • anúncio  → escondido para revisão da Equipa + aviso à empresa
-- O pedido é feito depois de gravar (pg_net): nunca atrasa nem impede o envio.
-- Sem a chave WEB_RISK_KEY a função não faz nada.

-- respostas da Google guardadas 1 dia (poupa pedidos; só o servidor lê e escreve)
create table if not exists public.links_verificados (
  url text primary key,
  ameaca text,
  verificado timestamptz not null default now()
);
alter table public.links_verificados enable row level security;
revoke all on public.links_verificados from anon, authenticated;

create or replace function public.pedir_verificacao_links(p_corpo jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare tok text;
begin
  select token into tok from push_segredo where id = 1;
  if tok is null then return; end if;
  perform net.http_post(
    url := 'https://bljnkwrhqnpawclybqrw.supabase.co/functions/v1/verificar-links',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJsam5rd3JocW5wYXdjbHlicXJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3Njg1OTMsImV4cCI6MjA5MTM0NDU5M30.CX2UVsuUllQuqDWDfTop2Bb3f8IM9OzdGM3jUKToO78',
      'x-links-token', tok),
    body := p_corpo,
    timeout_milliseconds := 15000
  );
exception when others then
  return;   -- uma verificação que falha nunca impede a mensagem ou o anúncio
end $$;
revoke all on function public.pedir_verificacao_links(jsonb) from public, anon, authenticated;

-- só links de fora da Feira Comercial
create or replace function public.tem_link_externo(t text)
returns boolean language sql immutable set search_path = public as $$
  select coalesce(t, '') ~* '(https?://|www\.)'
     and regexp_replace(coalesce(t, ''), '(https?://|www\.)(www\.)?(feira-comercial\.com|[a-z0-9-]+\.supabase\.co)[^\s]*', '', 'gi') ~* '(https?://|www\.)'
$$;

create or replace function public.links_mensagem()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(new.deleted, false) and tem_link_externo(new.content) then
    perform pedir_verificacao_links(jsonb_build_object('mensagem', new.id));
  end if;
  return null;
end $$;
revoke all on function public.links_mensagem() from public, anon, authenticated;

drop trigger if exists trg_links_mensagem on public.messages;
create trigger trg_links_mensagem after insert on public.messages
  for each row execute function public.links_mensagem();

create or replace function public.links_anuncio()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if nullif(btrim(coalesce(new.link, '')), '') is not null
     or tem_link_externo(coalesce(new.titulo, '') || ' ' || coalesce(new.descricao, '')) then
    perform pedir_verificacao_links(jsonb_build_object('anuncio', new.id));
  end if;
  return null;
end $$;
revoke all on function public.links_anuncio() from public, anon, authenticated;

drop trigger if exists trg_links_anuncio on public.vagas_anuncios;
create trigger trg_links_anuncio after insert or update of link, titulo, descricao on public.vagas_anuncios
  for each row execute function public.links_anuncio();
