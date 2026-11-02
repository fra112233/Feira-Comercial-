-- 075: segurança, ronda 1
--  • Detetor de burlas no servidor (usado no painel "Suspeitos"): mais 3 sinais, iguais aos do
--    aviso no chat (burlas.js) — pedir foto do BI/selfie com documento, "transferência por
--    engano, devolva", e links encurtados que escondem o destino.
--  • Candidaturas e CVs são apagados 3 meses (90 dias) depois de a vaga terminar (ou da
--    candidatura, se a vaga não tiver data de fim). A função abaixo só diz quais; quem apaga
--    (linhas e ficheiros) é a limpeza automática diária (função limpeza-expirados).

create or replace function public.sinal_burla(t text)
returns text language sql immutable set search_path = public as $$
  select case
    when x ~ '(equipa|suporte|apoio|administra\w*|seguranca|moderador\w*)\M.{0,25}\mfeira\M' then 'equipa'
    when x ~ '\m(codigo|cod|code|pin|senha|palavra.?passe|password|otp|token)\M'
     and x ~ '\m(envi|mand|diz|diga|pass|partilh|da-?me|de-?me|confirm|recebe|cheg|escrev|copi|send|give|share|tell)' then 'codigo'
    when x ~ '\m(adiantad\w*|antecipad\w*|caucao|advance|upfront)\M'
      or x ~ '\m(pag|transf|deposit|envi|mand)\w*\M.{0,25}\m(antes|primeiro|metade)\M'
      or x ~ '\m(pag\w*|dar|de|da|mand\w*|envi\w*|transf\w*)\M.{0,15}\msinal\M'
      or x ~ '\mtaxa (de )?(entrega|envio|reserva|transporte|liberta\w*|alfandeg\w*|desalfandeg\w*)' then 'adiantado'
    when x ~ '\m(foto\w*|fotografi\w*|imagem|copia|scan\w*|selfie|digitaliz\w*)\M.{0,30}\m(bi|bilhete|documento|passaporte|cartao de eleitor|dire|carta de conducao)\M'
      or x ~ '\mselfie\M.{0,25}\m(com|segurando|a segurar)\M.{0,20}\m(bi|documento|bilhete)\M' then 'documento'
    when x ~ '\m(engano|enganei|sem querer|numero errado|errei)\M.{0,40}\m(transf\w*|envi\w*|mand\w*|deposit\w*|m-?pesa|e-?mola|mkesh|dinheiro|valor|devolv\w*)\M'
      or x ~ '\m(transf\w*|envi\w*|mand\w*|deposit\w*|devolv\w*)\M.{0,40}\m(por engano|numero errado|sem querer)\M' then 'engano'
    when x ~ '\m(bit\.ly|tinyurl\.com|t\.co|cutt\.ly|is\.gd|rb\.gy|shorturl\.at|goo\.gl|ow\.ly|tiny\.cc|s\.id|rebrand\.ly|short\.io|v\.gd)/\S+' then 'encurtador'
    when x ~ '\m(ganhou|ganhaste|sorteado|premio|sorteio|bonus|prize|winner)\M'
     and x ~ '\m(pag|envi|mand|taxa|codigo|levant|reclam)' then 'premio'
  end
  from (select translate(lower(coalesce(t, '')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') as x) s
$$;

create or replace function public.candidaturas_expiradas(p_dias integer default 90)
returns table (id bigint, cv text) language sql stable security definer set search_path = public as $$
  select c.id, c.cv from candidaturas c left join vagas_anuncios a on a.id = c.anuncio_id
   where coalesce(a.validade, (c.criado at time zone 'Africa/Maputo')::date)
         < (now() at time zone 'Africa/Maputo')::date - greatest(coalesce(p_dias, 90), 30);
$$;
revoke all on function public.candidaturas_expiradas(integer) from public, anon, authenticated;
