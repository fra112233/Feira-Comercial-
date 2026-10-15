-- ============================================================
-- Feira Comercial — 026: Privacidade e segurança
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Precisa da 022–025. Pode ser corrido mais de uma vez sem problema.
--
-- 1) "Quem me pode enviar mensagens": todos, ou só quem eu sigo.
-- 2) Apagar a conta não apaga os registos de pagamentos (ficam com o nome da
--    empresa, para a contabilidade e os recibos).
-- 3) Verificação em dois passos: se o administrador a ativar, os poderes de
--    administrador só funcionam depois de confirmar o código.
-- 4) "Descarregar os meus dados": tudo o que é meu num só ficheiro.
-- ============================================================

-- ---------- 1) Quem me pode enviar mensagens ----------
alter table public.perfis add column if not exists mensagens_de text not null default 'todos';
alter table public.perfis drop constraint if exists perfis_mensagens_de_check;
alter table public.perfis add constraint perfis_mensagens_de_check check (mensagens_de in ('todos', 'seguidos'));
grant update (mensagens_de) on public.perfis to authenticated;

create or replace function public.pode_receber_mensagem(dest uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select mensagens_de from perfis where id = dest), 'todos') = 'todos'
      or exists (select 1 from perfis where id in (dest, auth.uid()) and role in ('admin', 'equipa'))   -- a equipa fala sempre
      or exists (select 1 from followers where follower_id = dest and following_id = auth.uid())       -- sigo-o
      or exists (select 1 from messages where sender_id = dest and receiver_id = auth.uid());          -- já me escreveu
$$;
revoke all on function public.pode_receber_mensagem(uuid) from public, anon;
grant execute on function public.pode_receber_mensagem(uuid) to authenticated;

drop policy if exists mensagens_enviar on public.messages;
create policy mensagens_enviar on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid()) and receiver_id is not null and receiver_id <> (select auth.uid())
    and not exists (select 1 from bloqueios b where b.blocker_id = messages.receiver_id and b.blocked_id = (select auth.uid()))
    and public.pode_receber_mensagem(receiver_id)
  );

-- ---------- 2) Pagamentos sobrevivem à eliminação da conta ----------
alter table public.pagamentos add column if not exists empresa_nome text;
alter table public.pagamentos add column if not exists empresa_nuit text;
alter table public.pagamentos alter column empresa_id drop not null;
alter table public.pagamentos drop constraint if exists pagamentos_empresa_id_fkey;
alter table public.pagamentos add constraint pagamentos_empresa_id_fkey
  foreign key (empresa_id) references public.perfis(id) on delete set null;

create or replace function public.guardar_pagamentos_ao_apagar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update pagamentos set empresa_nome = coalesce(empresa_nome, old.full_name), empresa_nuit = coalesce(empresa_nuit, old.nuit)
   where empresa_id = old.id;
  return old;
end $$;
revoke all on function public.guardar_pagamentos_ao_apagar() from public, anon, authenticated;
drop trigger if exists trg_guardar_pagamentos on public.perfis;
create trigger trg_guardar_pagamentos before delete on public.perfis for each row execute function public.guardar_pagamentos_ao_apagar();

-- ---------- 3) Administrador com verificação em dois passos ----------
create or replace function public.sou_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and role = 'admin')
     and (coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
          or not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified'));
$$;

-- ---------- 4) Descarregar os meus dados ----------
create or replace function public.exportar_meus_dados()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare eu uuid := auth.uid();
begin
  if eu is null then return null; end if;
  return jsonb_build_object(
    'exportado_em', now(),
    'perfil', (select to_jsonb(p) - 'role' from perfis p where p.id = eu),
    'publicacoes', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]') from posts x where x.user_id = eu),
    'comentarios', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]') from comments x where x.user_id = eu),
    'gostos', (select coalesce(jsonb_agg(jsonb_build_object('post_id', x.post_id, 'reacao', x.reaction, 'em', x.created_at)), '[]') from likes x where x.user_id = eu),
    'mensagens', (select coalesce(jsonb_agg(jsonb_build_object('em', x.created_at, 'de', x.sender_id, 'para', x.receiver_id, 'texto', x.content, 'ficheiro', x.file_url) order by x.created_at), '[]')
                    from messages x where (x.sender_id = eu or x.receiver_id = eu) and not coalesce(x.deleted, false)),
    'sigo', (select coalesce(jsonb_agg(x.following_id), '[]') from followers x where x.follower_id = eu),
    'seguidores', (select count(*) from followers x where x.following_id = eu),
    'videos', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from videos x where x.user_id = eu),
    'stories', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from stories x where x.user_id = eu),
    'anuncios', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from vagas_anuncios x where x.empresa_id = eu),
    'produtos', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from produtos x where x.user_id = eu),
    'avaliacoes_que_fiz', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from avaliacoes x where x.user_id = eu),
    'avaliacoes_recebidas', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from avaliacoes x where x.empresa_id = eu),
    'guardados', (select coalesce(jsonb_agg(x.post_id), '[]') from guardados x where x.user_id = eu),
    'pagamentos', (select coalesce(jsonb_agg(to_jsonb(x) - 'nota_admin' order by x.created_at), '[]') from pagamentos x where x.empresa_id = eu),
    'reclamacoes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from reclamacoes x where x.user_id = eu),
    'bloqueios', (select coalesce(jsonb_agg(x.blocked_id), '[]') from bloqueios x where x.blocker_id = eu)
  );
end $$;
revoke all on function public.exportar_meus_dados() from public, anon;
grant execute on function public.exportar_meus_dados() to authenticated;
