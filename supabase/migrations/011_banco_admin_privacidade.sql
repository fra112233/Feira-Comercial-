-- ============================================================
-- Feira Comercial — 011: Pagamento por banco, administração,
-- privacidade dos perfis (parte 1), chat privado (parte 1),
-- visualizações únicas e otimizações da base de dados.
--
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
--
-- Esta parte só ACRESCENTA coisas: não quebra o site antigo.
-- A parte 2 (012) fecha os acessos antigos depois de o site novo estar no ar.
-- Pode ser corrido mais de uma vez sem problema.
-- ============================================================

-- 1) Configuração do pagamento por transferência bancária
insert into public.config (chave, valor, descricao) values
  ('banco_nome', 'Standard Bank', 'Banco que recebe as mensalidades'),
  ('banco_nib', '000301050961722101829', 'NIB da conta que recebe as mensalidades'),
  ('banco_titular', 'Feira Comercial', 'Nome do titular da conta bancária')
on conflict (chave) do nothing;

-- 2) Pagamentos: método "banco" e comprovativo
alter table public.pagamentos drop constraint if exists pagamentos_metodo_check;
alter table public.pagamentos add constraint pagamentos_metodo_check
  check (metodo in ('banco', 'mpesa', 'emola'));
alter table public.pagamentos add column if not exists comprovativo text;  -- caminho no bucket "comprovativos"

-- 3) Administração
create or replace function public.sou_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and role = 'admin');
$$;
revoke execute on function public.sou_admin() from public, anon;
grant execute on function public.sou_admin() to authenticated;

-- conta do dono da plataforma
update public.perfis set role = 'admin' where id = 'ede042b6-964f-46fb-a361-0432ef30715e';

drop policy if exists "pagamentos_admin_ver" on public.pagamentos;
create policy "pagamentos_admin_ver" on public.pagamentos for select to authenticated
  using ((select public.sou_admin()));
drop policy if exists "pagamentos_admin_decidir" on public.pagamentos;
create policy "pagamentos_admin_decidir" on public.pagamentos for update to authenticated
  using ((select public.sou_admin())) with check ((select public.sou_admin()));
grant update (estado, nota_admin) on public.pagamentos to authenticated;

drop policy if exists "reclamacoes_admin_ver" on public.reclamacoes;
create policy "reclamacoes_admin_ver" on public.reclamacoes for select to authenticated
  using ((select public.sou_admin()));
drop policy if exists "reclamacoes_admin_responder" on public.reclamacoes;
create policy "reclamacoes_admin_responder" on public.reclamacoes for update to authenticated
  using ((select public.sou_admin())) with check ((select public.sou_admin()));
grant update (estado, resposta) on public.reclamacoes to authenticated;

-- 4) Comprovativos de pagamento (privados: só a empresa e a administração veem)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprovativos', 'comprovativos', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "comprovativos_enviar" on storage.objects;
create policy "comprovativos_enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'comprovativos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "comprovativos_ver" on storage.objects;
create policy "comprovativos_ver" on storage.objects for select to authenticated
  using (bucket_id = 'comprovativos'
         and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.sou_admin())));

-- 5) Perfis: leitura segura
-- Devolve o perfil com os campos que quem pergunta pode ver:
--  • o próprio (e a administração): tudo;
--  • empresas: dados públicos + contactos comerciais (telefone, WhatsApp, e-mail, morada, mapa);
--  • pessoas: só dados públicos (sem celular, e-mail, morada exata nem NUIT).
create or replace function public.perfil_completo(pid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.perfis; r jsonb;
begin
  if auth.uid() is null then return null; end if;
  select * into p from public.perfis where id = pid;
  if not found then return null; end if;
  if p.id = auth.uid() or public.sou_admin() then return to_jsonb(p); end if;

  r := jsonb_build_object(
    'id', p.id, 'username', p.username, 'full_name', p.full_name, 'avatar_url', p.avatar_url,
    'type', p.type, 'sector', p.sector, 'bio', p.bio, 'visibility', p.visibility,
    'created_at', p.created_at, 'gender', p.gender, 'city', p.city, 'province', p.province,
    'website', p.website, 'facebook', p.facebook, 'instagram', p.instagram,
    'opening_hours', p.opening_hours);
  if p.type = 'empresa' then
    r := r || jsonb_build_object('phone', p.phone, 'whatsapp', p.whatsapp, 'email', p.email,
      'morada', p.morada, 'latitude', p.latitude, 'longitude', p.longitude);
  end if;
  return r;
end $$;
revoke execute on function public.perfil_completo(uuid) from public, anon;
grant execute on function public.perfil_completo(uuid) to authenticated;

-- contactos comerciais de várias empresas de uma vez (lista de anúncios)
create or replace function public.contactos_empresas(ids uuid[])
returns table (id uuid, phone text, whatsapp text)
language sql stable security definer set search_path = public as $$
  select p.id, p.phone, p.whatsapp from public.perfis p
   where p.id = any(ids) and p.type = 'empresa' and auth.uid() is not null;
$$;
revoke execute on function public.contactos_empresas(uuid[]) from public, anon;
grant execute on function public.contactos_empresas(uuid[]) to authenticated;

-- 6) Chat: quem recebe um ficheiro pode abri-lo (para o bucket poder ficar privado)
drop policy if exists "chat_media_ver_destinatario" on storage.objects;
create policy "chat_media_ver_destinatario" on storage.objects for select to authenticated
  using (bucket_id = 'chat-media' and exists (
    select 1 from public.messages m
     where m.file_url like '%/chat-media/' || storage.objects.name
       and (m.receiver_id = (select auth.uid()) or m.sender_id = (select auth.uid()))));

