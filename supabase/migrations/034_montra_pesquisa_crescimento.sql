-- ============================================================
-- Feira Comercial — 034: Montra pública, pesquisa de produtos e painel de crescimento
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Precisa da 025 e 032. Pode ser corrido mais de uma vez sem problema.
--
-- 1) Montra pública (loja.html): quem não tem conta pode VER a montra de uma
--    EMPRESA — nome, logótipo, setor, cidade, horário, produtos, fotos e estrelas.
--    Segurança: uma única função só de leitura; nada de pessoas particulares,
--    nada de telefone/WhatsApp/e-mail/morada/NUIT/mapa, nada de mensagens.
--    Para falar com a loja é preciso criar conta. Nenhuma tabela fica aberta.
-- 2) Pesquisa de produtos em todas as empresas (com sessão iniciada).
-- 3) Painel de crescimento para a Administração.
-- ============================================================

-- ---------- 1) Montra pública ----------
create or replace function public.montra_publica(pid uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'nome', p.full_name, 'logo', p.avatar_url, 'setor', p.sector, 'bio', left(p.bio, 600),
    'cidade', p.city, 'provincia', p.province, 'horario', p.opening_hours, 'desde', p.created_at,
    'oficial', p.role in ('admin', 'equipa'),
    'seguidores', (select count(*) from followers f where f.following_id = p.id),
    'avaliacao', (select jsonb_build_object('media', round(avg(estrelas)::numeric, 1), 'total', count(*))
                    from avaliacoes a where a.empresa_id = p.id),
    'produtos', coalesce((select jsonb_agg(jsonb_build_object('nome', x.nome, 'descricao', left(x.descricao, 200),
                                   'preco', x.preco, 'foto', x.foto_url) order by x.ordem, x.criado desc)
                          from (select * from produtos where user_id = p.id and disponivel
                                 order by ordem, criado desc limit 24) x), '[]'::jsonb),
    'fotos', coalesce((select jsonb_agg(u) from (
                 select m->>'url' as u
                   from (select media, created_at from posts where user_id = p.id order by created_at desc limit 30) po,
                        jsonb_array_elements(case when jsonb_typeof(po.media) = 'array' then po.media else '[]'::jsonb end) m
                  where coalesce(m->>'type', 'image') <> 'video' and (m->>'url') like 'https://%'
                  limit 12) f), '[]'::jsonb))
  from perfis p
  where p.id = pid
    and p.type = 'empresa'
    and coalesce(p.bloqueado, false) = false
    and coalesce(p.visibility, 'publico') = 'publico';
$$;
revoke all on function public.montra_publica(uuid) from public;
grant execute on function public.montra_publica(uuid) to anon, authenticated;

-- ---------- 2) Pesquisa de produtos ----------
create or replace function public.procurar_produtos(
  p_q text default '', p_provincia text default '', p_min numeric default null, p_max numeric default null,
  p_ordem text default 'relevancia', p_limite int default 30, p_offset int default 0)
