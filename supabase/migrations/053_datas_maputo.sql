-- ============================================================
-- 053 — Datas certas: dias do calendário e hora de Maputo
--   O servidor trabalha na hora de Londres (UTC) e contava dias em blocos de 24 horas.
--   Resultado: "Conta criada há 1 dia" para uma conta de anteontem, "termina hoje" para uma
--   mensalidade que acaba amanhã de madrugada, e gráficos por dia desviados 2 horas.
--   Agora tudo conta em dias do calendário de Maputo.
-- ============================================================

-- dia de calendário em Maputo (Moçambique não muda a hora no verão)
create or replace function public.dia_maputo(t timestamptz)
returns date language sql stable as $$ select (t at time zone 'Africa/Maputo')::date $$;
create or replace function public.hoje_maputo()
returns date language sql stable as $$ select (now() at time zone 'Africa/Maputo')::date $$;
create or replace function public.inicio_mes_maputo()
returns timestamptz language sql stable as $$ select date_trunc('month', now() at time zone 'Africa/Maputo') at time zone 'Africa/Maputo' $$;

-- ---------- Gráficos do painel por dia de Maputo (antes: dia de Londres; "novas hoje" começava às 02h) ----------
create or replace function public.admin_crescimento(p_dias int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare d int := greatest(7, least(coalesce(p_dias, 30), 90)); r jsonb;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  with gente as (select p.* from perfis p where p.role not in ('admin', 'equipa')),
  recentes as (select g.* from gente g where g.created_at > now() - make_interval(days => d)),
  dias as (select generate_series(hoje_maputo() - (d - 1), hoje_maputo(), interval '1 day')::date dia)
  select jsonb_build_object(
    'contas', (select count(*) from gente),
    'empresas', (select count(*) from gente where type = 'empresa'),
    'pessoas', (select count(*) from gente where type <> 'empresa'),
    'novas_hoje', (select count(*) from gente where dia_maputo(created_at) = hoje_maputo()),
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
                      and coalesce(confirmado_em, created_at) >= inicio_mes_maputo()),
    'receita_mes_anterior', (select coalesce(sum(valor), 0) from pagamentos where estado = 'confirmado'
                      and coalesce(confirmado_em, created_at) >= inicio_mes_maputo() - interval '1 month'
                      and coalesce(confirmado_em, created_at) <  inicio_mes_maputo()),
    'pagamentos_pendentes', (select count(*) from pagamentos where estado = 'pendente'),
    'produtos', (select count(*) from produtos where disponivel),
    'por_dia', (select jsonb_agg(jsonb_build_object(
          'dia', dias.dia,
          'contas', (select count(*) from gente g where dia_maputo(g.created_at) = dias.dia),
          'publicacoes', (select count(*) from posts x where dia_maputo(x.created_at) = dias.dia),
          'mensagens', (select count(*) from messages m where dia_maputo(m.created_at) = dias.dia
                          and m.sender_id <> 'a73d8f73-5b2c-4f03-9deb-17aa890287dd')) order by dias.dia)
        from dias)
  ) into r;
  return r;
end $$;

-- ---------- Estatísticas das empresas por dia de Maputo ----------
create or replace function public.minhas_estatisticas(p_dias int default 7)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  eu uuid := auth.uid();
  d int := greatest(1, least(coalesce(p_dias, 7), 90));
  ini timestamptz := now() - make_interval(days => d);
  ant timestamptz := now() - make_interval(days => 2 * d);
  r jsonb;
