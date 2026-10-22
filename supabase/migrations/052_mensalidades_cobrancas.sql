-- ============================================================
-- 052 — Mensalidades e cobranças
--   O administrador vê que empresas já pagaram e quais estão em atraso, atribui
--   empresas a alguém da equipa (Ajudante) para as cobrar, regista os contactos
--   ("prometeu pagar sexta") e pode enviar um lembrete a todas as que estão em atraso.
--   O Ajudante só vê as empresas que lhe foram atribuídas, sem os totais recebidos.
-- ============================================================

create table if not exists public.cobrancas (
  empresa_id    uuid primary key references public.perfis(id) on delete cascade,
  responsavel   uuid references public.perfis(id) on delete set null,
  atribuido_por uuid,
  atribuido_em  timestamptz not null default now()
);
alter table public.cobrancas enable row level security;

create table if not exists public.cobrancas_registo (
  id         bigserial primary key,
  empresa_id uuid not null references public.perfis(id) on delete cascade,
  por        uuid references public.perfis(id) on delete set null,
  nota       text not null check (char_length(nota) between 1 and 500),
  criado     timestamptz not null default now()
);
alter table public.cobrancas_registo enable row level security;
create index if not exists cobrancas_registo_empresa_idx on public.cobrancas_registo (empresa_id, criado desc);

alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto', 'comentario', 'resposta', 'seguir', 'publicacao', 'video', 'gosto_video', 'comentario_video',
  'live', 'avaliacao', 'resposta_avaliacao', 'convite_aceite', 'convite_premio', 'marco_publicacao',
  'marco_seguidor', 'marco_mensagem', 'gratis_fim', 'mensalidade_fim', 'oferta_guardado', 'oferta_loja',
  'resumo_semanal', 'lojas_hoje', 'travao', 'numero_proibido', 'cobranca']));

-- ---------- a lista ----------
-- estado: 'pendente' (pagou, falta a equipa confirmar) · 'em_atraso' · 'a_terminar' (5 dias ou menos)
--         · 'gratis' (ainda no período grátis, nunca pagou) · 'em_dia'
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
              else ceil(extract(epoch from (e.assinatura_ate - now())) / 86400)::int end,
         case when coalesce(pg.pendente, false) then 'pendente'
              when e.assinatura_ate is null or e.assinatura_ate <= now() then 'em_atraso'
              when e.assinatura_ate <= now() + interval '5 days' then 'a_terminar'
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
                 when e.assinatura_ate <= now() + interval '5 days' then 1 else 3 end,
            e.assinatura_ate nulls first;
end $$;

