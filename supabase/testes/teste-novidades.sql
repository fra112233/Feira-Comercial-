-- Teste das novidades (migrações 022–027) da Feira Comercial.
-- Correr no Supabase → SQL Editor. O resultado aparece como um "erro" vermelho que começa
-- por RELATORIO: é de propósito, porque o erro anula tudo e nada fica gravado.
-- Contas: Ana (pessoa), Loja (empresa), Carlos (pessoa "intruso"), Dora (empresa convidada pela Loja),
-- Chefe (administrador do tipo pessoa).
create temp table r (n serial, area text, teste text, ok boolean, detalhe text) on commit drop;
grant all on r to anon, authenticated; grant usage on sequence r_n_seq to anon, authenticated;

create function pg_temp.t(area text, teste text, uid uuid, sql text, espera text, aal text default 'aal1') returns void language plpgsql as $f$
declare n bigint; v text; err text; passou boolean; det text;
begin
  perform set_config('request.jwt.claims',
    case when uid is null then '{"role":"anon"}' else json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal)::text end, true);
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
  dora uuid := gen_random_uuid(); chefe uuid := gen_random_uuid();
  pid bigint; pid2 bigint; cid bigint; vid bigint; prod bigint; pag bigint; relat text; ate_antes timestamptz;
begin
  -- ── 0. Contas (Dora cria conta pelo link de convite da Loja) ──
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
   ('00000000-0000-0000-0000-000000000000', ana, 'authenticated', 'authenticated', 'ana.t2@exemplo.co.mz', '', now(), '{"provider":"email"}',
    '{"full_name":"Ana Teste","type":"singular","province":"Maputo Cidade","city":"Maputo"}', now(), now()),
   ('00000000-0000-0000-0000-000000000000', loja, 'authenticated', 'authenticated', 'loja.t2@exemplo.co.mz', '', now(), '{"provider":"email"}',
    '{"full_name":"Loja Teste Lda","type":"empresa","whatsapp":"+258842222222","province":"Maputo Cidade","city":"Maputo"}', now(), now()),
   ('00000000-0000-0000-0000-000000000000', carlos, 'authenticated', 'authenticated', 'carlos.t2@exemplo.co.mz', '', now(), '{"provider":"email"}',
    '{"full_name":"Carlos Intruso","type":"singular"}', now(), now()),
   ('00000000-0000-0000-0000-000000000000', chefe, 'authenticated', 'authenticated', 'chefe.t2@exemplo.co.mz', '', now(), '{"provider":"email"}',
    '{"full_name":"Chefe Teste","type":"singular"}', now(), now());
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', dora, 'authenticated', 'authenticated', 'dora.t2@exemplo.co.mz', '', now(), '{"provider":"email"}',
    json_build_object('full_name', 'Dora Lda', 'type', 'empresa', 'convidado_por', loja)::jsonb, now(), now());
  update perfis set role = 'admin' where id = chefe;

  -- ── 1. Notificações (sino) ──
  perform pg_temp.t('Notificações','Ana segue a Loja', ana, format('insert into followers(follower_id,following_id,created_at) values (%L,%L,(extract(epoch from now())*1000)::bigint)', ana, loja), 'ok');
  perform pg_temp.t('Notificações','… Loja recebe aviso "começou a segui-lo"', loja, 'select id from notificacoes where tipo=''seguir''', 'n=1');
  perform pg_temp.t('Notificações','Loja publica', loja, format('insert into posts(user_id,content) values (%L,''Novidades da semana'')', loja), 'ok');
  select max(id) into pid from posts where user_id = loja;
  perform pg_temp.t('Notificações','… a seguidora (Ana) recebe aviso da publicação', ana, format('select id from notificacoes where tipo=''publicacao'' and post_id=%s', pid), 'n=1');
  perform pg_temp.t('Notificações','… quem não segue (Carlos) NÃO recebe', carlos, 'select id from notificacoes', 'n=0');
  perform pg_temp.t('Notificações','Ana gosta da publicação', ana, format('insert into likes(post_id,user_id) values (%s,%L)', pid, ana), 'ok');
  perform pg_temp.t('Notificações','Ana tira e volta a pôr o gosto', ana, format('delete from likes where post_id=%s and user_id=%L', pid, ana), 'ok');
  perform pg_temp.t('Notificações','(volta a pôr)', ana, format('insert into likes(post_id,user_id) values (%s,%L)', pid, ana), 'ok');
  perform pg_temp.t('Notificações','… anti-spam: Loja tem só 1 aviso de gosto', loja, 'select id from notificacoes where tipo=''gosto''', 'n=1');
  perform pg_temp.t('Notificações','Loja gosta da própria publicação: sem aviso', loja, format('insert into likes(post_id,user_id) values (%s,%L)', pid, loja), 'ok');
  perform pg_temp.t('Notificações','… continua 1 aviso de gosto', loja, 'select id from notificacoes where tipo=''gosto''', 'n=1');
  perform pg_temp.t('Notificações','Carlos comenta', carlos, format('insert into comments(post_id,user_id,content) values (%s,%L,''Tem entrega?'')', pid, carlos), 'ok');
  select max(id) into cid from comments where post_id = pid;
  perform pg_temp.t('Notificações','… Loja recebe aviso de comentário com o texto', loja, 'select texto from notificacoes where tipo=''comentario''', 'v=Tem entrega?');
  perform pg_temp.t('Notificações','Loja responde ao Carlos', loja, format('insert into comments(post_id,user_id,content,parent_id) values (%s,%L,''Sim, temos'',%s)', pid, loja, cid), 'ok');
  perform pg_temp.t('Notificações','… Carlos recebe aviso de resposta', carlos, 'select id from notificacoes where tipo=''resposta''', 'n=1');
  perform pg_temp.t('Notificações','Loja bloqueia o Carlos', loja, format('insert into bloqueios(blocker_id,blocked_id) values (%L,%L)', loja, carlos), 'ok');
  perform pg_temp.t('Notificações','Carlos (bloqueado) gosta', carlos, format('insert into likes(post_id,user_id) values (%s,%L)', pid, carlos), 'ok');
  perform pg_temp.t('Notificações','… Loja NÃO recebe aviso de quem bloqueou', loja, format('select id from notificacoes where autor_id=%L and tipo=''gosto''', carlos), 'n=0');
  perform pg_temp.t('Notificações','Cada um só vê os seus avisos', ana, format('select id from notificacoes where user_id<>%L', ana), 'n=0');
  perform pg_temp.t('Notificações','Sem sessão NÃO vê avisos', null, 'select id from notificacoes', 'bloqueado');
  perform pg_temp.t('Notificações','NÃO cria avisos falsos', carlos, format('insert into notificacoes(user_id,autor_id,tipo) values (%L,%L,''seguir'')', ana, carlos), 'bloqueado');
  perform pg_temp.t('Notificações','NÃO chama a função interna de avisos', carlos, format('select criar_notificacao(%L,%L,''seguir'')', ana, carlos), 'bloqueado');
  perform pg_temp.t('Notificações','Marcar como lida', ana, 'update notificacoes set lida=true', 'ok');
  perform pg_temp.t('Notificações','NÃO muda o tipo/texto do aviso', ana, 'update notificacoes set texto=''hack''', 'bloqueado');
  perform pg_temp.t('Notificações','Apagar os meus avisos', ana, 'delete from notificacoes', 'ok');
  perform pg_temp.t('Notificações','Loja faz Live → seguidora recebe aviso', loja, format('insert into lives(user_id,titulo) values (%L,''Abertura'')', loja), 'ok');
  perform pg_temp.t('Notificações','… aviso de Live', ana, 'select id from notificacoes where tipo=''live''', 'n=1');
  perform pg_temp.t('Notificações','Loja publica vídeo → seguidora avisada', loja, format('insert into videos(user_id,video_url,caption) values (%L,''https://x/v.mp4'',''Stock novo'')', loja), 'ok');
  select max(id) into vid from videos where user_id = loja;
  perform pg_temp.t('Notificações','… aviso de vídeo', ana, format('select id from notificacoes where tipo=''video'' and video_id=%s', vid), 'n=1');
  perform pg_temp.t('Notificações','Gosto e comentário no vídeo avisam a Loja', ana, format('insert into video_likes(video_id,user_id) values (%s,%L)', vid, ana), 'ok');
  perform pg_temp.t('Notificações','(comentário no vídeo)', ana, format('insert into video_comments(video_id,user_id,content) values (%s,%L,''Lindo'')', vid, ana), 'ok');
  perform pg_temp.t('Notificações','… Loja tem os 2 avisos do vídeo', loja, 'select id from notificacoes where tipo in (''gosto_video'',''comentario_video'')', 'n=2');

  -- ── 2. Estatísticas ──
  perform pg_temp.t('Estatísticas','Ana visita o perfil da Loja', ana, format('select coalesce(registar_evento(%L,''perfil'')::text,''feito'')', loja), 'v=');
  perform pg_temp.t('Estatísticas','… visita outra vez (não deve contar 2x)', ana, format('select coalesce(registar_evento(%L,''perfil'')::text,''feito'')', loja), 'v=');
  perform pg_temp.t('Estatísticas','Ana clica no WhatsApp', ana, format('select coalesce(registar_evento(%L,''whatsapp'')::text,''feito'')', loja), 'v=');
  perform pg_temp.t('Estatísticas','Publicação vista no feed', ana, format('select coalesce(registar_vistas(array[%s]::bigint[])::text,''feito'')', pid), 'v=');
  perform pg_temp.t('Estatísticas','A Loja a ver-se a si própria não conta', loja, format('select coalesce(registar_evento(%L,''perfil'')::text,''feito'')', loja), 'v=');
  perform pg_temp.t('Estatísticas','Visita a uma pessoa (não empresa) não conta', loja, format('select coalesce(registar_evento(%L,''perfil'')::text,''feito'')', ana), 'v=');
  perform pg_temp.t('Estatísticas','Loja vê: 1 visita ao perfil', loja, 'select minhas_estatisticas(7)->''atual''->>''perfil''', 'v=1');
  perform pg_temp.t('Estatísticas','… 1 clique no WhatsApp', loja, 'select minhas_estatisticas(7)->''atual''->>''whatsapp''', 'v=1');
  perform pg_temp.t('Estatísticas','… 1 vista da publicação', loja, 'select minhas_estatisticas(7)->''atual''->>''publicacao''', 'v=1');
  perform pg_temp.t('Estatísticas','… 1 pessoa alcançada', loja, 'select minhas_estatisticas(7)->>''visitantes''', 'v=1');
  perform pg_temp.t('Estatísticas','… 2 gostos recebidos (Ana e Carlos; o próprio não conta)', loja, 'select minhas_estatisticas(7)->>''gostos''', 'v=2');
  perform pg_temp.t('Estatísticas','… 1 seguidor novo', loja, 'select minhas_estatisticas(7)->>''seguidores_novos''', 'v=1');
  perform pg_temp.t('Estatísticas','… gráfico com 30 dias', loja, 'select jsonb_array_length(minhas_estatisticas(30)->''por_dia'')::text', 'v=30');
  perform pg_temp.t('Estatísticas','Ninguém lê os eventos diretamente', carlos, 'select id from eventos', 'bloqueado');
  perform pg_temp.t('Estatísticas','Sem sessão NÃO regista eventos', null, format('select registar_evento(%L,''perfil'')', loja), 'bloqueado');

  -- ── 3. Guardados e Ofertas ──
  perform pg_temp.t('Guardados','Ana guarda a publicação', ana, format('insert into guardados(user_id,post_id) values (%L,%s)', ana, pid), 'ok');
  perform pg_temp.t('Guardados','NÃO guarda duas vezes', ana, format('insert into guardados(user_id,post_id) values (%L,%s)', ana, pid), 'bloqueado');
  perform pg_temp.t('Guardados','NÃO guarda em nome de outro', carlos, format('insert into guardados(user_id,post_id) values (%L,%s)', ana, pid), 'bloqueado');
  perform pg_temp.t('Guardados','Outros NÃO veem os guardados da Ana', carlos, 'select post_id from guardados', 'n=0');
  perform pg_temp.t('Guardados','Ana vê os seus guardados', ana, 'select post_id from guardados', 'n=1');
  perform pg_temp.t('Ofertas','Loja publica oferta relâmpago', loja, format('insert into posts(user_id,content,oferta_preco,oferta_preco_antigo,oferta_ate) values (%L,''Ténis'',1500,2200,now()+interval ''6 hours'')', loja), 'ok');
  select max(id) into pid2 from posts where user_id = loja;
  perform pg_temp.t('Ofertas','… seguidora recebe "⚡ Oferta: 1 500 MT"', ana, format('select texto from notificacoes where post_id=%s', pid2), 'v=⚡ Oferta: 1 500 MT · Ténis');
  perform pg_temp.t('Ofertas','… aparece no filtro de ofertas', ana, format('select id from posts where oferta_ate > now() and user_id=%L', loja), 'n=1');
  perform pg_temp.t('Ofertas','Recusa oferta sem preço', loja, format('insert into posts(user_id,content,oferta_ate) values (%L,''x'',now()+interval ''1 hour'')', loja), 'bloqueado');
  perform pg_temp.t('Ofertas','Recusa preço antes menor que a oferta', loja, format('insert into posts(user_id,content,oferta_preco,oferta_preco_antigo,oferta_ate) values (%L,''x'',100,50,now()+interval ''1 hour'')', loja), 'bloqueado');
  perform pg_temp.t('Ofertas','Recusa oferta com mais de 7 dias', loja, format('insert into posts(user_id,content,oferta_preco,oferta_ate) values (%L,''x'',100,now()+interval ''9 days'')', loja), 'bloqueado');
  perform pg_temp.t('Ofertas','Recusa oferta já terminada', loja, format('insert into posts(user_id,content,oferta_preco,oferta_ate) values (%L,''x'',100,now()-interval ''1 hour'')', loja), 'bloqueado');

  -- ── 4. Produtos ──
  perform pg_temp.t('Produtos','Loja adiciona produto', loja, format('insert into produtos(user_id,nome,preco,foto_url) values (%L,''Ténis Nike'',4500,''https://x/t.jpg'')', loja), 'ok');
  select max(id) into prod from produtos where user_id = loja;
  perform pg_temp.t('Produtos','Pessoa NÃO adiciona produtos', ana, format('insert into produtos(user_id,nome) values (%L,''x'')', ana), 'bloqueado');
  perform pg_temp.t('Produtos','NÃO adiciona em nome de outra empresa', carlos, format('insert into produtos(user_id,nome) values (%L,''x'')', loja), 'bloqueado');
  perform pg_temp.t('Produtos','Recusa foto com endereço perigoso', loja, format('insert into produtos(user_id,nome,foto_url) values (%L,''x'',''javascript:alert(1)'')', loja), 'bloqueado');
  perform pg_temp.t('Produtos','Recusa nome vazio', loja, format('insert into produtos(user_id,nome) values (%L,''   '')', loja), 'bloqueado');
  perform pg_temp.t('Produtos','Recusa preço negativo', loja, format('insert into produtos(user_id,nome,preco) values (%L,''x'',-5)', loja), 'bloqueado');
  perform pg_temp.t('Produtos','Clientes veem o produto', ana, format('select id from produtos where user_id=%L', loja), 'n=1');
  perform pg_temp.t('Produtos','Outro NÃO muda o preço', carlos, format('update produtos set preco=1 where id=%s', prod), 'bloqueado');
  perform pg_temp.t('Produtos','Outro NÃO apaga', carlos, format('delete from produtos where id=%s', prod), 'bloqueado');
  perform pg_temp.t('Produtos','Loja esconde o produto', loja, format('update produtos set disponivel=false where id=%s', prod), 'ok');
  perform pg_temp.t('Produtos','… clientes deixam de o ver', ana, format('select id from produtos where id=%s', prod), 'n=0');
  perform pg_temp.t('Produtos','… a Loja continua a vê-lo', loja, format('select id from produtos where id=%s', prod), 'n=1');

  -- ── 5. Avaliações ──
  perform pg_temp.t('Avaliações','Ana avalia a Loja com 4 estrelas', ana, format('insert into avaliacoes(empresa_id,user_id,estrelas,comentario) values (%L,%L,4,''Bom atendimento'')', loja, ana), 'ok');
  perform pg_temp.t('Avaliações','… Loja recebe aviso com as estrelas', loja, 'select texto from notificacoes where tipo=''avaliacao''', 'v=★★★★☆ · Bom atendimento');
  perform pg_temp.t('Avaliações','NÃO avalia duas vezes (só atualiza)', ana, format('insert into avaliacoes(empresa_id,user_id,estrelas) values (%L,%L,5)', loja, ana), 'bloqueado');
  perform pg_temp.t('Avaliações','NÃO avalia pessoas (só empresas)', loja, format('insert into avaliacoes(empresa_id,user_id,estrelas) values (%L,%L,5)', ana, loja), 'bloqueado');
  perform pg_temp.t('Avaliações','Empresa NÃO se avalia a si própria', loja, format('insert into avaliacoes(empresa_id,user_id,estrelas) values (%L,%L,5)', loja, loja), 'bloqueado');
  perform pg_temp.t('Avaliações','NÃO aceita 6 estrelas', carlos, format('insert into avaliacoes(empresa_id,user_id,estrelas) values (%L,%L,6)', loja, carlos), 'bloqueado');
  perform pg_temp.t('Avaliações','NÃO avalia em nome de outro', carlos, format('insert into avaliacoes(empresa_id,user_id,estrelas) values (%L,%L,1)', loja, ana), 'bloqueado');
  perform pg_temp.t('Avaliações','Loja responde', loja, format('update avaliacoes set resposta=''Obrigado, Ana!'' where empresa_id=%L', loja), 'ok');
  perform pg_temp.t('Avaliações','… Ana recebe aviso da resposta', ana, 'select id from notificacoes where tipo=''resposta_avaliacao''', 'n=1');
  perform pg_temp.t('Avaliações','Loja tenta mudar as estrelas para 5', loja, format('update avaliacoes set estrelas=5 where empresa_id=%L', loja), 'ok');
  perform pg_temp.t('Avaliações','… as estrelas NÃO mudam', ana, format('select estrelas::text from avaliacoes where empresa_id=%L', loja), 'v=4');
  perform pg_temp.t('Avaliações','Ana tenta escrever a resposta da empresa', ana, format('update avaliacoes set resposta=''falsa'' where empresa_id=%L', loja), 'ok');
  perform pg_temp.t('Avaliações','… a resposta NÃO muda', ana, format('select resposta from avaliacoes where empresa_id=%L', loja), 'v=Obrigado, Ana!');
  perform pg_temp.t('Avaliações','Média e total', carlos, format('select media||''/''||total from resumo_avaliacoes(array[%L]::uuid[])', loja), 'v=4.0/1');
  perform pg_temp.t('Avaliações','Terceiro NÃO apaga a avaliação', carlos, format('delete from avaliacoes where empresa_id=%L', loja), 'bloqueado');

  -- ── 6. Convide e ganhe ──
  insert into r(area, teste, ok, detalhe) select 'Convites', 'Dora ficou ligada à Loja que a convidou', convidado_por = loja, coalesce(convidado_por::text, 'sem convite') from perfis where id = dora;
  perform pg_temp.t('Convites','… Loja recebe aviso "criou conta com o seu convite"', loja, 'select id from notificacoes where tipo=''convite_aceite''', 'n=1');
  perform pg_temp.t('Convites','Dora tenta mudar quem a convidou', dora, format('update perfis set convidado_por=%L where id=%L', carlos, dora), 'ok');
  insert into r(area, teste, ok, detalhe) select 'Convites', '… NÃO muda', convidado_por = loja, 'continua ligada a quem convidou' from perfis where id = dora;
  select assinatura_ate into ate_antes from perfis where id = loja;
  perform pg_temp.t('Convites','Dora envia pagamento', dora, format('insert into pagamentos(empresa_id,metodo,meses,codigo_transacao,telefone) values (%L,''banco'',1,''TESTE001'',''840000000'')', dora), 'ok');
  select max(id) into pag from pagamentos where empresa_id = dora;
  perform pg_temp.t('Convites','Dora NÃO confirma o próprio pagamento', dora, format('update pagamentos set estado=''confirmado'' where id=%s', pag), 'bloqueado');
  perform pg_temp.t('Convites','Administrador confirma', chefe, format('update pagamentos set estado=''confirmado'' where id=%s', pag), 'ok');
  insert into r(area, teste, ok, detalhe) select 'Convites', '… Loja ganhou 30 dias grátis', round(extract(epoch from assinatura_ate - ate_antes)/86400) = 30, round(extract(epoch from assinatura_ate - ate_antes)/86400) || ' dias' from perfis where id = loja;
  perform pg_temp.t('Convites','… Loja recebe aviso do prémio', loja, 'select id from notificacoes where tipo=''convite_premio''', 'n=1');
  perform pg_temp.t('Convites','2.º pagamento da Dora', dora, format('insert into pagamentos(empresa_id,metodo,meses,codigo_transacao,telefone) values (%L,''banco'',1,''TESTE002'',''840000000'')', dora), 'ok');
  select max(id) into pag from pagamentos where empresa_id = dora;
  perform pg_temp.t('Convites','(confirmado)', chefe, format('update pagamentos set estado=''confirmado'' where id=%s', pag), 'ok');
  insert into r(area, teste, ok, detalhe) select 'Convites', '… o prémio só é dado UMA vez', round(extract(epoch from assinatura_ate - ate_antes)/86400) = 30, round(extract(epoch from assinatura_ate - ate_antes)/86400) || ' dias no total' from perfis where id = loja;
  perform pg_temp.t('Convites','Números do convite da Loja', loja, 'select meus_convites()->>''contas''||''/''||(meus_convites()->>''premios'')||''/''||(meus_convites()->>''dias'')', 'v=1/1/30');

  -- ── 7. Privacidade ──
  perform pg_temp.t('Privacidade','Carlos passa a aceitar mensagens só de quem segue', carlos, format('update perfis set mensagens_de=''seguidos'' where id=%L', carlos), 'ok');
  perform pg_temp.t('Privacidade','Ana NÃO consegue escrever ao Carlos', ana, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,''olá'')', ana, carlos), 'bloqueado');
  perform pg_temp.t('Privacidade','Administrador consegue sempre escrever', chefe, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,''Aviso da equipa'')', chefe, carlos), 'ok');
  perform pg_temp.t('Privacidade','Carlos segue a Ana', carlos, format('insert into followers(follower_id,following_id) values (%L,%L)', carlos, ana), 'ok');
  perform pg_temp.t('Privacidade','… agora a Ana já consegue escrever', ana, format('insert into messages(sender_id,receiver_id,content) values (%L,%L,''olá'')', ana, carlos), 'ok');
  perform pg_temp.t('Privacidade','Valor inventado recusado', carlos, format('update perfis set mensagens_de=''ninguem'' where id=%L', carlos), 'bloqueado');
  perform pg_temp.t('Privacidade','Descarregar os meus dados', ana, 'select (exportar_meus_dados()->''perfil''->>''full_name'')', 'v=Ana Teste');
  perform pg_temp.t('Privacidade','… inclui as minhas mensagens (boas-vindas + a que enviei)', ana, 'select jsonb_array_length(exportar_meus_dados()->''mensagens'')::text', 'v=2');
  perform pg_temp.t('Privacidade','… NÃO inclui dados de outros', carlos, 'select (exportar_meus_dados()->''perfil''->>''full_name'')', 'v=Carlos Intruso');
  perform pg_temp.t('Privacidade','Sem sessão NÃO exporta nada', null, 'select exportar_meus_dados()::text', 'bloqueado');

  -- ── 8. Administrador ──
  perform pg_temp.t('Administrador','Admin (tipo pessoa) publica no feed', chefe, format('insert into posts(user_id,content) values (%L,''Comunicado da Feira Comercial'')', chefe), 'ok');
  perform pg_temp.t('Administrador','Admin cria anúncio', chefe, format('insert into vagas_anuncios(empresa_id,titulo,descricao) values (%L,''Feira de Natal'',''Inscrições abertas'')', chefe), 'ok');
  perform pg_temp.t('Administrador','Admin faz Live', chefe, format('insert into lives(user_id,titulo) values (%L,''Boas-vindas'')', chefe), 'ok');
  perform pg_temp.t('Administrador','Pessoa normal continua SEM publicar', ana, format('insert into posts(user_id,content) values (%L,''Olá'')', ana), 'bloqueado');
  perform pg_temp.t('Administrador','Admin vê os pagamentos', chefe, format('select id from pagamentos where empresa_id=%L', dora), 'n=2');
  insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    values (gen_random_uuid(), chefe, 'Teste', 'totp', 'verified', now(), now());
  perform pg_temp.t('Administrador','Com 2 passos ativos, sessão SEM código NÃO tem poderes', chefe, format('select id from pagamentos where empresa_id=%L', dora), 'n=0');
  perform pg_temp.t('Administrador','… sessão COM código tem poderes', chefe, format('select id from pagamentos where empresa_id=%L', dora), 'n=2', 'aal2');

  -- ── 9. Apagar conta: pagamentos ficam guardados ──
  begin
    delete from auth.users where id = dora;
    insert into r(area, teste, ok, detalhe)
    select 'Apagar conta', 'Conta da Dora apagada; pagamentos guardados com o nome', count(*) = 2 and bool_and(empresa_nome = 'Dora Lda'),
           count(*) || ' pagamento(s) guardado(s), nome: ' || coalesce(string_agg(distinct empresa_nome, ','), '-')
      from pagamentos where empresa_id is null and codigo_transacao in ('TESTE001', 'TESTE002');
  exception when others then
    insert into r(area, teste, ok, detalhe) values ('Apagar conta', 'Conta da Dora apagada; pagamentos guardados', false, 'ERRO: ' || sqlerrm);
  end;

  select string_agg(case when ok then 'OK  ' else 'FALHA' end || ' | ' || area || ' | ' || teste || ' | ' || detalhe, E'\n' order by n) into relat from r;
  relat := relat || E'\n\nTOTAL: ' || (select count(*) filter (where ok) from r) || '/' || (select count(*) from r);
  raise exception E'RELATORIO\n%', relat;   -- anula tudo: nada fica gravado
end $do$;