begin
  if eu is null then return null; end if;
  select jsonb_build_object(
    'dias', d,
    'atual', (select jsonb_object_agg(tipo, n) from (select tipo, count(*) n from eventos where empresa_id = eu and criado >= ini group by tipo) x),
    'anterior', (select jsonb_object_agg(tipo, n) from (select tipo, count(*) n from eventos where empresa_id = eu and criado >= ant and criado < ini group by tipo) x),
    'visitantes', (select count(distinct visitante_id) from eventos where empresa_id = eu and criado >= ini),
    'visitantes_ant', (select count(distinct visitante_id) from eventos where empresa_id = eu and criado >= ant and criado < ini),
    'gostos', (select count(*) from likes l join posts p on p.id = l.post_id where p.user_id = eu and l.created_at >= ini and l.user_id <> eu),
    'gostos_ant', (select count(*) from likes l join posts p on p.id = l.post_id where p.user_id = eu and l.created_at >= ant and l.created_at < ini and l.user_id <> eu),
    'comentarios', (select count(*) from comments c join posts p on p.id = c.post_id where p.user_id = eu and c.created_at >= ini and c.user_id <> eu),
    'comentarios_ant', (select count(*) from comments c join posts p on p.id = c.post_id where p.user_id = eu and c.created_at >= ant and c.created_at < ini and c.user_id <> eu),
    'conversas', (select count(distinct sender_id) from messages where receiver_id = eu and created_at >= ini),
    'conversas_ant', (select count(distinct sender_id) from messages where receiver_id = eu and created_at >= ant and created_at < ini),
    'seguidores', (select count(*) from followers where following_id = eu),
    'seguidores_novos', (select count(*) from followers where following_id = eu and created_at >= extract(epoch from ini) * 1000),
    'seguidores_novos_ant', (select count(*) from followers where following_id = eu and created_at >= extract(epoch from ant) * 1000 and created_at < extract(epoch from ini) * 1000),
    'por_dia', (
      select jsonb_agg(jsonb_build_object('dia', g.dia, 'perfil', coalesce(v.perfil, 0), 'publicacao', coalesce(v.publicacao, 0), 'contactos', coalesce(v.contactos, 0)) order by g.dia)
      from generate_series(hoje_maputo() - (d - 1), hoje_maputo(), interval '1 day') as g(dia)
      left join (
        select dia_maputo(criado) dia,
               count(*) filter (where tipo = 'perfil') perfil,
               count(*) filter (where tipo = 'publicacao') publicacao,
               count(*) filter (where tipo in ('whatsapp','ligar','email','site')) contactos
          from eventos where empresa_id = eu and criado >= ini group by 1) v on v.dia = g.dia::date),
    'top', (
      select jsonb_agg(t order by t.vistas desc, t.gostos desc) from (
        select p.id, left(coalesce(p.content, ''), 90) texto, p.created_at, p.curtidas_count gostos, p.comentarios_count comentarios,
               coalesce(p.media->0->>'url', p.image_url) foto, coalesce(p.media->0->>'type', 'image') foto_tipo,
               (select count(*) from eventos e where e.empresa_id = eu and e.tipo = 'publicacao' and e.alvo = p.id::text and e.criado >= ini) vistas
          from posts p where p.user_id = eu and p.created_at >= ant
          order by vistas desc, p.curtidas_count desc limit 5) t)
  ) into r;
  return r;
end $$;

-- ---------- Mensalidades: dias do calendário (antes: blocos de 24 h → "termina hoje"/"amanhã" trocados) ----------
create or replace function public.admin_mensalidades()
returns table (
  id uuid, nome text, avatar_url text, cidade text, provincia text, telefone text, whatsapp text, idioma text,
  criada timestamptz, ultimo_acesso timestamptz, paga_ate timestamptz, dias int, estado text,
  pagou_alguma_vez boolean, ultimo_pagamento timestamptz, total_pago numeric, pagamento_pendente boolean,
  responsavel uuid, responsavel_nome text, ultimo_contacto timestamptz, ultima_nota text, contactado_por text)
