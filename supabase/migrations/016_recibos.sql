-- ============================================================
-- Feira Comercial — 016: Recibos (e Factura/Recibo com IVA, mais tarde)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • Cada pagamento confirmado recebe um número de recibo seguido, que nunca se repete.
-- • A empresa (e o administrador) abrem o recibo em recibo.html e guardam em PDF.
-- • Enquanto a Feira Comercial não tiver NUIT e registo de IVA, o documento sai como
--   "RECIBO" sem IVA. Quando o administrador preencher os dados e ligar o IVA
--   (Administração → Dados dos recibos), passa a sair "FACTURA/RECIBO" com IVA de 17%.
-- ============================================================

-- 1) Número do recibo
create sequence if not exists public.recibo_seq;
alter table public.pagamentos add column if not exists numero_recibo bigint;
create unique index if not exists pagamentos_numero_recibo_uk on public.pagamentos (numero_recibo);

create or replace function public.numerar_recibo()
returns trigger language plpgsql as $$
begin
  if new.estado = 'confirmado' and new.numero_recibo is null then
    new.numero_recibo := nextval('public.recibo_seq');
  end if;
  return new;
end $$;

drop trigger if exists trg_numerar_recibo on public.pagamentos;
create trigger trg_numerar_recibo
  before insert or update on public.pagamentos
  for each row execute function public.numerar_recibo();

-- pagamentos já confirmados: numerar por ordem de confirmação
with x as (
  select id from public.pagamentos
  where estado = 'confirmado' and numero_recibo is null
  order by coalesce(confirmado_em, created_at), id
)
update public.pagamentos p set numero_recibo = nextval('public.recibo_seq')
from x where p.id = x.id;

-- 2) Dados de quem emite (preenchidos mais tarde na Administração)
insert into public.config (chave, valor, descricao) values
  ('recibo_nome',     'Feira Comercial',               'Nome legal no cabeçalho dos recibos'),
  ('recibo_nuit',     '',                              'NUIT da Feira Comercial (recibos)'),
  ('recibo_morada',   '',                              'Morada da Feira Comercial (recibos)'),
  ('recibo_telefone', '',                              'Telefone da Feira Comercial (recibos)'),
  ('recibo_email',    'contacto@feira-comercial.com',  'Email nos recibos'),
  ('iva_ativo',       'nao',                           'sim = emitir Factura/Recibo com IVA'),
  ('iva_taxa',        '17',                            'Taxa de IVA em %'),
  ('iva_incluido',    'sim',                           'sim = o valor da mensalidade já inclui IVA')
on conflict (chave) do nothing;

-- 2b) Assinatura (imagem) — guardada à parte; só sai dentro do recibo
create table if not exists public.recibo_imagens (
  chave text primary key,
  dados text not null default ''
);
alter table public.recibo_imagens enable row level security;
revoke all on public.recibo_imagens from anon, authenticated;

create or replace function public.admin_guardar_imagem(p_chave text, p_dados text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_chave not in ('assinatura') then raise exception 'chave não permitida'; end if;
  if length(coalesce(p_dados, '')) > 400000 then raise exception 'imagem demasiado grande'; end if;
  if coalesce(p_dados, '') <> '' and p_dados not like 'data:image/png;base64,%' then raise exception 'formato inválido'; end if;
  insert into recibo_imagens (chave, dados) values (p_chave, coalesce(p_dados, ''))
  on conflict (chave) do update set dados = excluded.dados;
end $$;
revoke all on function public.admin_guardar_imagem(text, text) from public, anon;
grant execute on function public.admin_guardar_imagem(text, text) to authenticated;

create or replace function public.admin_ver_imagem(p_chave text)
returns text language sql stable security definer set search_path = public as $$
  select case when sou_admin() then (select dados from recibo_imagens where chave = p_chave) end;
$$;
revoke all on function public.admin_ver_imagem(text) from public, anon;
grant execute on function public.admin_ver_imagem(text) to authenticated;

-- 3) Ler um recibo (só a própria empresa ou o administrador; só pagamentos confirmados)
create or replace function public.dados_recibo(pid bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  select jsonb_build_object(
    'numero', p.numero_recibo, 'id', p.id, 'empresa_id', p.empresa_id, 'metodo', p.metodo, 'meses', p.meses, 'valor', p.valor,
    'referencia', p.codigo_transacao, 'telefone', p.telefone,
    'pago_em', p.created_at, 'confirmado_em', coalesce(p.confirmado_em, p.created_at),
    'cliente', jsonb_build_object(
      'nome', e.full_name, 'nuit', e.nuit, 'morada', e.morada, 'cidade', e.city,
      'provincia', e.province, 'telefone', coalesce(e.phone, e.whatsapp), 'email', e.email),
    'emissor', (select jsonb_object_agg(chave, valor) from config
                where chave in ('recibo_nome','recibo_nuit','recibo_morada','recibo_telefone','recibo_email',
                                'iva_ativo','iva_taxa','iva_incluido','banco_nome','banco_nib','banco_titular')),
    'assinatura', (select nullif(dados, '') from recibo_imagens where chave = 'assinatura')
  ) into r
  from pagamentos p join perfis e on e.id = p.empresa_id
  where p.id = pid and p.estado = 'confirmado'
    and (p.empresa_id = auth.uid() or sou_admin());
  return r;
end $$;
revoke all on function public.dados_recibo(bigint) from public, anon;
grant execute on function public.dados_recibo(bigint) to authenticated;

-- 4) O administrador edita os dados dos recibos (só estas chaves)
create or replace function public.admin_guardar_config(p_chave text, p_valor text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_chave not in ('recibo_nome','recibo_nuit','recibo_morada','recibo_telefone','recibo_email',
                     'iva_ativo','iva_taxa','iva_incluido') then
    raise exception 'chave não permitida';
  end if;
  update config set valor = left(coalesce(p_valor, ''), 300) where chave = p_chave;
end $$;
revoke all on function public.admin_guardar_config(text, text) from public, anon;
grant execute on function public.admin_guardar_config(text, text) to authenticated;
