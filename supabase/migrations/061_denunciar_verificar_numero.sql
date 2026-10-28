-- ============================================================
-- Feira Comercial — 061: Denunciar e verificar números de burlões
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- A comunidade ajuda a apanhar burlões:
--  1) DENUNCIAR NÚMERO: quem tem conta pode denunciar um número M-Pesa/telefone
--     que o tentou burlar (dentro ou fora da Feira).
--     • Quando 3 pessoas DIFERENTES o denunciam, o número entra sozinho na lista de
--       números proibidos (aviso vermelho no chat, conta no Radar).
--     • Contra abusos (ex.: loja rival a sujar outra):
--         - só contam contas com 3 dias ou mais e não suspensas;
--         - cada pessoa denuncia o mesmo número uma vez, e no máximo 5 números por dia;
--         - ninguém denuncia o próprio número;
--         - número de uma loja com coroa 👑 ou da equipa NUNCA entra sozinho:
--           a equipa recebe um aviso e decide.
--     • Nunca se mostra quem denunciou.
--  2) VERIFICAR NÚMERO: qualquer pessoa (mesmo sem conta) cola um número e vê:
--     proibido / denunciado / de uma loja verificada / sem denúncias.
--  3) EQUIPA: lista dos números denunciados; "Ignorar" apaga as denúncias
--     (denúncias falsas). Tirar um número da lista proibida também as apaga.
-- ============================================================

create table if not exists public.denuncias_numeros (
  id bigint generated always as identity primary key,
  numero text not null check (numero ~ '^8[2-7][0-9]{7}$'),
  autor uuid not null references public.perfis(id) on delete cascade,
  tipo text not null check (tipo in ('adiantado', 'codigo', 'premio', 'produto', 'falsa_equipa', 'outro')),
  detalhe text check (char_length(detalhe) <= 300),
  criado timestamptz not null default now(),
  unique (numero, autor)
);
alter table public.denuncias_numeros enable row level security;   -- só pelas funções abaixo
revoke all on public.denuncias_numeros from anon, authenticated;
create index if not exists denuncias_numeros_numero_idx on public.denuncias_numeros (numero);
create index if not exists denuncias_numeros_autor_idx on public.denuncias_numeros (autor, criado desc);