language plpgsql stable security definer set search_path = public as $$
declare admin boolean := sou_admin();
begin
  if not (admin or sou_suporte()) then raise exception 'só a equipa'; end if;
  return query
  with pg as (
    select p.empresa_id,
           max(p.confirmado_em) filter (where p.estado = 'confirmado') as ultimo,
           sum(p.valor) filter (where p.estado = 'confirmado')          as total,
           bool_or(p.estado = 'pendente')                               as pendente
      from pagamentos p group by p.empresa_id
  ),
  ult as (
    select distinct on (r.empresa_id) r.empresa_id, r.criado, r.nota, q.full_name as quem
      from cobrancas_registo r left join perfis q on q.id = r.por
     order by r.empresa_id, r.criado desc
  )
  select e.id, e.full_name, e.avatar_url, e.city, e.province, e.phone, e.whatsapp, e.idioma,
         e.created_at, u.last_sign_in_at, e.assinatura_ate,
         case when e.assinatura_ate is null then null
              else dia_maputo(e.assinatura_ate) - hoje_maputo() end,   -- dias do calendário (0 = acaba/acabou hoje)
         case when coalesce(pg.pendente, false) then 'pendente'
              when e.assinatura_ate is null or e.assinatura_ate <= now() then 'em_atraso'
              when dia_maputo(e.assinatura_ate) - hoje_maputo() <= 5 then 'a_terminar'
              when pg.ultimo is null then 'gratis'
              else 'em_dia' end,
         pg.ultimo is not null, pg.ultimo,
         case when admin then coalesce(pg.total, 0) end,
         coalesce(pg.pendente, false),
         c.responsavel, r.full_name, ult.criado, ult.nota, ult.quem
    from perfis e
    left join auth.users u on u.id = e.id
    left join pg on pg.empresa_id = e.id
    left join cobrancas c on c.empresa_id = e.id
    left join perfis r on r.id = c.responsavel
    left join ult on ult.empresa_id = e.id
   where e.type = 'empresa' and coalesce(e.role, 'user') not in ('admin', 'equipa')
     and (admin or c.responsavel = auth.uid())
   order by case when coalesce(pg.pendente, false) then 2
                 when e.assinatura_ate is null or e.assinatura_ate <= now() then 0
                 when dia_maputo(e.assinatura_ate) - hoje_maputo() <= 5 then 1 else 3 end,
            e.assinatura_ate nulls first;
end $$;

-- ---------- Lembrete "a terminar" com a mesma regra da lista ----------
create or replace function public.admin_lembrar_mensalidades(p_estado text default 'em_atraso')
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_estado not in ('em_atraso', 'a_terminar') then raise exception 'Estado inválido.' using errcode = 'P0001'; end if;
  with alvo as (
    select e.* from perfis e
     where e.type = 'empresa' and coalesce(e.role, 'user') not in ('admin', 'equipa') and not coalesce(e.bloqueado, false)
       and not exists (select 1 from pagamentos p where p.empresa_id = e.id and p.estado = 'pendente')
       and case when p_estado = 'em_atraso' then e.assinatura_ate is null or e.assinatura_ate <= now()
                else e.assinatura_ate > now() and dia_maputo(e.assinatura_ate) - hoje_maputo() <= 5 end
       and not exists (select 1 from cobrancas_registo r where r.empresa_id = e.id and r.nota like 'Lembrete enviado%' and r.criado > now() - interval '3 days')
  ), env as (
    insert into messages (sender_id, receiver_id, content)
    select 'a73d8f73-5b2c-4f03-9deb-17aa890287dd', p.id, texto_lembrete_mensalidade(p) from alvo a join perfis p on p.id = a.id
    returning receiver_id
  )
  insert into cobrancas_registo (empresa_id, por, nota)
  select receiver_id, auth.uid(), 'Lembrete enviado pela Equipa (mensagem automática)' from env;
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------- Texto do lembrete: hoje / amanhã / data, na data de Maputo ----------
create or replace function public.texto_lembrete_mensalidade(e perfis)
returns text language plpgsql stable security definer set search_path = public as $$
declare preco text := coalesce(nullif((select valor from config where chave = 'mensalidade_valor'), ''), '100');
        nome text := left(trim(coalesce(e.full_name, '')), 60);   -- empresa: nome completo ("Olá Loja Bom Preço!")
        d int := case when e.assinatura_ate is null then null else dia_maputo(e.assinatura_ate) - hoje_maputo() end;   -- dias do calendário
        acabou boolean := e.assinatura_ate is null or e.assinatura_ate <= now();
        data text := to_char(e.assinatura_ate at time zone 'Africa/Maputo', 'DD/MM/YYYY');   -- data de Maputo (não de Londres)