-- pessoas da equipa que podem cobrar (para escolher o responsável)
create or replace function public.admin_membros_equipa()
returns table (id uuid, nome text, funcao text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query select p.id, p.full_name, p.role from perfis p where p.role in ('admin', 'ajudante') order by p.role, p.full_name;
end $$;

-- atribuir (ou tirar, com p_responsavel = null) uma empresa a alguém da equipa
create or replace function public.admin_cobranca_atribuir(p_empresa uuid, p_responsavel uuid)
returns void language plpgsql security definer set search_path = public as $$
declare nome text;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if p_responsavel is null then delete from cobrancas where empresa_id = p_empresa; return; end if;
  if not exists (select 1 from perfis where id = p_responsavel and role in ('admin', 'ajudante')) then
    raise exception 'Só se pode atribuir a um administrador ou Ajudante.' using errcode = 'P0001';
  end if;
  select full_name into nome from perfis where id = p_empresa and type = 'empresa';
  if not found then raise exception 'Empresa não encontrada.' using errcode = 'P0001'; end if;
  insert into cobrancas (empresa_id, responsavel, atribuido_por) values (p_empresa, p_responsavel, auth.uid())
  on conflict (empresa_id) do update set responsavel = excluded.responsavel, atribuido_por = excluded.atribuido_por, atribuido_em = now();
  insert into cobrancas_registo (empresa_id, por, nota)
  values (p_empresa, auth.uid(), 'Atribuída a ' || coalesce((select full_name from perfis where id = p_responsavel), 'alguém da equipa'));
  if p_responsavel <> auth.uid() then
    insert into notificacoes (user_id, autor_id, tipo, texto) values (p_responsavel, p_empresa, 'cobranca', coalesce(nome, 'Uma empresa'));
  end if;
end $$;

-- registar um contacto ("liguei, prometeu pagar sexta")
create or replace function public.admin_cobranca_registar(p_empresa uuid, p_nota text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (sou_admin() or (sou_suporte() and exists (select 1 from cobrancas where empresa_id = p_empresa and responsavel = auth.uid()))) then
    raise exception 'Esta empresa não está atribuída a si.' using errcode = 'P0001';
  end if;
  if nullif(trim(p_nota), '') is null then raise exception 'Escreva o que aconteceu.' using errcode = 'P0001'; end if;
  insert into cobrancas_registo (empresa_id, por, nota) values (p_empresa, auth.uid(), left(trim(p_nota), 500));
end $$;

create or replace function public.admin_cobranca_historico(p_empresa uuid)
returns table (criado timestamptz, por text, nota text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (sou_admin() or (sou_suporte() and exists (select 1 from cobrancas where empresa_id = p_empresa and responsavel = auth.uid()))) then
    raise exception 'Esta empresa não está atribuída a si.' using errcode = 'P0001';
  end if;
  return query select r.criado, q.full_name, r.nota from cobrancas_registo r left join perfis q on q.id = r.por
                where r.empresa_id = p_empresa order by r.criado desc limit 30;
end $$;

-- texto do lembrete (o mesmo para a mensagem individual e para o envio a todas)
create or replace function public.texto_lembrete_mensalidade(e perfis)
returns text language plpgsql stable security definer set search_path = public as $$
declare preco text := coalesce(nullif((select valor from config where chave = 'mensalidade_valor'), ''), '100');
        nome text := left(trim(coalesce(e.full_name, '')), 60);   -- empresa: nome completo ("Olá Loja Bom Preço!")
        d int := case when e.assinatura_ate is null then null else floor(extract(epoch from (e.assinatura_ate - now())) / 86400)::int end;
        data text := to_char(e.assinatura_ate, 'DD/MM/YYYY');
begin
  if e.idioma = 'en' then
    return 'Hello' || case when nome <> '' then ' ' || nome else '' end || '! 👋' || chr(10) || chr(10) ||
      case when d is null or d < 0 then 'Your Feira Comercial monthly plan has ended' || case when data is not null then ' (' || data || ')' else '' end || '.'
           else 'Your Feira Comercial monthly plan ends on ' || data || '.' end ||
      ' To keep posting, running ads and Lives, pay ' || preco || ' MT by M-Pesa, e-Mola or bank here: https://www.feira-comercial.com/mensalidade.html' || chr(10) || chr(10) ||
      'If you have already paid, reply to this message and we will confirm it. Thank you! 💛' || chr(10) || 'Feira Comercial Team';
  end if;
  return 'Olá' || case when nome <> '' then ' ' || nome else '' end || '! 👋' || chr(10) || chr(10) ||
    case when d is null or d < 0 then 'A sua mensalidade da Feira Comercial terminou' || case when data is not null then ' (' || data || ')' else '' end || '.'
         when d = 0 then 'A sua mensalidade da Feira Comercial termina hoje.'
         else 'A sua mensalidade da Feira Comercial termina a ' || data || '.' end ||
    ' Para continuar a publicar, fazer anúncios e Lives, pague ' || preco || ' MT por M-Pesa, e-Mola ou banco aqui: https://www.feira-comercial.com/mensalidade.html' || chr(10) || chr(10) ||
    'Se já pagou, responda a esta mensagem e confirmamos. Obrigado! 💛' || chr(10) || 'Equipa Feira Comercial';
end $$;
revoke execute on function public.texto_lembrete_mensalidade(perfis) from public, anon, authenticated;

create or replace function public.admin_texto_lembrete(p_empresa uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare e perfis%rowtype;
begin
  if not (sou_admin() or (sou_suporte() and exists (select 1 from cobrancas where empresa_id = p_empresa and responsavel = auth.uid()))) then
    raise exception 'Esta empresa não está atribuída a si.' using errcode = 'P0001';
  end if;
  select * into e from perfis where id = p_empresa;
  return texto_lembrete_mensalidade(e);
end $$;

-- lembrete pela Equipa Feira Comercial a todas as empresas em atraso (ou a terminar);
-- cada empresa recebe no máximo um lembrete a cada 3 dias
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
                else e.assinatura_ate > now() and e.assinatura_ate <= now() + interval '5 days' end
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
