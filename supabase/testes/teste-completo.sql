-- Teste completo da base de dados da Feira Comercial.
-- Correr no Supabase → SQL Editor DEPOIS das migrações 007 e 008.
-- O resultado aparece como um "erro" vermelho que começa por RELATORIO: é de propósito,
-- porque o erro anula tudo e nada fica gravado.
-- Cria 3 contas (Ana = pessoa, Loja = empresa, Carlos = pessoa "intruso"),
-- testa cada funcionalidade e cada regra, e no fim ANULA TUDO (raise exception).
create temp table r (n serial, area text, teste text, ok boolean, detalhe text) on commit drop;
grant all on r to anon, authenticated; grant usage on sequence r_n_seq to anon, authenticated;

create function pg_temp.t(area text, teste text, uid uuid, sql text, espera text) returns void language plpgsql as $f$
declare n bigint; v text; err text; passou boolean; det text;
begin
  perform set_config('request.jwt.claims',
    case when uid is null then '{"role":"anon"}' else json_build_object('sub', uid, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), true);
  execute 'set local role ' || case when uid is null then 'anon' else 'authenticated' end;
  begin
    if espera like 'v=%' then
      execute sql into v; n := 1;
    elsif espera like 'n=%' then
      execute 'select count(*) from (' || sql || ') x' into n;
    else
      execute sql; get diagnostics n = row_count;
    end if;
  exception when others then err := sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  if espera = 'ok' then passou := err is null and n >= 1; det := coalesce('ERRO: ' || err, n || ' linha(s)');
  elsif espera = 'bloqueado' then passou := err is not null or n = 0; det := coalesce('recusado: ' || err, n || ' linha(s) alteradas');
  elsif espera like 'n=%' then passou := err is null and n = substr(espera, 3)::bigint; det := coalesce('ERRO: ' || err, 'contou ' || n || ', esperado ' || substr(espera, 3));
  elsif espera like 'v=%' then passou := err is null and v is not distinct from substr(espera, 3); det := coalesce('ERRO: ' || err, 'valor "' || coalesce(v, 'null') || '", esperado "' || substr(espera, 3) || '"');
  end if;
  insert into r(area, teste, ok, detalhe) values (area, teste, passou, det);
end $f$;

do $do$
declare
  ana uuid := gen_random_uuid(); loja uuid := gen_random_uuid(); carlos uuid := gen_random_uuid();
  pid bigint; pid2 bigint; cid bigint; mid bigint; vid bigint; vcid bigint; aid uuid; story bigint; relat text; i int; tinha_reclam boolean;