begin
  if e.idioma = 'en' then
    return 'Hello' || case when nome <> '' then ' ' || nome else '' end || '! 👋' || chr(10) || chr(10) ||
      case when acabou then 'Your Feira Comercial monthly plan has ended' || case when data is not null then ' (' || data || ')' else '' end || '.'
           when d = 0 then 'Your Feira Comercial monthly plan ends today.'
           when d = 1 then 'Your Feira Comercial monthly plan ends tomorrow (' || data || ').'
           else 'Your Feira Comercial monthly plan ends on ' || data || '.' end ||
      ' To keep posting, running ads and Lives, pay ' || preco || ' MT by M-Pesa, e-Mola or bank here: https://www.feira-comercial.com/mensalidade.html' || chr(10) || chr(10) ||
      'If you have already paid, reply to this message and we will confirm it. Thank you! 💛' || chr(10) || 'Feira Comercial Team';
  end if;
  return 'Olá' || case when nome <> '' then ' ' || nome else '' end || '! 👋' || chr(10) || chr(10) ||
    case when acabou then 'A sua mensalidade da Feira Comercial terminou' || case when data is not null then ' (' || data || ')' else '' end || '.'
         when d = 0 then 'A sua mensalidade da Feira Comercial termina hoje.'
         when d = 1 then 'A sua mensalidade da Feira Comercial termina amanhã (' || data || ').'
         else 'A sua mensalidade da Feira Comercial termina a ' || data || '.' end ||
    ' Para continuar a publicar, fazer anúncios e Lives, pague ' || preco || ' MT por M-Pesa, e-Mola ou banco aqui: https://www.feira-comercial.com/mensalidade.html' || chr(10) || chr(10) ||
    'Se já pagou, responda a esta mensagem e confirmamos. Obrigado! 💛' || chr(10) || 'Equipa Feira Comercial';
end $$;

