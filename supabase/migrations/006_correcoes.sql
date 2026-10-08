-- ============================================================
-- Feira Comercial — 006: correções encontradas nos registos de erros
-- Correr UMA vez no Supabase: SQL Editor → New query → colar → Run
-- ============================================================

-- 1) Anúncios: havia uma regra antiga que só aceitava os tipos 'vaga' e 'anuncio'.
--    Junto com a regra nova (promo/vaga/servico), só "vaga" passava → promoções e
--    serviços eram recusados. Removemos a antiga; fica a nova.
alter table public.vagas_anuncios drop constraint if exists vagas_anuncios_tipo_check;

-- 2) Mensagens: o campo do ficheiro era obrigatório, por isso mensagens só de texto
--    (sem foto/ficheiro) eram recusadas.
alter table public.messages alter column file_url drop not null;

-- 3) Mensagens: se uma conta for apagada, apagar também as mensagens recebidas
--    (antes a regra tentava pôr o destinatário a vazio, o que não é permitido).
alter table public.messages drop constraint if exists messages_receiver_id_fkey;
alter table public.messages add constraint messages_receiver_id_fkey
  foreign key (receiver_id) references public.perfis(id) on delete cascade;
