-- 068: pedido da coroa dourada com localização da loja (foto carimbada na hora, estilo Timestamp)
-- A foto da loja leva data, hora e localização gravadas; aqui guardamos também as coordenadas
-- para a Equipa abrir no mapa. A localização passa a ser obrigatória.

alter table public.verificacoes
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists precisao int,          -- metros (precisão do GPS)
  add column if not exists endereco text;         -- rua / bairro / cidade (OpenStreetMap), se houver

-- 1) a empresa pede (agora com localização)
drop function if exists public.pedir_verificacao(text, text, text, text);
create or replace function public.pedir_verificacao(p_tipo text, p_documento text, p_foto text, p_telefone text,
  p_lat double precision default null, p_lng double precision default null, p_precisao int default null, p_endereco text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); novo bigint; t text := regexp_replace(coalesce(p_telefone, ''), '[^0-9+ ]', '', 'g');
begin
  if eu is null then raise exception 'sem sessão'; end if;
  if not exists (select 1 from perfis where id = eu and type = 'empresa') then raise exception 'só para empresas'; end if;
  if exists (select 1 from perfis where id = eu and verificada_em is not null) then raise exception 'a sua loja já está verificada'; end if;
  if exists (select 1 from verificacoes where empresa_id = eu and estado = 'pendente') then raise exception 'já tem um pedido em análise'; end if;
  if split_part(coalesce(p_documento, ''), '/', 1) <> eu::text or split_part(coalesce(p_foto, ''), '/', 1) <> eu::text then raise exception 'ficheiros inválidos'; end if;
  if length(regexp_replace(t, '\D', '', 'g')) < 9 then raise exception 'telefone inválido'; end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'falta a localização da loja: ligue o GPS e tire a foto outra vez';
  end if;
  insert into verificacoes (empresa_id, documento_tipo, documento, foto, telefone, lat, lng, precisao, endereco)
  values (eu, p_tipo, p_documento, p_foto, left(btrim(t), 20), p_lat, p_lng,
          least(greatest(coalesce(p_precisao, 0), 0), 100000), left(nullif(btrim(p_endereco), ''), 200))
  returning id into novo;
  return novo;
end $$;
revoke all on function public.pedir_verificacao(text, text, text, text, double precision, double precision, int, text) from public, anon;
grant execute on function public.pedir_verificacao(text, text, text, text, double precision, double precision, int, text) to authenticated;

-- 2) lista para a Equipa (com a localização)
drop function if exists public.suporte_verificacoes();
create function public.suporte_verificacoes()
returns table (id bigint, empresa_id uuid, nome text, avatar_url text, city text, province text, criado_conta timestamptz,
               n_pubs int, estado text, documento_tipo text, documento text, foto text, telefone text,
               parecer text, parecer_nota text, parecer_por_nome text, parecer_em timestamptz, motivo text, criado timestamptz,
               lat double precision, lng double precision, precisao int, endereco text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_suporte() then raise exception 'sem permissão'; end if;
  return query
  select v.id, v.empresa_id, p.full_name, p.avatar_url, p.city, p.province, p.created_at,
         (select count(*)::int from posts x where x.user_id = p.id),
         v.estado, v.documento_tipo, v.documento, v.foto, v.telefone,
         v.parecer, v.parecer_nota, (select split_part(trim(a.full_name), ' ', 1) from perfis a where a.id = v.parecer_por),
         v.parecer_em, v.motivo, v.criado, v.lat, v.lng, v.precisao, v.endereco
    from verificacoes v join perfis p on p.id = v.empresa_id
   where v.estado = 'pendente' or v.criado > now() - interval '30 days'
   order by (v.estado = 'pendente') desc, v.criado desc
   limit 200;
end $$;
revoke all on function public.suporte_verificacoes() from public, anon;
grant execute on function public.suporte_verificacoes() to authenticated;