-- 7) Visualizações: cada pessoa conta uma só vez por vídeo/anúncio
create table if not exists public.visualizacoes (
  user_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in ('video', 'anuncio')),
  alvo text not null,
  created_at timestamptz not null default now(),
  primary key (tipo, alvo, user_id)
);
alter table public.visualizacoes enable row level security;  -- sem regras: só as funções abaixo escrevem
revoke all on public.visualizacoes from anon, authenticated;

create or replace function public.ver_video(vid bigint)
returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then return; end if;
  insert into public.visualizacoes (user_id, tipo, alvo) values (auth.uid(), 'video', vid::text)
  on conflict do nothing;
  get diagnostics n = row_count;
  if n > 0 then update public.videos set views = views + 1 where id = vid; end if;
end $$;

create or replace function public.ver_anuncio(aid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then return; end if;
  insert into public.visualizacoes (user_id, tipo, alvo) values (auth.uid(), 'anuncio', aid::text)
  on conflict do nothing;
  get diagnostics n = row_count;
  if n > 0 then update public.vagas_anuncios set views = views + 1 where id = aid; end if;
end $$;
revoke execute on function public.ver_video(bigint) from public, anon;
revoke execute on function public.ver_anuncio(uuid) from public, anon;
grant execute on function public.ver_video(bigint) to authenticated;
grant execute on function public.ver_anuncio(uuid) to authenticated;

-- 8) Índices em falta (ligações entre tabelas)
create index if not exists ad_campaigns_user_idx      on public.ad_campaigns (user_id);
create index if not exists bloqueios_blocked_idx      on public.bloqueios (blocked_id);
create index if not exists comments_parent_idx        on public.comments (parent_id);
create index if not exists comments_user_idx          on public.comments (user_id);
create index if not exists followers_following_idx    on public.followers (following_id);
create index if not exists likes_user_idx             on public.likes (user_id);
create index if not exists lives_user_idx             on public.lives (user_id);
create index if not exists messages_reply_to_idx      on public.messages (reply_to);
create index if not exists posts_user_idx             on public.posts (user_id);
create index if not exists stories_user_idx           on public.stories (user_id);
create index if not exists vagas_empresa_idx          on public.vagas_anuncios (empresa_id);
create index if not exists video_comments_user_idx    on public.video_comments (user_id);
create index if not exists video_likes_user_idx       on public.video_likes (user_id);

-- 9) Comentários: uma só regra para apagar (autor do comentário ou dono da publicação)
drop policy if exists "So o dono doo comentario  pode apagar" on public.comments;
drop policy if exists "comments_apagar_dono_post" on public.comments;
drop policy if exists "comments_apagar" on public.comments;
create policy "comments_apagar" on public.comments for delete to authenticated
  using (user_id = (select auth.uid())
         or exists (select 1 from public.posts p where p.id = comments.post_id and p.user_id = (select auth.uid())));
drop policy if exists "auth.uid() = user_id" on public.comments;
drop policy if exists "comments_criar" on public.comments;
create policy "comments_criar" on public.comments for insert to authenticated
  with check (user_id = (select auth.uid()));

-- 10) Regras mais rápidas: auth.uid() avaliado uma vez por consulta, não por linha
do $$
declare r record; q text; c text; sql text;
begin
  for r in select schemaname, tablename, policyname, qual, with_check from pg_policies
           where schemaname = 'public'
             and (qual ~ 'auth\.uid\(\)(?! AS uid)' or with_check ~ 'auth\.uid\(\)(?! AS uid)') loop
    q := regexp_replace(r.qual, 'auth\.uid\(\)(?! AS uid)', '(select auth.uid())', 'g');
    c := regexp_replace(r.with_check, 'auth\.uid\(\)(?! AS uid)', '(select auth.uid())', 'g');
    sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if q is not null then sql := sql || format(' using (%s)', q); end if;
    if c is not null then sql := sql || format(' with check (%s)', c); end if;
    execute sql;
  end loop;
end $$;

-- 11) Visitantes sem sessão não leem tabelas (só podem enviar reclamações)
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('revoke select, update, delete, truncate, references, trigger on public.%I from anon', t.tablename);
  end loop;
end $$;
