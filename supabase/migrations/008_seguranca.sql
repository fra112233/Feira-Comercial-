-- ============================================================
-- Feira Comercial — 008: correções de segurança e de limites
-- (encontradas na análise das regras da base de dados)
-- Correr UMA vez no Supabase: SQL Editor → New query → colar → Run
-- Pode ser corrido mais de uma vez sem problema.
-- ============================================================

-- 1) PERFIS: o utilizador não pode dar-se o papel de "admin" nem trocar o e-mail
--    mostrado no perfil (o e-mail verdadeiro é o da conta). O tipo já estava protegido.
create or replace function public.bloquear_mudanca_tipo()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    new.type  := old.type;
    new.role  := old.role;
    new.email := old.email;
    new.id    := old.id;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end $$;

-- 2) PUBLICAÇÕES: só quem tem sessão iniciada as vê (como os perfis)
drop policy if exists "Enable read access for all users" on public.posts;
drop policy if exists "Qualquer um pode ver posts" on public.posts;
drop policy if exists "posts_ver" on public.posts;
create policy "posts_ver" on public.posts for select to authenticated using (true);

-- 3) PUBLICAÇÕES: os contadores de gostos/comentários não podem ser falsificados
create or replace function public.proteger_post()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.curtidas_count    := old.curtidas_count;
    new.comentarios_count := old.comentarios_count;
    new.user_id    := old.user_id;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;
drop trigger if exists posts_proteger on public.posts;
create trigger posts_proteger before update on public.posts
  for each row execute function public.proteger_post();

-- 4) PUBLICAÇÕES: nada de publicações vazias nem textos gigantes (máx. 5000 caracteres)
alter table public.posts drop constraint if exists posts_conteudo_check;
alter table public.posts add constraint posts_conteudo_check check (
  char_length(coalesce(content, '')) <= 5000
  and (coalesce(btrim(content), '') <> '' or jsonb_array_length(coalesce(media, '[]'::jsonb)) > 0 or image_url is not null)
);

-- 5) REAÇÕES: só as 5 reações do site
alter table public.likes drop constraint if exists likes_reacao_check;
alter table public.likes add constraint likes_reacao_check
  check (reaction in ('Curtir', 'Amei', 'Haha', 'Triste', 'Uau'));

-- 6) COMENTÁRIOS: sem comentários vazios (máx. 2000 caracteres)
alter table public.comments drop constraint if exists comments_conteudo_check;
alter table public.comments add constraint comments_conteudo_check
  check (coalesce(btrim(content), '') <> '' and char_length(content) <= 2000);

-- 7) COMENTÁRIOS: o dono da publicação pode apagar comentários na sua publicação
drop policy if exists "comments_apagar_dono_post" on public.comments;
create policy "comments_apagar_dono_post" on public.comments for delete to authenticated
  using (exists (select 1 from public.posts p where p.id = comments.post_id and p.user_id = (select auth.uid())));

-- 8) MENSAGENS: sem mensagens vazias (texto, ficheiro ou apagada) e máx. 5000 caracteres
alter table public.messages drop constraint if exists messages_conteudo_check;
alter table public.messages add constraint messages_conteudo_check check (
  char_length(coalesce(content, '')) <= 5000
  and (deleted or coalesce(btrim(content), '') <> '' or file_url is not null)
);

-- 9) ANÚNCIOS: a empresa não pode falsificar as visualizações
create or replace function public.proteger_anuncio()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.views := old.views;
    new.empresa_id := old.empresa_id;
    new.data_publicacao := old.data_publicacao;
  end if;
  return new;
end $$;
drop trigger if exists anuncios_proteger on public.vagas_anuncios;
create trigger anuncios_proteger before update on public.vagas_anuncios
  for each row execute function public.proteger_anuncio();

-- 10) APAGAR CONTA: havia uma ligação antiga dos anúncios à conta (auth.users) sem
--     "apagar em cascata", que impedia apagar uma empresa com anúncios.
--     Fica só a ligação ao perfil, que já apaga os anúncios junto com a conta.
alter table public.vagas_anuncios drop constraint if exists vagas_anuncios_empresa_id_fkey;