-- quem é dono de um número (perfil): para proteger lojas com coroa e a equipa
create or replace function public.dono_do_numero(n text)
returns table (id uuid, nome text, verificada boolean, equipa boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.verificada_em is not null, p.role in ('admin', 'equipa', 'ajudante')
    from perfis p
   where n = any (numeros_em(coalesce(p.phone, '') || ' ' || coalesce(p.whatsapp, '')))
     and coalesce(p.bloqueado, false) = false
   order by (p.verificada_em is not null) desc, (p.role in ('admin', 'equipa', 'ajudante')) desc
   limit 1;
$$;
revoke all on function public.dono_do_numero(text) from public, anon, authenticated;

-- denúncias que contam: pessoas diferentes, contas com 3+ dias, não suspensas
create or replace function public.denuncias_validas(n text)
returns int language sql stable security definer set search_path = public as $$
  select count(distinct d.autor)::int
    from denuncias_numeros d join perfis p on p.id = d.autor
   where d.numero = n and p.created_at < now() - interval '3 days' and coalesce(p.bloqueado, false) = false;
$$;
revoke all on function public.denuncias_validas(text) from public, anon, authenticated;

-- ---------- 1) Denunciar ----------
create or replace function public.denunciar_numero(p_numero text, p_tipo text, p_detalhe text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  eu uuid := auth.uid();
  n text := (numeros_em(p_numero))[1];
  me perfis%rowtype;
  dono record;
  total int;
  oficial uuid;
begin
  if eu is null then raise exception 'Entre na sua conta para denunciar um número.' using errcode = 'P0001'; end if;
  if n is null then raise exception 'Número inválido: use um número de Moçambique (82 a 87 + 7 algarismos).' using errcode = 'P0001'; end if;
  if p_tipo not in ('adiantado', 'codigo', 'premio', 'produto', 'falsa_equipa', 'outro') then
    raise exception 'Escolha o que aconteceu.' using errcode = 'P0001';
  end if;
  select * into me from perfis where id = eu;
  if not found or coalesce(me.bloqueado, false) then raise exception 'A sua conta não pode denunciar números.' using errcode = 'P0001'; end if;
  if n = any (numeros_em(coalesce(me.phone, '') || ' ' || coalesce(me.whatsapp, ''))) then
    raise exception 'Este é o seu próprio número.' using errcode = 'P0001';
  end if;
  if exists (select 1 from denuncias_numeros where numero = n and autor = eu) then
    raise exception 'Já denunciou este número. Obrigado — a sua denúncia está guardada.' using errcode = 'P0001';
  end if;
  if (select count(*) from denuncias_numeros where autor = eu and criado > now() - interval '1 day') >= 5 then
    raise exception 'Já fez 5 denúncias hoje. Pode continuar amanhã.' using errcode = 'P0001';
  end if;

  insert into denuncias_numeros (numero, autor, tipo, detalhe)
  values (n, eu, p_tipo, nullif(left(btrim(coalesce(p_detalhe, '')), 300), ''));

  total := denuncias_validas(n);
  if total >= 3 and not exists (select 1 from numeros_proibidos where numero = n) then
    select * into dono from dono_do_numero(n);
    select id into oficial from perfis where role = 'equipa' limit 1;
    if dono.id is not null and (dono.verificada or dono.equipa) then
      -- loja com coroa / equipa: a equipa decide (aviso uma vez por dia)
      if not exists (select 1 from notificacoes where tipo = 'numero_denunciado' and texto like '%' || n || '%' and criado > now() - interval '1 day') then
        insert into notificacoes (user_id, autor_id, tipo, texto)
        select p.id, oficial, 'numero_denunciado',
               n || ' (' || coalesce(dono.nome, 'loja verificada') || ') tem ' || total || ' denúncias — decida em Números'
          from perfis p where p.role = 'admin';
      end if;
    else
      insert into numeros_proibidos (numero, motivo) values (n, 'Denunciado por ' || total || ' pessoas')
      on conflict (numero) do nothing;
      insert into notificacoes (user_id, autor_id, tipo, texto)
      select p.id, oficial, 'numero_denunciado', n || ' entrou na lista: ' || total || ' denúncias'
        from perfis p where p.role = 'admin';
    end if;
  end if;
  return jsonb_build_object('ok', true, 'numero', n);
end $$;
revoke all on function public.denunciar_numero(text, text, text) from public, anon;
grant execute on function public.denunciar_numero(text, text, text) to authenticated;

-- ---------- 2) Verificar (qualquer pessoa) ----------
create or replace function public.verificar_numero(p_numero text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  n text := (numeros_em(p_numero))[1];
  dono record;
  total int;
  tipos text[];
begin
  if n is null then return jsonb_build_object('estado', 'invalido'); end if;
  total := denuncias_validas(n);
  select array_agg(t order by c desc) into tipos
    from (select tipo t, count(*) c from denuncias_numeros where numero = n group by tipo) s;
  if exists (select 1 from numeros_proibidos where numero = n) then
    return jsonb_build_object('estado', 'proibido', 'numero', n, 'denuncias', total, 'tipos', coalesce(tipos, '{}'));
  end if;
  select * into dono from dono_do_numero(n);
  if dono.id is not null and dono.verificada then
    return jsonb_build_object('estado', 'verificada', 'numero', n, 'loja', dono.nome, 'loja_id', dono.id, 'denuncias', total);
  end if;
  if total > 0 then
    return jsonb_build_object('estado', 'denunciado', 'numero', n, 'denuncias', total, 'tipos', coalesce(tipos, '{}'));
  end if;
  return jsonb_build_object('estado', 'limpo', 'numero', n);
end $$;
revoke all on function public.verificar_numero(text) from public;
grant execute on function public.verificar_numero(text) to anon, authenticated;

-- as minhas denúncias (para a pessoa ver o que já denunciou)
create or replace function public.minhas_denuncias_numeros()
returns table (numero text, tipo text, criado timestamptz, na_lista boolean)
language sql stable security definer set search_path = public as $$
  select d.numero, d.tipo, d.criado, exists (select 1 from numeros_proibidos np where np.numero = d.numero)
    from denuncias_numeros d where d.autor = auth.uid() order by d.criado desc limit 50;
$$;
revoke all on function public.minhas_denuncias_numeros() from public, anon;
grant execute on function public.minhas_denuncias_numeros() to authenticated;

-- ---------- 3) Equipa ----------
create or replace function public.admin_numeros_denunciados()
returns table (numero text, denuncias int, total int, tipos text[], detalhes text[], ultima timestamptz,
               na_lista boolean, dono_id uuid, dono_nome text, dono_verificada boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  select d.numero, denuncias_validas(d.numero), count(*)::int,
         array_agg(distinct d.tipo), (array_agg(d.detalhe order by d.criado desc) filter (where d.detalhe is not null))[1:5],
         max(d.criado), exists (select 1 from numeros_proibidos np where np.numero = d.numero),
         o.id, o.nome, coalesce(o.verificada, false)
    from denuncias_numeros d
    left join lateral dono_do_numero(d.numero) o on true
   group by d.numero, o.id, o.nome, o.verificada
   order by max(d.criado) desc
   limit 200;
end $$;
revoke all on function public.admin_numeros_denunciados() from public, anon;
grant execute on function public.admin_numeros_denunciados() to authenticated;

-- "Ignorar": denúncias falsas → apagadas (fica registado)
create or replace function public.admin_ignorar_denuncias_numero(p_numero text)
returns void language plpgsql security definer set search_path = public as $$
declare n text := (numeros_em(p_numero))[1];
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  delete from denuncias_numeros where numero = n;
  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo) values (auth.uid(), 'numero_ignorado', null, null, n);
end $$;
revoke all on function public.admin_ignorar_denuncias_numero(text) from public, anon;
grant execute on function public.admin_ignorar_denuncias_numero(text) to authenticated;

-- tirar um número da lista também apaga as denúncias (senão voltava a entrar sozinho)
create or replace function public.admin_numero_proibido(p_numero text, p_proibir boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare n text := (numeros_em(p_numero))[1];
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  if n is null then raise exception 'Número inválido: use um número de Moçambique (82 a 87 + 7 algarismos).' using errcode = 'P0001'; end if;
  if p_proibir then
    insert into numeros_proibidos (numero, motivo) values (n, coalesce(nullif(trim(p_motivo), ''), 'Adicionado pela equipa'))
    on conflict (numero) do nothing;
  else
    delete from numeros_proibidos where numero = n;
    delete from denuncias_numeros where numero = n;
  end if;
end $$;

-- novo tipo de aviso no sino
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo = any (array[
  'gosto', 'comentario', 'resposta', 'seguir', 'publicacao', 'video', 'gosto_video', 'comentario_video', 'live',
  'avaliacao', 'resposta_avaliacao', 'convite_aceite', 'convite_premio', 'marco_publicacao', 'marco_seguidor',
  'marco_mensagem', 'gratis_fim', 'mensalidade_fim', 'oferta_guardado', 'oferta_loja', 'resumo_semanal', 'lojas_hoje',
  'travao', 'numero_proibido', 'cobranca', 'gosto_story', 'numero_denunciado']));