begin
  -- ── 0. Livro de reclamações: se a tabela ainda não existe, cria-a só para este teste ──
  tinha_reclam := to_regclass('public.reclamacoes') is not null;
  if not tinha_reclam then
    create table public.reclamacoes (
      id bigint generated always as identity primary key,
      user_id uuid default auth.uid() references public.perfis(id) on delete set null,
      nome text not null check (char_length(btrim(nome)) between 2 and 120),
      email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 200),
      telefone text check (telefone is null or char_length(telefone) <= 30),
      tipo text not null default 'sugestao' check (tipo in ('sugestao','reclamacao','problema','denuncia','elogio')),
      assunto text not null check (char_length(btrim(assunto)) between 3 and 150),
      mensagem text not null check (char_length(btrim(mensagem)) between 10 and 4000),
      link text check (link is null or char_length(link) <= 500),
      estado text not null default 'recebida' check (estado in ('recebida','em_analise','resolvida','arquivada')),
      resposta text, respondido_em timestamptz, created_at timestamptz not null default now());
    alter table public.reclamacoes enable row level security;
    create policy reclamacoes_inserir on public.reclamacoes for insert to anon, authenticated
      with check ((user_id is null or user_id = (select auth.uid())) and estado = 'recebida' and resposta is null and respondido_em is null);
    create policy reclamacoes_ver_proprias on public.reclamacoes for select to authenticated using (user_id = (select auth.uid()));
    create function public.limitar_reclamacoes() returns trigger language plpgsql security definer set search_path = public as $g$
    begin
      if (select count(*) from public.reclamacoes where created_at > now() - interval '1 hour'
          and (lower(email) = lower(new.email) or (new.user_id is not null and user_id = new.user_id))) >= 5 then
        raise exception 'Demasiados pedidos seguidos. Tente novamente daqui a uma hora.';
      end if;
      new.email := lower(btrim(new.email)); new.nome := btrim(new.nome); return new;
    end $g$;
    create trigger limitar_reclamacoes before insert on public.reclamacoes for each row execute function public.limitar_reclamacoes();
    create function public.marcar_resposta() returns trigger language plpgsql set search_path = public as $g$
    begin
      if new.resposta is distinct from old.resposta and new.resposta is not null then new.respondido_em := now(); end if; return new;
    end $g$;
    create trigger marcar_resposta before update on public.reclamacoes for each row execute function public.marcar_resposta();
    grant insert on public.reclamacoes to anon, authenticated; grant select on public.reclamacoes to authenticated;
  end if;

  -- ── 1. Registo (como o Formulário faz: signUp com os dados no "metadata") ──
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
   ('00000000-0000-0000-0000-000000000000', ana, 'authenticated', 'authenticated', 'ana.teste@exemplo.co.mz', extensions.crypt('Teste1234', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Ana Teste","type":"singular","gender":"feminino","phone":"+258841111111","morada":"Av. Julius Nyerere 100","province":"Maputo Cidade","city":"Maputo"}', now(), now()),
   ('00000000-0000-0000-0000-000000000000', loja, 'authenticated', 'authenticated', 'loja.teste@exemplo.co.mz', extensions.crypt('Teste1234', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Loja Teste Lda","type":"empresa","phone":"+258842222222","whatsapp":"+258842222222","website":"https://loja.exemplo.co.mz","morada":"Rua da Sé 5","province":"Maputo Cidade","city":"Maputo","sector":"Comércio","nuit":"400123456","bio":"Loja de teste","latitude":"-25.9692","longitude":"32.5732","opening_hours":{"seg":{"abre":"08:00","fecha":"17:00"}}}', now(), now()),
   ('00000000-0000-0000-0000-000000000000', carlos, 'authenticated', 'authenticated', 'carlos.teste@exemplo.co.mz', extensions.crypt('Teste1234', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{"full_name":"Carlos Intruso","type":"singular"}', now(), now());

  perform pg_temp.t('Registo','Conta pessoal criada com género, celular, morada, província', ana,
    format('select type||''|''||gender||''|''||phone||''|''||morada||''|''||province from perfis where id=%L', ana), 'v=singular|feminino|+258841111111|Av. Julius Nyerere 100|Maputo Cidade');
  perform pg_temp.t('Registo','Conta empresa criada com NUIT, WhatsApp, setor, site, mapa e horário', loja,
    format('select type||''|''||nuit||''|''||whatsapp||''|''||sector||''|''||website||''|''||round(latitude::numeric,2)||''|''||(opening_hours->''seg''->>''abre'') from perfis where id=%L', loja),
    'v=empresa|400123456|+258842222222|Comércio|https://loja.exemplo.co.mz|-25.97|08:00');
  perform pg_temp.t('Registo','Nome de utilizador gerado automaticamente', ana, format('select (username like ''ana.teste_%%'')::text from perfis where id=%L', ana), 'v=true');

  -- ── 2. Perfis ──
  perform pg_temp.t('Perfis','Sem sessão NÃO se vê nenhum perfil', null, 'select id from perfis', 'n=0');
  perform pg_temp.t('Perfis','Com sessão vê o perfil da empresa', ana, format('select id from perfis where id=%L', loja), 'n=1');
  perform pg_temp.t('Perfis','Editar o próprio perfil (bio)', ana, format('update perfis set bio=''Olá!'' where id=%L', ana), 'ok');
  perform pg_temp.t('Perfis','NÃO edita o perfil de outra pessoa', carlos, format('update perfis set bio=''hackeado'' where id=%L', ana), 'bloqueado');
  perform pg_temp.t('Perfis','Pessoa tenta passar a empresa (update)', ana, format('update perfis set type=''empresa'' where id=%L', ana), 'ok');
  perform pg_temp.t('Perfis','… e o tipo continua "singular"', ana, format('select type from perfis where id=%L', ana), 'v=singular');
  perform pg_temp.t('Perfis','Esconder perfil da pesquisa (visibility=privado)', ana, format('update perfis set visibility=''privado'' where id=%L', ana), 'ok');
  perform pg_temp.t('Perfis','NÃO cria perfil falso com outro id', carlos, format('insert into perfis(id,username) values (%L,''falso'')', gen_random_uuid()), 'bloqueado');
  perform pg_temp.t('Perfis','NÃO apaga o perfil (só apagando a conta)', ana, format('delete from perfis where id=%L', ana), 'bloqueado');
  perform pg_temp.t('Perfis','Tenta dar-se o papel de admin e trocar o e-mail do perfil', ana, format('update perfis set role=''admin'', email=''presidente@gov.mz'' where id=%L', ana), 'ok');
  perform pg_temp.t('Perfis','… papel e e-mail NÃO mudam', ana, format('select role||''|''||email from perfis where id=%L', ana), 'v=user|ana.teste@exemplo.co.mz');

  -- ── 3. Publicações ──
  perform pg_temp.t('Publicações','Pessoa publica no feed', ana, format('insert into posts(user_id,content,media) values (%L,''Primeira publicação'',''[{"url":"https://x/a.jpg","type":"image"}]'')', ana), 'ok');
  select max(id) into pid from posts where user_id = ana;
  perform pg_temp.t('Publicações','Empresa publica no feed', loja, format('insert into posts(user_id,content) values (%L,''Promoção!'')', loja), 'ok');
  select max(id) into pid2 from posts where user_id = loja;
  perform pg_temp.t('Publicações','NÃO publica em nome de outra pessoa', carlos, format('insert into posts(user_id,content) values (%L,''falso'')', ana), 'bloqueado');
  perform pg_temp.t('Publicações','Sem sessão NÃO deve ler publicações (perfis estão protegidos)', null, format('select id from posts where id=%L', pid), 'n=0');
  perform pg_temp.t('Publicações','NÃO edita publicação de outro', carlos, format('update posts set content=''x'' where id=%L', pid), 'bloqueado');
  perform pg_temp.t('Publicações','NÃO apaga publicação de outro', carlos, format('delete from posts where id=%L', pid), 'bloqueado');
  perform pg_temp.t('Publicações','NÃO deve aceitar publicação vazia (sem texto nem foto)', ana, format('insert into posts(user_id,content,media) values (%L,null,''[]'')', ana), 'bloqueado');
  perform pg_temp.t('Publicações','NÃO deve aceitar texto gigante (100 000 caracteres)', ana, format('insert into posts(user_id,content) values (%L,repeat(''a'',100000))', ana), 'bloqueado');

  -- ── 4. Reações e comentários ──
  perform pg_temp.t('Reações','Dar gosto', loja, format('insert into likes(post_id,user_id,reaction) values (%s,%L,''Amei'')', pid, loja), 'ok');
  perform pg_temp.t('Reações','Contador de gostos atualiza sozinho', ana, format('select curtidas_count::text from posts where id=%s', pid), 'v=1');
  perform pg_temp.t('Reações','NÃO dá dois gostos na mesma publicação', loja, format('insert into likes(post_id,user_id) values (%s,%L)', pid, loja), 'bloqueado');
  perform pg_temp.t('Reações','Mudar a reação (Amei → Haha)', loja, format('update likes set reaction=''Haha'' where post_id=%s and user_id=%L', pid, loja), 'ok');
  perform pg_temp.t('Reações','NÃO muda a reação de outro', carlos, format('update likes set reaction=''Triste'' where post_id=%s', pid), 'bloqueado');
  perform pg_temp.t('Reações','NÃO deve aceitar reação inventada', loja, format('update likes set reaction=''<script>'' where post_id=%s and user_id=%L', pid, loja), 'bloqueado');
  update likes set reaction = 'Haha' where post_id = pid and user_id = loja;
  perform pg_temp.t('Reações','Gosto falso em nome de outro', carlos, format('insert into likes(post_id,user_id) values (%s,%L)', pid, ana), 'bloqueado');
  perform pg_temp.t('Reações','Dono tenta falsificar o contador de gostos', ana, format('update posts set curtidas_count=9999 where id=%s', pid), 'ok');
  perform pg_temp.t('Reações','… o contador NÃO muda', ana, format('select curtidas_count::text from posts where id=%s', pid), 'v=1');

  perform pg_temp.t('Comentários','Comentar', loja, format('insert into comments(post_id,user_id,content) values (%s,%L,''Muito bom'')', pid, loja), 'ok');
  select max(id) into cid from comments where post_id = pid;
  perform pg_temp.t('Comentários','Responder a um comentário', ana, format('insert into comments(post_id,user_id,content,parent_id) values (%s,%L,''Obrigada'',%s)', pid, ana, cid), 'ok');
  perform pg_temp.t('Comentários','Contador de comentários = 2', ana, format('select comentarios_count::text from posts where id=%s', pid), 'v=2');
  perform pg_temp.t('Comentários','NÃO comenta em nome de outro', carlos, format('insert into comments(post_id,user_id,content) values (%s,%L,''x'')', pid, loja), 'bloqueado');
  perform pg_temp.t('Comentários','NÃO apaga comentário de outro', carlos, format('delete from comments where id=%s', cid), 'bloqueado');
  perform pg_temp.t('Comentários','Dono da publicação pode apagar comentários ofensivos na sua publicação', ana, format('delete from comments where id=%s', cid), 'ok');
  perform pg_temp.t('Comentários','NÃO deve aceitar comentário vazio', loja, format('insert into comments(post_id,user_id,content) values (%s,%L,''   '')', pid, loja), 'bloqueado');
  perform pg_temp.t('Comentários','Sem sessão NÃO comenta', null, format('insert into comments(post_id,content) values (%s,''anon'')', pid), 'bloqueado');

  -- ── 5. Stories ──
  perform pg_temp.t('Stories','Publicar story', ana, format('insert into stories(user_id,media_url) values (%L,''https://x/s.jpg'')', ana), 'ok');
  select max(id) into story from stories where user_id = ana;
  perform pg_temp.t('Stories','Outros veem o story', carlos, format('select id from stories where id=%s', story), 'n=1');
  perform pg_temp.t('Stories','Sem sessão NÃO vê stories', null, 'select id from stories', 'n=0');
  perform pg_temp.t('Stories','NÃO publica story em nome de outro', carlos, format('insert into stories(user_id,media_url) values (%L,''x'')', ana), 'bloqueado');
  perform pg_temp.t('Stories','NÃO apaga story de outro', carlos, format('delete from stories where id=%s', story), 'bloqueado');
  perform pg_temp.t('Stories','Responder ao story por mensagem (com a referência da foto)', loja,
    format('insert into messages(sender_id,receiver_id,content,ref) values (%L,%L,''Que bonito!'',''{"tipo":"story","id":%s}'')', loja, ana, story), 'ok');

  -- ── 6. Seguidores ──
  perform pg_temp.t('Seguidores','Seguir a empresa', ana, format('insert into followers(follower_id,following_id,created_at) values (%L,%L,1)', ana, loja), 'ok');
  perform pg_temp.t('Seguidores','NÃO segue duas vezes', ana, format('insert into followers(follower_id,following_id) values (%L,%L)', ana, loja), 'bloqueado');
  perform pg_temp.t('Seguidores','NÃO segue a si próprio', ana, format('insert into followers(follower_id,following_id) values (%L,%L)', ana, ana), 'bloqueado');
  perform pg_temp.t('Seguidores','NÃO põe outra pessoa a seguir alguém', carlos, format('insert into followers(follower_id,following_id) values (%L,%L)', ana, carlos), 'bloqueado');
  perform pg_temp.t('Seguidores','Contar seguidores da empresa', carlos, format('select id from followers where following_id=%L', loja), 'n=1');
  perform pg_temp.t('Seguidores','NÃO desfaz o "seguir" de outro', carlos, format('delete from followers where follower_id=%L', ana), 'bloqueado');
  perform pg_temp.t('Seguidores','Deixar de seguir', ana, format('delete from followers where follower_id=%L and following_id=%L', ana, loja), 'ok');

  -- ── 7. Mensagens ──
  perform pg_temp.t('Mensagens','Enviar mensagem de texto', ana, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,''Olá, tem stock?'')', ana, loja), 'ok');
  select max(id) into mid from messages where sender_id = ana;
  perform pg_temp.t('Mensagens','Enviar foto (ficheiro)', ana, format('insert into messages(sender_id,receiver_id,content,file_url,media_type,file_name) values (%L,%L,'''',''https://x/f.jpg'',''image'',''f.jpg'')', ana, loja), 'ok');
  perform pg_temp.t('Mensagens','NÃO envia mensagem a si próprio', ana, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,''eu'')', ana, ana), 'bloqueado');
  perform pg_temp.t('Mensagens','NÃO envia em nome de outro', carlos, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,''falso'')', ana, loja), 'bloqueado');
  perform pg_temp.t('Mensagens','Destinatário vê a mensagem', loja, format('select id from messages where id=%s', mid), 'n=1');
  perform pg_temp.t('Mensagens','Terceiro NÃO lê a conversa dos outros', carlos, format('select id from messages where sender_id in (%L,%L)', ana, loja), 'n=0');
  perform pg_temp.t('Mensagens','Sem sessão NÃO lê mensagens', null, 'select id from messages', 'n=0');
  perform pg_temp.t('Mensagens','Destinatário marca como lida', loja, format('update messages set read_at=now() where id=%s', mid), 'ok');
  perform pg_temp.t('Mensagens','… fica marcada como lida', ana, format('select (read_at is not null)::text from messages where id=%s', mid), 'v=true');
  perform pg_temp.t('Mensagens','Destinatário tenta mudar o texto', loja, format('update messages set content=''alterado'' where id=%s', mid), 'ok');
  perform pg_temp.t('Mensagens','… e o texto NÃO muda', ana, format('select content from messages where id=%s', mid), 'v=Olá, tem stock?');
  perform pg_temp.t('Mensagens','Reagir a uma mensagem', loja, format('update messages set reaction=''❤️'' where id=%s', mid), 'ok');
  perform pg_temp.t('Mensagens','Responder citando a mensagem', loja, format('insert into messages(sender_id,receiver_id,content,reply_to) values (%L,%L,''Sim, temos'',%s)', loja, ana, mid), 'ok');
  perform pg_temp.t('Mensagens','Terceiro NÃO mexe na mensagem', carlos, format('update messages set reaction=''x'' where id=%s', mid), 'bloqueado');
  perform pg_temp.t('Mensagens','Destinatário NÃO apaga para todos', loja, format('update messages set deleted=true where id=%s', mid), 'ok');
  perform pg_temp.t('Mensagens','… a mensagem continua lá', ana, format('select deleted::text from messages where id=%s', mid), 'v=false');
  perform pg_temp.t('Mensagens','Remetente apaga para todos', ana, format('update messages set deleted=true where id=%s', mid), 'ok');
  perform pg_temp.t('Mensagens','… o texto desaparece mesmo da base de dados', loja, format('select content from messages where id=%s', mid), 'v=');
  perform pg_temp.t('Mensagens','Limpar conversa só para mim', loja, format('update messages set cleared_by_receiver=true where receiver_id=%L', loja), 'ok');
  perform pg_temp.t('Mensagens','NÃO deve aceitar mensagem vazia (sem texto nem ficheiro)', ana, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,null)', ana, loja), 'bloqueado');

  perform pg_temp.t('Bloqueios','Empresa bloqueia a Ana', loja, format('insert into bloqueios(blocker_id,blocked_id) values (%L,%L)', loja, ana), 'ok');
  perform pg_temp.t('Bloqueios','Ana bloqueada NÃO consegue enviar mensagem', ana, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,''olá?'')', ana, loja), 'bloqueado');
  perform pg_temp.t('Bloqueios','Terceiro NÃO vê quem bloqueou quem', carlos, 'select 1 from bloqueios', 'n=0');
  perform pg_temp.t('Bloqueios','NÃO bloqueia a si próprio', ana, format('insert into bloqueios(blocker_id,blocked_id) values (%L,%L)', ana, ana), 'bloqueado');
  perform pg_temp.t('Bloqueios','NÃO desbloqueia em nome de outro', ana, format('delete from bloqueios where blocker_id=%L', loja), 'bloqueado');
  perform pg_temp.t('Bloqueios','Desbloquear', loja, format('delete from bloqueios where blocker_id=%L and blocked_id=%L', loja, ana), 'ok');
  perform pg_temp.t('Bloqueios','Depois de desbloquear, a Ana já envia', ana, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,''obrigada'')', ana, loja), 'ok');

  -- ── 8. Anúncios (só empresas) ──
  perform pg_temp.t('Anúncios','Pessoa NÃO publica anúncio', ana, format('insert into vagas_anuncios(empresa_id,titulo,descricao) values (%L,''Vendo'',''x'')', ana), 'bloqueado');
  perform pg_temp.t('Anúncios','Empresa publica promoção', loja, format('insert into vagas_anuncios(empresa_id,titulo,descricao,tipo,preco,validade) values (%L,''Saldos'',''Tudo a 50%%'',''promo'',''500 MT'',current_date+7)', loja), 'ok');
  select id into aid from vagas_anuncios where empresa_id = loja limit 1;
  perform pg_temp.t('Anúncios','Empresa publica vaga de emprego', loja, format('insert into vagas_anuncios(empresa_id,titulo,descricao,tipo) values (%L,''Vendedor'',''Precisa-se'',''vaga'')', loja), 'ok');
  perform pg_temp.t('Anúncios','Empresa publica serviço', loja, format('insert into vagas_anuncios(empresa_id,titulo,descricao,tipo) values (%L,''Entregas'',''Ao domicílio'',''servico'')', loja), 'ok');
  perform pg_temp.t('Anúncios','NÃO aceita tipo inventado', loja, format('insert into vagas_anuncios(empresa_id,titulo,descricao,tipo) values (%L,''x'',''x'',''spam'')', loja), 'bloqueado');
  perform pg_temp.t('Anúncios','Empresa NÃO publica em nome de outra', loja, format('insert into vagas_anuncios(empresa_id,titulo,descricao) values (%L,''x'',''x'')', carlos), 'bloqueado');
  perform pg_temp.t('Anúncios','Pessoas veem os anúncios ativos', ana, format('select id from vagas_anuncios where empresa_id=%L', loja), 'n=3');
  perform pg_temp.t('Anúncios','Contar visualização', ana, format('select ver_anuncio(%L)::text', aid), 'v=');
  perform pg_temp.t('Anúncios','… visualizações = 1', ana, format('select views::text from vagas_anuncios where id=%L', aid), 'v=1');
  perform pg_temp.t('Anúncios','Sem sessão NÃO conta visualizações', null, format('select ver_anuncio(%L)::text', aid), 'bloqueado');
  perform pg_temp.t('Anúncios','Empresa tenta falsificar visualizações', loja, format('update vagas_anuncios set views=99999 where id=%L', aid), 'ok');
  perform pg_temp.t('Anúncios','… as visualizações NÃO mudam', loja, format('select views::text from vagas_anuncios where id=%L', aid), 'v=1');
  perform pg_temp.t('Anúncios','Pausar anúncio', loja, format('update vagas_anuncios set ativo=false where id=%L', aid), 'ok');
  perform pg_temp.t('Anúncios','Anúncio pausado desaparece para os outros', ana, format('select id from vagas_anuncios where id=%L', aid), 'n=0');
  perform pg_temp.t('Anúncios','… mas a empresa continua a vê-lo', loja, format('select id from vagas_anuncios where id=%L', aid), 'n=1');
  perform pg_temp.t('Anúncios','Outro NÃO edita o anúncio', carlos, format('update vagas_anuncios set titulo=''x'' where empresa_id=%L', loja), 'bloqueado');
  perform pg_temp.t('Anúncios','Outro NÃO apaga o anúncio', carlos, format('delete from vagas_anuncios where empresa_id=%L', loja), 'bloqueado');
  perform pg_temp.t('Anúncios','Campanha: pessoa NÃO cria', ana, format('insert into ad_campaigns(user_id,nome) values (%L,''x'')', ana), 'bloqueado');
  perform pg_temp.t('Anúncios','Campanha: empresa cria', loja, format('insert into ad_campaigns(user_id,nome) values (%L,''Natal'')', loja), 'ok');

  -- ── 9. Vídeos curtos ──
  perform pg_temp.t('Vídeos','Pessoa publica vídeo', ana, format('insert into videos(user_id,video_url,caption,duracao) values (%L,''https://x/v.mp4'',''Meu vídeo'',30)', ana), 'ok');
  select max(id) into vid from videos where user_id = ana;
  perform pg_temp.t('Vídeos','Gostar do vídeo', loja, format('insert into video_likes(video_id,user_id) values (%s,%L)', vid, loja), 'ok');
  perform pg_temp.t('Vídeos','NÃO gosta duas vezes do mesmo vídeo', loja, format('insert into video_likes(video_id,user_id) values (%s,%L)', vid, loja), 'bloqueado');
  delete from video_likes where video_id = vid and user_id = loja and ctid not in (select min(ctid) from video_likes where video_id = vid and user_id = loja);
  update videos set likes_count = (select count(*) from video_likes where video_id = vid) where id = vid;
  perform pg_temp.t('Vídeos','Contador de gostos = 1', ana, format('select likes_count::text from videos where id=%s', vid), 'v=1');
  perform pg_temp.t('Vídeos','Comentar vídeo', loja, format('insert into video_comments(video_id,user_id,content) values (%s,%L,''Top'')', vid, loja), 'ok');
  select max(id) into vcid from video_comments where video_id = vid;
  perform pg_temp.t('Vídeos','NÃO aceita comentário vazio', loja, format('insert into video_comments(video_id,user_id,content) values (%s,%L,'''')', vid, loja), 'bloqueado');
  perform pg_temp.t('Vídeos','NÃO aceita comentário com mais de 1000 letras', loja, format('insert into video_comments(video_id,user_id,content) values (%s,%L,repeat(''a'',1001))', vid, loja), 'bloqueado');
  perform pg_temp.t('Vídeos','Terceiro NÃO apaga o comentário', carlos, format('delete from video_comments where id=%s', vcid), 'bloqueado');
  perform pg_temp.t('Vídeos','Dono do vídeo apaga comentário', ana, format('delete from video_comments where id=%s', vcid), 'ok');
  perform pg_temp.t('Vídeos','Dono tenta falsificar gostos', ana, format('update videos set likes_count=9999, views=9999 where id=%s', vid), 'ok');
  perform pg_temp.t('Vídeos','… e os números NÃO mudam', ana, format('select likes_count||''/''||views from videos where id=%s', vid), 'v=1/0');
  perform pg_temp.t('Vídeos','Contar visualização', carlos, format('select ver_video(%s)::text', vid), 'v=');
  perform pg_temp.t('Vídeos','Outro NÃO muda a legenda', carlos, format('update videos set caption=''x'' where id=%s', vid), 'bloqueado');
  perform pg_temp.t('Vídeos','Outro NÃO apaga o vídeo', carlos, format('delete from videos where id=%s', vid), 'bloqueado');

  -- ── 10. Reclamações ──
  perform pg_temp.t('Reclamações','Sem conta: enviar sugestão', null, 'insert into reclamacoes(nome,email,tipo,assunto,mensagem) values (''Visitante'',''Visit@Gmail.com'',''sugestao'',''Ideia'',''Gostava de ver mais lojas'')', 'ok');
  perform pg_temp.t('Reclamações','Sem conta NÃO lê pedidos', null, 'select id from reclamacoes', 'bloqueado');
  perform pg_temp.t('Reclamações','Sem conta NÃO finge ser outra pessoa', null, format('insert into reclamacoes(user_id,nome,email,assunto,mensagem) values (%L,''x'',''a@b.co'',''abc'',''0123456789'')', ana), 'bloqueado');
  perform pg_temp.t('Reclamações','Com conta: enviar denúncia', ana, format('insert into reclamacoes(user_id,nome,email,tipo,assunto,mensagem,link) values (%L,''Ana'',''ana.teste@exemplo.co.mz'',''denuncia'',''Perfil falso'',''Esta conta é falsa e engana pessoas'',''https://x/perfil.html?id=1'')', ana), 'ok');
  perform pg_temp.t('Reclamações','Vê os seus pedidos', ana, 'select id from reclamacoes', 'n=1');
  perform pg_temp.t('Reclamações','Terceiro NÃO vê pedidos dos outros', carlos, 'select id from reclamacoes', 'n=0');
  perform pg_temp.t('Reclamações','NÃO se marca como "resolvida" sozinho', ana, format('insert into reclamacoes(user_id,nome,email,assunto,mensagem,estado) values (%L,''Ana'',''a@b.co'',''abc'',''0123456789'',''resolvida'')', ana), 'bloqueado');
  perform pg_temp.t('Reclamações','NÃO altera o pedido depois de enviado', ana, 'update reclamacoes set estado=''resolvida''', 'bloqueado');
  perform pg_temp.t('Reclamações','NÃO apaga o pedido', ana, 'delete from reclamacoes', 'bloqueado');
  perform pg_temp.t('Reclamações','E-mail inválido recusado', null, 'insert into reclamacoes(nome,email,assunto,mensagem) values (''Ze'',''nao-e-email'',''abc'',''0123456789'')', 'bloqueado');
  perform pg_temp.t('Reclamações','Mensagem curta recusada', null, 'insert into reclamacoes(nome,email,assunto,mensagem) values (''Ze'',''ze@x.co'',''abc'',''curta'')', 'bloqueado');
  perform pg_temp.t('Reclamações','Tipo inventado recusado', null, 'insert into reclamacoes(nome,email,tipo,assunto,mensagem) values (''Ze'',''ze@x.co'',''spam'',''abc'',''0123456789'')', 'bloqueado');
  for i in 1..4 loop
    perform pg_temp.t('Reclamações','(envio ' || (i + 1) || ' do mesmo e-mail na mesma hora)', null, 'insert into reclamacoes(nome,email,assunto,mensagem) values (''Spam'',''spam@x.co'',''abc'',''0123456789'')', 'ok');
  end loop;
  perform pg_temp.t('Reclamações','(envio 1 do mesmo e-mail na mesma hora)', null, 'insert into reclamacoes(nome,email,assunto,mensagem) values (''Spam'',''SPAM@x.co'',''abc'',''0123456789'')', 'ok');
  perform pg_temp.t('Reclamações','Anti-spam: 6.º pedido na mesma hora é recusado', null, 'insert into reclamacoes(nome,email,assunto,mensagem) values (''Spam'',''spam@x.co'',''abc'',''0123456789'')', 'bloqueado');
  update reclamacoes set resposta = 'Conta removida. Obrigado!', estado = 'resolvida' where user_id = ana;
  perform pg_temp.t('Reclamações','Equipa responde → utilizador vê resposta e data', ana, 'select (estado||''|''||resposta||''|''||(respondido_em is not null)) from reclamacoes', 'v=resolvida|Conta removida. Obrigado!|true');

  -- ── 11. Ficheiros (Storage) ──
  perform pg_temp.t('Ficheiros','Enviar foto para a minha pasta', ana, format('insert into storage.objects(bucket_id,name,owner) values (''media'',%L,%L)', ana || '/foto.jpg', ana), 'ok');
  perform pg_temp.t('Ficheiros','NÃO envia para a pasta de outro', carlos, format('insert into storage.objects(bucket_id,name,owner) values (''media'',%L,%L)', ana || '/hack.jpg', carlos), 'bloqueado');
  perform pg_temp.t('Ficheiros','NÃO apaga ficheiros de outro', carlos, format('delete from storage.objects where name=%L', ana || '/foto.jpg'), 'bloqueado');
  perform pg_temp.t('Ficheiros','Pessoa NÃO envia imagens de anúncio', ana, format('insert into storage.objects(bucket_id,name,owner) values (''ads_media'',%L,%L)', ana || '/a.jpg', ana), 'bloqueado');
  perform pg_temp.t('Ficheiros','Empresa envia imagem de anúncio', loja, format('insert into storage.objects(bucket_id,name,owner) values (''ads_media'',%L,%L)', loja || '/a.jpg', loja), 'ok');
  perform pg_temp.t('Ficheiros','Anexo do chat na minha pasta', ana, format('insert into storage.objects(bucket_id,name,owner) values (''chat-media'',%L,%L)', ana || '/doc.pdf', ana), 'ok');
  perform pg_temp.t('Ficheiros','Terceiro NÃO lista anexos do chat dos outros', carlos, format('select name from storage.objects where bucket_id=''chat-media'' and name like %L', ana || '/%'), 'n=0');
  perform pg_temp.t('Ficheiros','Vídeo na minha pasta', ana, format('insert into storage.objects(bucket_id,name,owner) values (''videos'',%L,%L)', ana || '/v.mp4', ana), 'ok');
  perform pg_temp.t('Ficheiros','Foto de perfil na minha pasta', ana, format('insert into storage.objects(bucket_id,name,owner) values (''avatars'',%L,%L)', ana || '/eu.jpg', ana), 'ok');

  -- ── 12. Apagar conta (tudo o que é dela deve desaparecer) ──
  begin
    delete from auth.users where id = loja;
    insert into r(area, teste, ok, detalhe) values ('Apagar conta', 'Apagar a conta da empresa (com anúncios, mensagens, campanha)', true,
      'apagada; anúncios restantes: ' || (select count(*) from vagas_anuncios where empresa_id = loja) || ', mensagens: ' || (select count(*) from messages where sender_id = loja or receiver_id = loja));
  exception when others then
    insert into r(area, teste, ok, detalhe) values ('Apagar conta', 'Apagar a conta da empresa (com anúncios, mensagens, campanha)', false, 'ERRO: ' || sqlerrm);
  end;
  begin
    delete from auth.users where id = ana;
    insert into r(area, teste, ok, detalhe) values ('Apagar conta', 'Apagar a conta pessoal (com publicações, vídeos, reclamações)', true,
      'apagada; publicações restantes: ' || (select count(*) from posts where user_id = ana) || ', reclamações guardadas sem dono: ' || (select count(*) from reclamacoes where user_id is null and email = 'ana.teste@exemplo.co.mz'));
  exception when others then
    insert into r(area, teste, ok, detalhe) values ('Apagar conta', 'Apagar a conta pessoal (com publicações, vídeos, reclamações)', false, 'ERRO: ' || sqlerrm);
  end;

  select string_agg(case when ok then 'OK  ' else 'FALHA' end || ' | ' || area || ' | ' || teste || ' | ' || detalhe, E'\n' order by n) into relat from r;
  relat := relat || E'\n\nTOTAL: ' || (select count(*) filter (where ok) from r) || '/' || (select count(*) from r)
    || E'\nTabela reclamacoes já existia: ' || tinha_reclam;
  raise exception E'RELATORIO\n%', relat;   -- anula tudo: nada fica gravado
end $do$;
