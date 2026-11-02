/* ============================================================
   Feira Comercial — burlas.js
   Reconhece mensagens com sinais de burla, para avisar o cliente no chat.
   Não bloqueia nada nem envia nada para lado nenhum: só mostra um aviso por baixo
   da mensagem recebida. As contas oficiais (Equipa) nunca são assinaladas.

   FCBurlas.analisar(texto, { nova: bool, verificada: bool })
     → null, ou { tipo, icone, texto } com o aviso mais importante.
   ============================================================ */
(function (raiz) {
  // tira acentos e põe em minúsculas, para "Código", "codigo" e "CÓDIGO" serem iguais
  function limpar(t) {
    return String(t || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  }

  var AVISOS = {
    falsaEquipa: { icone: '🛡️', texto: 'Esta conta NÃO é da Equipa Feira Comercial. A Equipa só fala pela conta oficial, com o selo ✔.' },
    codigo:      { icone: '🔐', texto: 'Nunca partilhe códigos SMS, PIN ou a palavra-passe. Nem a Equipa da Feira os pede.' },
    adiantado:   { icone: '💸', texto: 'Cuidado com pagamentos adiantados. Prefira pagar quando receber ou vir o produto.' },
    premio:      { icone: '🎁', texto: 'Prémios que pedem pagamento, códigos ou dados pessoais são burla.' },
    link:        { icone: '🔗', texto: 'Cuidado com links: a Feira nunca pede para entrar na sua conta noutro site.' },
    pagarNova:   { icone: '⚠️', texto: 'Conta nova a pedir pagamento. Confirme bem quem é antes de enviar dinheiro.' },
    sair:        { icone: '💬', texto: 'Prefira continuar aqui: se algo correr mal, a equipa pode ver a conversa e ajudar.' },
    encurtador:  { icone: '🔗', texto: 'Link encurtado: não mostra para onde leva. Não abra se não conhece bem a pessoa.' },
    documento:   { icone: '🪪', texto: 'Nunca envie foto do BI ou selfie com o documento: podem abrir contas M-Pesa ou e-Mola em seu nome.' },
    engano:      { icone: '↩️', texto: '"Transferência por engano" é uma burla comum. Confirme no extrato oficial antes de devolver qualquer valor.' }
  };

  var R = {
    falsaEquipa: /\b(equipa|suporte|apoio|administra\w*|seguranca|moderador\w*)\b.{0,25}\bfeira\b|\bfeira comercial\b.{0,30}\b(equipa|suporte|conta (foi )?(bloquead|suspens|desativ)|verificac)/,
    codigoPalavra: /\b(codigo|codig|cod\.?|code|pin|senha|palavra[- ]?passe|password|otp|token)\b/,
    codigoPedido: /\b(envi\w*|mand\w*|diz\w*|diga|pass\w*|partilh\w*|da-?me|de-?me|confirm\w*|recebe\w*|cheg\w*|escrev\w*|copi\w*|send|give|share|tell)\b/,
    adiantado: /\b(adiantad\w*|antecipad\w*|caucao|advance|upfront)\b|\b(pag\w*|dar|de|da|mand\w*|envi\w*|transf\w*)\b.{0,15}\bsinal\b|\bsinal\b.{0,12}\b(de \d|\d|mt|meticais|para reserv)|\btaxa (de )?(entrega|envio|reserva|transporte|liberta\w*|desalfandeg\w*|alfandega)\b|\b(pag\w*|transf\w*|deposit\w*|envi\w*|mand\w*)\b.{0,25}\b(antes|primeiro|metade|50 ?%)\b|\b(pay|send).{0,15}\b(first|before)\b/,
    premio: /\b(ganhou|ganhaste|ganhaste|foi (sorteado|selecionad\w*|escolhid\w*)|premio|sorteio|bonus|you won|winner|prize)\b/,
    link: /\b(?:https?:\/\/|www\.)[^\s]+/g,
    linkIsco: /\b(entr\w*|login|verific\w*|confirm\w*|atualiz\w*|desbloque\w*|premio|ganh\w*|bonus|gratis|oferta especial)\b/,
    pagamento: /\b(m-?pesa|e-?mola|mkesh|ponto ?24|conta bancaria|nib|iban|transferencia|transfira|deposit\w*)\b/,
    numero: /(\+?258[\s-]?)?8[2-7][\s-]?\d{3}[\s-]?\d{3,4}|\d{7,}/,
    sair: /\b(whats\s?app|wa\.me|zap|telegram|t\.me|signal|liga[- ]?me|ligue[- ]?me|chama[- ]?me)\b/,
    encurtador: /\b(bit\.ly|tinyurl\.com|t\.co|cutt\.ly|is\.gd|rb\.gy|shorturl\.at|goo\.gl|ow\.ly|tiny\.cc|s\.id|rebrand\.ly|short\.io|v\.gd)\/\S+/,
    documento: /\b(foto\w*|fotografi\w*|imagem|copia|scan\w*|selfie|digitaliz\w*)\b.{0,30}\b(bi|bilhete|documento|passaporte|cartao de eleitor|dire|carta de conducao)\b|\bselfie\b.{0,25}\b(com|segurando|a segurar)\b.{0,20}\b(bi|documento|bilhete)\b/,
    engano: /\b(engano|enganei|sem querer|numero errado|errei)\b.{0,40}\b(transf\w*|envi\w*|mand\w*|deposit\w*|m-?pesa|e-?mola|mkesh|dinheiro|valor|devolv\w*)\b|\b(transf\w*|envi\w*|mand\w*|deposit\w*|devolv\w*)\b.{0,40}\b(por engano|numero errado|sem querer)\b/
  };

  function linkExterno(t) {
    var l = t.match(R.link);
    if (!l) return false;
    return l.some(function (u) { return !/^(?:https?:\/\/)?(?:www\.)?feira-comercial\.com(?:[\/?#]|$)/.test(u); });
  }

  function analisar(texto, o) {
    o = o || {};
    var t = limpar(texto);
    if (!t.trim()) return null;
    var nova = !!o.nova && !o.verificada;
    var tipo = null;
    if (R.falsaEquipa.test(t)) tipo = 'falsaEquipa';
    else if (R.codigoPalavra.test(t) && R.codigoPedido.test(t)) tipo = 'codigo';
    else if (R.adiantado.test(t)) tipo = 'adiantado';
    else if (R.documento.test(t)) tipo = 'documento';
    else if (R.engano.test(t)) tipo = 'engano';
    else if (R.encurtador.test(t)) tipo = 'encurtador';
    else if (R.premio.test(t) && (R.pagamento.test(t) || R.codigoPalavra.test(t) || linkExterno(t) || /\b(pag|envi|mand|taxa|levant|reclam)/.test(t))) tipo = 'premio';
    else if (linkExterno(t) && (nova || R.linkIsco.test(t))) tipo = 'link';
    else if (nova && R.pagamento.test(t) && R.numero.test(t)) tipo = 'pagarNova';
    else if (nova && R.sair.test(t)) tipo = 'sair';
    if (!tipo) return null;
    return { tipo: tipo, icone: AVISOS[tipo].icone, texto: AVISOS[tipo].texto };
  }

  // "há 3 dias", "hoje", "há 2 semanas" — idade de uma conta
  function emIngles() { try { return !!(raiz.FCI18N && raiz.FCI18N.lang === 'en'); } catch (e) { return false; } }
  function idade(criada) {
    // dias do calendário (no fuso do aparelho), não períodos de 24 h: criada ontem às 21h e vista
    // hoje às 08h é "ontem"; criada anteontem às 22h e vista hoje às 20h é "há 2 dias"
    var c = new Date(criada), h = new Date(raiz.FC && raiz.FC.agora ? raiz.FC.agora() : Date.now()), en = emIngles();
    var d = Math.round((new Date(h.getFullYear(), h.getMonth(), h.getDate()) - new Date(c.getFullYear(), c.getMonth(), c.getDate())) / 86400000);
    if (!(d >= 0)) return '';
    if (d === 0) return en ? 'today' : 'hoje';
    if (d === 1) return en ? 'yesterday' : 'ontem';
    if (d < 14) return en ? d + ' days ago' : 'há ' + d + ' dias';
    if (d < 60) return en ? Math.floor(d / 7) + ' weeks ago' : 'há ' + Math.floor(d / 7) + ' semanas';
    return en ? Math.floor(d / 30) + ' months ago' : 'há ' + Math.floor(d / 30) + ' meses';
  }
  // "Conta criada há 2 dias." / "Account created 2 days ago."
  function frase(criada) { return (emIngles() ? 'Account created ' : 'Conta criada ') + idade(criada) + '.'; }
  function contaNova(criada) {
    var t = new Date(criada).getTime();
    return !!t && (raiz.FC && raiz.FC.agora ? raiz.FC.agora() : Date.now()) - t < 30 * 86400000;
  }

  var api = { analisar: analisar, idade: idade, frase: frase, contaNova: contaNova, AVISOS: AVISOS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else raiz.FCBurlas = api;
})(typeof window !== 'undefined' ? window : this);