-- ---------- Suspeitos: "Conta criada hoje / ontem / há N dias" por calendário ----------
create or replace function public.admin_suspeitos(p_dias int default 7)
returns table (id uuid, nome text, avatar_url text, tipo text, criada timestamptz, verificada boolean, pontos int, motivos text[])
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 30)));
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  with msgs as (
    select m.sender_id, m.receiver_id, m.created_at, m.content, m.alerta from messages m where m.created_at > desde
    union all
    select a.sender_id, a.receiver_id, a.enviada_em, a.content, null from mensagens_apagadas a where a.enviada_em > desde
  ),
  sinais as (
    select sender_id as uid,
           count(*) filter (where sinal_burla(content) = 'codigo')    as codigo,
           count(*) filter (where sinal_burla(content) = 'adiantado') as adiantado,
           count(*) filter (where sinal_burla(content) = 'premio')    as premio,
           count(*) filter (where sinal_burla(content) = 'equipa')    as equipa,
           count(*) filter (where alerta = 'numero_proibido')         as numero,
           count(*) filter (where content ~* '(https?://|www\.)' and content !~* 'feira-comercial\.com') as links
      from msgs group by sender_id
  ),
  contactos as (   -- conversas começadas por cada conta no período
    select m.sender_id as uid, count(distinct m.receiver_id) as novos,
           count(distinct m.receiver_id) filter (where m.created_at > now() - interval '24 hours') as novos24
      from messages m
     where m.created_at > desde
       and not exists (select 1 from messages r where r.sender_id = m.receiver_id and r.receiver_id = m.sender_id and r.created_at < m.created_at)
       and not exists (select 1 from messages o where o.sender_id = m.sender_id and o.receiver_id = m.receiver_id and o.created_at <= desde)
     group by m.sender_id
  ),
  denuncias as (
    select r.denunciado as uid, count(distinct r.user_id) as n from reclamacoes r
     where r.tipo = 'denuncia' and r.denunciado is not null and r.created_at > now() - interval '30 days' group by r.denunciado
  ),
  bloqs as (
    select b.blocked_id as uid, count(*) as n from bloqueios b where b.created_at > desde group by b.blocked_id
  ),
  cand as (
    select uid from sinais union select uid from contactos union select uid from denuncias union select uid from bloqs
  ),
  nota as (
    select p.id, p.full_name, p.avatar_url, p.type, p.created_at, p.verificada_em is not null as verif,
           coalesce(s.codigo, 0) codigo, coalesce(s.adiantado, 0) adiantado, coalesce(s.premio, 0) premio,
           coalesce(s.equipa, 0) equipa, coalesce(s.numero, 0) numero, coalesce(s.links, 0) links,
           coalesce(c.novos, 0) novos, coalesce(c.novos24, 0) novos24, coalesce(d.n, 0) denun, coalesce(b.n, 0) bloq,
           (exists (select 1 from numeros_proibidos np
                     where np.numero = any (numeros_em(coalesce(p.phone, '') || ' ' || coalesce(p.whatsapp, '')))
                       and np.conta is distinct from p.id)) num_perfil
      from cand x join perfis p on p.id = x.uid
      left join sinais s on s.uid = p.id left join contactos c on c.uid = p.id
      left join denuncias d on d.uid = p.id left join bloqs b on b.uid = p.id
     where not coalesce(p.bloqueado, false) and coalesce(p.role, 'user') not in ('admin', 'equipa', 'ajudante')
  ),
  pont as (
    select n.*,
      least(100, (
        (case when n.created_at > now() - interval '7 days' then 15 when n.created_at > now() - interval '30 days' then 5 else 0 end)
      + (case when n.novos24 >= 25 then 25 when n.novos24 >= 10 then 15 when n.novos >= 20 then 10 else 0 end)
      + least(30, n.adiantado * 5) + least(30, n.codigo * 10) + least(20, n.premio * 10) + least(30, n.equipa * 15)
      + (case when n.numero > 0 or n.num_perfil then 40 else 0 end)
      + (case when n.links > 0 then 5 else 0 end)
      + least(30, n.denun * 10) + least(20, n.bloq * 5)
      ) / (case when n.verif then 2 else 1 end))::int as pts
      from nota n
  )
  select p.id, p.full_name, p.avatar_url, p.type, p.created_at, p.verif, p.pts,
         array_remove(array[
           case when p.created_at > now() - interval '7 days' then
             (select case when d = 0 then 'Conta criada hoje' when d = 1 then 'Conta criada ontem' else 'Conta criada há ' || d || ' dias' end
                from (select greatest(0, hoje_maputo() - dia_maputo(p.created_at)) as d) x) end,
           case when p.novos24 >= 10 then 'Começou conversa com ' || p.novos24 || ' pessoas nas últimas 24 h'
                when p.novos >= 20 then 'Começou conversa com ' || p.novos || ' pessoas no período' end,
           case when p.adiantado > 0 then p.adiantado || ' mensagem(ns) a pedir pagamento adiantado' end,
           case when p.codigo > 0 then p.codigo || ' mensagem(ns) a pedir códigos, PIN ou palavra-passe' end,
           case when p.premio > 0 then p.premio || ' mensagem(ns) com prémios falsos' end,
           case when p.equipa > 0 then 'Diz ser da Equipa Feira Comercial (' || p.equipa || 'x)' end,
           case when p.numero > 0 then 'Enviou o número de uma conta suspensa (' || p.numero || 'x)'
                when p.num_perfil then 'Tem no perfil o número de uma conta suspensa' end,
           case when p.links > 0 then 'Enviou links para outros sites (' || p.links || 'x)' end,
           case when p.denun > 0 then p.denun || ' denúncia(s) nos últimos 30 dias' end,
           case when p.bloq > 0 then 'Bloqueada por ' || p.bloq || ' pessoa(s)' end,
           case when p.verif then 'Loja verificada (nota reduzida a metade)' end
         ], null)
    from pont p
    left join radar_dispensas rd on rd.conta = p.id
   where p.pts >= 20 and (rd.conta is null or p.pts > rd.pontos)
   order by p.pts desc
   limit 50;
end $$;
