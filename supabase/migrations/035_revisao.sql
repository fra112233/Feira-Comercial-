-- ============================================================
-- Feira Comercial — 035: Revisão de segurança (reforço)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema. Não muda nada para os utilizadores.
--
-- 1) A função agora() passa a ter o search_path fixo (aviso do Supabase).
-- 2) Visitantes SEM conta (anon) deixam de ter permissão de escrita nas tabelas.
--    As regras (RLS) já os bloqueavam; isto é uma segunda tranca.
--    "reclamacoes" fica como está: o Livro de Reclamações aceita pedidos sem conta.
-- ============================================================

alter function public.agora() set search_path = public;

do $$
declare t text;
begin
  foreach t in array array['ad_campaigns','bloqueios','comments','config','followers','likes','lives',
                           'messages','pagamentos','perfis','posts','vagas_anuncios','video_comments',
                           'video_likes','videos']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('revoke insert, update, delete, truncate on public.%I from anon', t);
    end if;
  end loop;
end $$;