returns table (id bigint, nome text, descricao text, preco numeric, foto_url text,
               empresa_id uuid, empresa text, logo text, cidade text, provincia text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare q text := translate(lower(btrim(coalesce(p_q, ''))), 'áàâãéêíóôõúç', 'aaaaeeiooouc');
begin
  if auth.uid() is null then raise exception 'sem sessão'; end if;
  return query
  select x.id, x.nome, left(x.descricao, 200), x.preco, x.foto_url, e.id, e.full_name, e.avatar_url, e.city, e.province
  from produtos x join perfis e on e.id = x.user_id
  where x.disponivel
    and e.type = 'empresa' and coalesce(e.bloqueado, false) = false
    and (q = '' or translate(lower(x.nome || ' ' || coalesce(x.descricao, '') || ' ' || coalesce(e.full_name, '') || ' ' || coalesce(e.sector, '')),
                             'áàâãéêíóôõúç', 'aaaaeeiooouc') like '%' || q || '%')
    and (coalesce(p_provincia, '') = '' or e.province = p_provincia)
    and (p_min is null or x.preco >= p_min)
    and (p_max is null or x.preco <= p_max)
  order by
    case when p_ordem = 'preco_asc' then x.preco end asc nulls last,
    case when p_ordem = 'preco_desc' then x.preco end desc nulls last,
    case when p_ordem = 'relevancia' and q <> '' then (translate(lower(x.nome), 'áàâãéêíóôõúç', 'aaaaeeiooouc') like q || '%') end desc,
    x.criado desc
  limit greatest(1, least(coalesce(p_limite, 30), 60)) offset greatest(0, coalesce(p_offset, 0));
end $$;
revoke all on function public.procurar_produtos(text, text, numeric, numeric, text, int, int) from public, anon;
grant execute on function public.procurar_produtos(text, text, numeric, numeric, text, int, int) to authenticated;

-- ---------- 3) Painel de crescimento ----------
create or replace function public.admin_crescimento(p_dias int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare d int := greatest(7, least(coalesce(p_dias, 30), 90)); r jsonb;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  with gente as (select p.* from perfis p where p.role not in ('admin', 'equipa')),
  recentes as (select g.* from gente g where g.created_at > now() - make_interval(days => d)),
  dias as (select generate_series((current_date - (d - 1)), current_date, interval '1 day')::date dia)
  select jsonb_build_object(
    'contas', (select count(*) from gente),
    'empresas', (select count(*) from gente where type = 'empresa'),
    'pessoas', (select count(*) from gente where type <> 'empresa'),
    'novas_hoje', (select count(*) from gente where created_at >= current_date),
    'novas_7d', (select count(*) from gente where created_at > now() - interval '7 days'),
    'novas_periodo', (select count(*) from recentes),
    'ativos_7d', (select count(*) from auth.users u join gente g on g.id = u.id where u.last_sign_in_at > now() - interval '7 days'),
    'passos_completos', (select count(*) from recentes r2 where
         coalesce(nullif(r2.avatar_url, ''), '') <> ''
     and coalesce(nullif(trim(r2.city), ''), nullif(trim(r2.province), '')) is not null
     and (select count(*) from followers f where f.follower_id = r2.id) >= 3
     and (case when r2.type = 'empresa' then exists (select 1 from posts x where x.user_id = r2.id)
               else exists (select 1 from likes l where l.user_id = r2.id) end)),
    'responderam', (select count(*) from recentes r3 where exists (
         select 1 from messages m join perfis e on e.id = m.receiver_id
          where m.sender_id = r3.id and e.role in ('admin', 'equipa'))),
    'empresas_em_dia', (select count(*) from gente where type = 'empresa' and assinatura_ate > now()),
    'receita_mes', (select coalesce(sum(valor), 0) from pagamentos where estado = 'confirmado'
                      and coalesce(confirmado_em, created_at) >= date_trunc('month', now())),
    'receita_mes_anterior', (select coalesce(sum(valor), 0) from pagamentos where estado = 'confirmado'
                      and coalesce(confirmado_em, created_at) >= date_trunc('month', now()) - interval '1 month'
                      and coalesce(confirmado_em, created_at) <  date_trunc('month', now())),
    'pagamentos_pendentes', (select count(*) from pagamentos where estado = 'pendente'),
    'produtos', (select count(*) from produtos where disponivel),
    'por_dia', (select jsonb_agg(jsonb_build_object(
          'dia', dias.dia,
          'contas', (select count(*) from gente g where g.created_at::date = dias.dia),
          'publicacoes', (select count(*) from posts x where x.created_at::date = dias.dia),
          'mensagens', (select count(*) from messages m where m.created_at::date = dias.dia
                          and m.sender_id <> 'a73d8f73-5b2c-4f03-9deb-17aa890287dd')) order by dias.dia)
        from dias)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_crescimento(int) from public, anon;
grant execute on function public.admin_crescimento(int) to authenticated;
