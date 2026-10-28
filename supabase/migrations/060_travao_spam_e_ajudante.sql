-- ============================================================
-- Feira Comercial — 060: Travão contra spam + Ajudantes com dois passos
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- 1) TRAVÃO CONTRA SPAM
--    Um robô (ou alguém mal-intencionado) não consegue encher a Feira de
--    publicações ou comentários. Os limites são largos para quem usa normalmente:
--    • Publicações: até 10 por hora e 40 por dia
--    • Comentários (publicações e vídeos): até 10 por minuto e 150 por dia
--    A equipa (administrador, conta oficial, ajudantes) não tem limite.
--
-- 2) AJUDANTES SÓ COM VERIFICAÇÃO EM DOIS PASSOS
--    • Só se pode tornar Ajudante quem já ativou os dois passos.
--    • O Ajudante só consegue usar as ferramentas da equipa se entrou com o código.
--    Assim, se roubarem a palavra-passe de um Ajudante, não chega para entrar.
--    (O administrador continua como estava: com dois passos se os tiver ativos.)
-- ============================================================

-- ---------- 1) Travão contra spam ----------

-- índices para contar depressa "quantas publicações desta pessoa na última hora"
create index if not exists posts_user_criado_idx on public.posts (user_id, created_at desc);
create index if not exists comments_user_criado_idx on public.comments (user_id, created_at desc);
create index if not exists video_comments_user_criado_idx on public.video_comments (user_id, created_at desc);
-- os índices antigos só por pessoa ficam cobertos pelos novos
drop index if exists public.posts_user_idx;
drop index if exists public.comments_user_idx;
drop index if exists public.video_comments_user_idx;

create or replace function public.travao_spam()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  n_curto int; n_dia int;
  max_curto int; max_dia int; janela interval; o_que text;
begin
  if new.user_id is null then return new; end if;
  if exists (select 1 from perfis where id = new.user_id and role in ('admin', 'equipa', 'ajudante')) then
    return new;
  end if;

  if tg_table_name = 'posts' then
    max_curto := 10; janela := interval '1 hour'; max_dia := 40; o_que := 'publicações';
  else
    max_curto := 10; janela := interval '1 minute'; max_dia := 150; o_que := 'comentários';
  end if;

  execute format('select count(*) filter (where created_at > now() - $2), count(*)
                    from %I.%I where user_id = $1 and created_at > now() - interval ''1 day''',
                 tg_table_schema, tg_table_name)
    into n_curto, n_dia using new.user_id, janela;

  if n_curto >= max_curto then
    raise exception 'Fez muitas % seguidas. Aguarde um pouco e tente outra vez.', o_que
      using errcode = 'P0001';
  end if;
  if n_dia >= max_dia then
    raise exception 'Chegou ao limite de % por hoje. Pode continuar amanhã.', o_que
      using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public.travao_spam() from public, anon, authenticated;

-- "ab_" para correr logo a seguir a "aa_valores_ao_criar" (que preenche o autor)
drop trigger if exists ab_travao_spam on public.posts;
create trigger ab_travao_spam before insert on public.posts
  for each row execute function public.travao_spam();
drop trigger if exists ab_travao_spam on public.comments;
create trigger ab_travao_spam before insert on public.comments
  for each row execute function public.travao_spam();
drop trigger if exists ab_travao_spam on public.video_comments;
create trigger ab_travao_spam before insert on public.video_comments
  for each row execute function public.travao_spam();

-- ---------- 2) Ajudantes com dois passos ----------

create or replace function public.sou_suporte()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.perfis p
     where p.id = auth.uid()
       and (
         -- administrador: como antes (código pedido se tiver os dois passos ativos)
         (p.role = 'admin'
           and (coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
                or not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified')))
         -- ajudante: tem sempre de ter entrado com o código
         or (p.role = 'ajudante' and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2')
       ));
$$;
revoke all on function public.sou_suporte() from public, anon;
grant execute on function public.sou_suporte() to authenticated;

create or replace function public.admin_definir_ajudante(p_uid uuid, p_sim boolean)
returns void language plpgsql security definer set search_path = public as $$
declare r text;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  select role into r from perfis where id = p_uid;
  if not found then raise exception 'conta não encontrada'; end if;
  if r in ('admin', 'equipa') then raise exception 'esta conta já é da equipa'; end if;
  if p_sim and not exists (select 1 from auth.mfa_factors f where f.user_id = p_uid and f.status = 'verified') then
    raise exception 'Esta pessoa ainda não ativou a verificação em dois passos. Peça-lhe para ativar em Menu → Privacidade e segurança, e tente outra vez.';
  end if;
  update perfis set role = case when p_sim then 'ajudante' else 'user' end where id = p_uid;
  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
    values (auth.uid(), case when p_sim then 'ajudante_sim' else 'ajudante_nao' end, p_uid, null, null);
end $$;
revoke all on function public.admin_definir_ajudante(uuid, boolean) from public, anon;
grant execute on function public.admin_definir_ajudante(uuid, boolean) to authenticated;

-- Para saber se o ajudante tem de ativar os dois passos (o painel mostra o aviso)
create or replace function public.ajudante_precisa_2passos()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfis where id = auth.uid() and role = 'ajudante')
     and coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2';
$$;
revoke all on function public.ajudante_precisa_2passos() from public, anon;
grant execute on function public.ajudante_precisa_2passos() to authenticated;
