/* ============================================================
   Feira Comercial — i18n.js : modo inglês (English mode)
   O site é escrito em português; com o inglês ligado, este ficheiro traduz
   os textos da interface no próprio navegador (incluindo os que aparecem
   depois, como avisos e janelas). O que as pessoas escrevem não é traduzido.
   Escolha guardada no aparelho: localStorage "fc_lang" = "pt" | "en".
   ============================================================ */
(function () {
  var CHAVE = 'fc_lang';
  var lang = 'pt';
  try {
    var g = localStorage.getItem(CHAVE);
    if (g === 'en' || g === 'pt') lang = g;
  } catch (e) {}

  var api = window.FCI18N = {
    lang: lang,
    // guarda no aparelho e, com sessão iniciada, também na conta (avisos, boas-vindas e e-mails nesse idioma)
    definir: function (l) {
      try { localStorage.setItem(CHAVE, l); } catch (e) {}
      api.guardarNaConta(l).then(function () { location.reload(); }, function () { location.reload(); });
    },
    guardarNaConta: function (l) {
      try {
        if (typeof supabaseClient === 'undefined') return Promise.resolve();
        return supabaseClient.auth.getSession().then(function (r) {
          var s = r && r.data && r.data.session; if (!s) return;
          return Promise.all([
            supabaseClient.from('perfis').update({ idioma: l }).eq('id', s.user.id),
            supabaseClient.auth.updateUser({ data: { idioma: l } })
          ]);
        }).catch(function () {});
      } catch (e) { return Promise.resolve(); }
    },
    escolhido: function () { try { return localStorage.getItem(CHAVE); } catch (e) { return null; } },
    alternar: function () { api.definir(lang === 'en' ? 'pt' : 'en'); },
    t: function (s) { return s; }
  };

  // botão PT / EN nas páginas sem menu (entrar, criar conta, recuperar palavra-passe, vídeos)
  function pilula() {
    if (window.FCMenu || document.getElementById('fc-lang')) return;
    if (!/(Portal|Formulario|password|loja)\.html/i.test(location.pathname) && !/\/$/.test(location.pathname)) return;   // só nas páginas de entrada
    // seletor "PT | EN" no canto de cima (páginas de entrar, criar conta, recuperar palavra-passe…)
    var w = document.createElement('div');
    w.id = 'fc-lang';
    w.setAttribute('data-no-i18n', '');
    w.setAttribute('role', 'group');
    w.setAttribute('aria-label', 'Idioma / Language');
    w.style.cssText = 'position:fixed;top:12px;right:12px;z-index:5000;display:flex;align-items:center;gap:2px;padding:3px;border-radius:999px;border:1px solid rgba(243,198,78,.45);background:rgba(22,22,26,.92);font:700 13px Inter,system-ui,sans-serif;box-shadow:0 6px 20px rgba(0,0,0,.35)';
    ['pt', 'en'].forEach(function (l) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = (l === 'pt' ? '🇲🇿 PT' : '🇬🇧 EN');
      var on = l === lang;
      b.style.cssText = 'border:none;cursor:pointer;padding:7px 12px;border-radius:999px;font:inherit;' + (on ? 'background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#111' : 'background:transparent;color:#f3c64e');
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
      b.onclick = function () { if (l !== lang) api.definir(l); };
      w.appendChild(b);
    });
    document.body.appendChild(w);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { setTimeout(pilula, 50); });
  else setTimeout(pilula, 50);

  if (lang !== 'en') return;
  document.documentElement.lang = 'en';

  var D = __DICIONARIO__;

  // palavras soltas (horários, dias) para o resto de frases compostas
  var W = { 'segunda': 'Monday', 'terça': 'Tuesday', 'quarta': 'Wednesday', 'quinta': 'Thursday', 'sexta': 'Friday', 'sábado': 'Saturday', 'domingo': 'Sunday',
    'às': 'at', 'amanhã': 'tomorrow', 'hoje': 'today', 'ontem': 'yesterday', 'e': 'and', 'dias': 'days', 'dia': 'day', 'meses': 'months', 'mês': 'month', 'em': 'in' };

  var REGRAS = [
    [/^Os seus dias grátis acabam em (\d+) dias$/, 'Your free days end in $1 days'],
    [/^A mensalidade termina em (\d+) dias$/, 'The subscription ends in $1 days'],
    [/^Pague (\d+) MT para continuar a mostrar a sua loja\.$/, 'Pay $1 MT to keep showing your shop.'],
    [/^Faltam (\d+) campos: (.+)$/, function (m, n, l) { return n + ' fields missing: ' + l.split(', ').map(function (x) { return api.t(x); }).join(', '); }],
    [/^Falta 1 campo: (.+)$/, function (m, l) { return '1 field missing: ' + api.t(l); }],
    [/^há (\d+) min$/, '$1 min ago'], [/^há (\d+) h$/, '$1 h ago'], [/^há (\d+) d$/, '$1 d ago'], [/^há (\d+) dias?$/, '$1 days ago'],
    [/^agora mesmo$/, 'just now'], [/^agora$/, 'now'],
    [/^(\d+) Gostos?$/, function (m, n) { return n + (n === '1' ? ' Like' : ' Likes'); }],
    [/^(\d+) gostos?$/, function (m, n) { return n + (n === '1' ? ' like' : ' likes'); }],
    [/^(\d+) comentários?$/, function (m, n) { return n + (n === '1' ? ' comment' : ' comments'); }],
    [/^(\d+) seguidor(es)?$/i, function (m, n) { return n + (n === '1' ? ' follower' : ' followers'); }],
    [/^(\d+) publicaç(ão|ões)$/i, function (m, n) { return n + (n === '1' ? ' post' : ' posts'); }],
    [/^(\d+) mensage(m|ns)$/i, function (m, n) { return n + (n === '1' ? ' message' : ' messages'); }],
    [/^(\d+) dias?$/, function (m, n) { return n + (n === '1' ? ' day' : ' days'); }],
    [/^(\d+) mes(es)?$|^(\d+) mês$/, function (m, a, b, c) { var n = a || c; return n + (n === '1' ? ' month' : ' months'); }],
    [/^termina em (\d+) dias$/, 'ends in $1 days'],
    [/^(\d+) ao vivo$/, '$1 live'],
    [/^(.+) está em direto$/, '$1 is live'],
    [/^(.+) e (.+) estão em direto$/, '$1 and $2 are live'],
    [/^(.+), (.+) e mais (\d+) estão em direto$/, '$1, $2 and $3 more are live'],
    [/^Reenviar em (\d+) ?s$/, 'Resend in $1 s'],
    [/^Membro desde (.+)$/, 'Member since $1'],
    [/^Ver perfil de (.+)$/, 'View profile of $1'],
    [/^Para falar com (.+), encomendar ou segui-la, crie a sua conta grátis na Feira Comercial — leva 1 minuto\.$/, function (m, a) { return 'To talk to ' + (a === 'esta empresa' ? 'this business' : a) + ', order or follow it, create your free Feira Comercial account — it takes 1 minute.'; }],
    [/^(\d+)\+? produtos?$/, function (m, n) { return m.replace(/produtos?$/, n === '1' ? 'product' : 'products'); }],
    [/^(\d+) de (\d+)$/, '$1 of $2'],
    [/^Seguir 3 empresas \((\d)\/3\)$/, 'Follow 3 businesses ($1/3)'],
    [/^(\d+) horas?$/, function (m, n) { return n + (n === '1' ? ' hour' : ' hours'); }],
    [/^\((\d+) avaliaç(ão|ões)\)$/, function (m, n) { return '(' + n + (n === '1' ? ' review)' : ' reviews)'); }],
    [/^(\d+) avaliaç(ão|ões)$/, function (m, n) { return n + (n === '1' ? ' review' : ' reviews'); }],
    [/^(\d+)% vs\. (\d+) dias antes$/, '$1% vs. the previous $2 days'],
    [/^Quantas pessoas viram e contactaram (.+)\. Cada pessoa só conta uma vez por visita\.$/, function (m, a) { return 'How many people saw and contacted ' + (a === 'a sua empresa' ? 'your business' : a) + '. Each person counts only once per visit.'; }],
    [/^Resposta pública a (.+):$/, function (m, a) { return 'Public reply to ' + (a === 'este cliente' ? 'this customer' : a) + ':'; }],
    [/^hoje às (\d{1,2}:\d{2})$/, 'today at $1'], [/^ontem às (\d{1,2}:\d{2})$/, 'yesterday at $1'], [/^amanhã às (\d{1,2}:\d{2})$/, 'tomorrow at $1'],
    [/^hoje, (.+), às (\d{1,2}:\d{2})$/, 'today, $1, at $2'],
    [/^(.*\d.*?),? às (\d{1,2}:\d{2})$/, '$1 at $2'],
    [/^Já estão (\d+) pessoas a ver, o máximo permitido\. Assim que alguém sair, pode entrar\.$/, 'There are already $1 people watching, the maximum allowed. As soon as someone leaves, you can join.'],
    [/^Esta foto tem (.+?)\. O máximo é 100 MB por foto\.$/, 'This photo is $1. The maximum is 100 MB per photo.'],
    [/^Este vídeo tem (.+?)\. Escolha um vídeo mais curto \(máximo 3 minutos\)\.$/, 'This video is $1. Choose a shorter video (maximum 3 minutes).'],
    [/^Este vídeo tem (.+?)\. O máximo é 3 minutos\.$/, 'This video is $1 long. The maximum is 3 minutes.'],
    [/^Este GIF tem (.+?)\. O máximo para GIF é 10 MB\.$/, 'This GIF is $1. The maximum for GIFs is 10 MB.'],
    [/^Este telemóvel não conseguiu reduzir a foto de (.+?)\. Tente uma foto em JPG ou tire uma captura de ecrã dela\.$/, 'This phone could not reduce the $1 photo. Try a JPG photo or take a screenshot of it.'],
    [/^Mesmo otimizado, o vídeo ficou com (.+?)\. O máximo é 50 MB\.$/, 'Even optimised, the video is $1. The maximum is 50 MB.'],
    [/^O vídeo tem (.+?) e este navegador não conseguiu reduzi-lo\. O máximo para enviar sem otimização é 50 MB\.$/, 'The video is $1 and this browser could not reduce it. The maximum to send without optimisation is 50 MB.'],
    [/^(Empresa|Pessoa) · (.+)$/, function (m, a, r) { return (a === 'Empresa' ? 'Business' : 'Person') + ' · ' + api.t(r); }],
    [/^Operação (.+)$/, 'Operation $1'],
    [/^(.+) · há (\d+) (min|h|d)$/, '$1 · $2 $3 ago'],
    [/^(.+) · agora$/, '$1 · now'],
    [/^· (\d+) mes(es)? · (.+)$/, function (m, n, p, r) { return '· ' + n + (n === '1' ? ' month · ' : ' months · ') + api.t(r); }]
  ];

  var porInicio = {}, porFim = {};
  Object.keys(D).forEach(function (k) {
    if (k.length < 4) return;
    var p = k.split(' ')[0];
    (porInicio[p] = porInicio[p] || []).push(k);
    if (/^[a-zà-ú·—]/.test(k)) { var u = k.split(' ').pop(); (porFim[u] = porFim[u] || []).push(k); }
  });
  Object.keys(porInicio).forEach(function (p) { porInicio[p].sort(function (a, b) { return b.length - a.length; }); });
  Object.keys(porFim).forEach(function (p) { porFim[p].sort(function (a, b) { return b.length - a.length; }); });

  function palavras(s) {   // "segunda às 08:00" → "Monday at 08:00"
    var ok = true;
    var r = s.replace(/[A-Za-zÀ-ú]+/g, function (w) { var x = W[w.toLowerCase()]; if (!x) ok = false; return x || w; });
    return ok ? r : null;
  }
  var cache = Object.create(null);
  function tr(k, fundo) {
    if (k in cache) return cache[k];
    var r = null;
    if (D[k] != null) r = D[k];
    if (r == null) for (var i = 0; i < REGRAS.length; i++) { if (REGRAS[i][0].test(k)) { var r2 = k.replace(REGRAS[i][0], REGRAS[i][1]); if (r2 !== k) { r = r2; break; } } }
    if (r == null && (fundo || 0) < 3) {
      // "Texto conhecido" + resto (ex.: "Não foi possível publicar: <erro>")
      var lst = porInicio[k.split(' ')[0]] || [];
      for (var j = 0; j < lst.length && r == null; j++) {
        var c = lst[j];
        if (!(/[^A-Za-zÀ-ú0-9]$/.test(c) || (c.length >= 14 && c.indexOf(' ') > 0))) continue;
        if (c.length < k.length && k.indexOf(c) === 0 && (/[\s:.,!?·—(…"]/.test(k.charAt(c.length)) || /[^A-Za-zÀ-ú0-9]$/.test(c))) {
          var resto = k.slice(c.length), m = resto.match(/^(\s*)([\s\S]*?)(\s*)$/);
          var rt = m[2] ? (tr(m[2], (fundo || 0) + 1) || palavras(m[2]) || m[2]) : '';
          r = D[c] + m[1] + rt + m[3];
        }
      }
      // resto + "texto conhecido" (ex.: "<nome> foi bloqueado.")
      var lf = porFim[k.split(' ').pop()] || [];
      for (var q = 0; q < lf.length && r == null; q++) {
        var f = lf[q];
        if (f.indexOf(' ') < 0) continue;
        if (f.length < k.length && k.slice(-f.length) === f && /\s$/.test(k.slice(0, -f.length))) r = k.slice(0, -f.length) + D[f];
      }
    }
    cache[k] = r;
    return r;
  }
  api.t = function (s) {
    if (s == null) return s;
    var str = String(s), m = str.match(/^(\s*)([\s\S]*?)(\s*)$/);
    if (!m[2]) return str;
    var k = m[2].replace(/\s+/g, ' ');
    var r = tr(k);
    if (r == null && /\n/.test(m[2])) {   // mensagens com várias linhas (alert/confirm)
      var linhas = m[2].split('\n'), mudou = false;
      linhas = linhas.map(function (l) { var x = l.trim() ? tr(l.trim()) : null; if (x != null) { mudou = true; return x; } return l; });
      if (mudou) r = linhas.join('\n');
    }
    return r == null ? str : m[1] + r + m[3];
  };

  // datas em inglês (o site pede 'pt-PT')
  ['toLocaleDateString', 'toLocaleString', 'toLocaleTimeString'].forEach(function (fn) {
    var orig = Date.prototype[fn];
    Date.prototype[fn] = function (loc, op) { return orig.call(this, (!loc || /^pt/i.test(loc)) ? 'en-GB' : loc, op); };
  });
  // janelas do navegador
  ['alert', 'confirm', 'prompt'].forEach(function (fn) {
    var orig = window[fn];
    window[fn] = function (msg, def) { return orig.call(window, api.t(msg), def); };
  });

  var IGNORAR = /^(SCRIPT|STYLE|TEXTAREA|CODE|PRE|NOSCRIPT)$/;
  var ATRS = ['placeholder', 'title', 'aria-label', 'alt'];
  function ignorado(el) {
    for (var e = el; e && e.nodeType === 1; e = e.parentElement) {
      if (IGNORAR.test(e.tagName) || e.isContentEditable || e.hasAttribute('data-no-i18n')) return true;
    }
    return false;
  }
  function textoNo(n) {
    var v = n.nodeValue;
    if (!v || !/[A-Za-zÀ-ú]/.test(v) || ignorado(n.parentElement)) return;
    var t = api.t(v);
    if (t !== v) n.nodeValue = t;
  }
  function atributos(el) {
    if (el.closest && el.closest('[data-no-i18n]')) return;
    for (var i = 0; i < ATRS.length; i++) {
      var v = el.getAttribute(ATRS[i]);
      if (v) { var t = api.t(v); if (t !== v) el.setAttribute(ATRS[i], t); }
    }
    if (el.tagName === 'INPUT' && /^(button|submit)$/i.test(el.type) && el.value) { var tv = api.t(el.value); if (tv !== el.value) el.value = tv; }
  }
  function percorrer(raiz) {
    if (raiz.nodeType === 3) { textoNo(raiz); return; }
    if (raiz.nodeType !== 1 && raiz.nodeType !== 9 && raiz.nodeType !== 11) return;
    if (raiz.nodeType === 1) { if (ignorado(raiz)) return; atributos(raiz); }
    var w = document.createTreeWalker(raiz, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, null), n;
    while ((n = w.nextNode())) { if (n.nodeType === 3) textoNo(n); else if (n.hasAttribute && (n.hasAttribute('placeholder') || n.hasAttribute('title') || n.hasAttribute('aria-label') || n.hasAttribute('alt') || n.tagName === 'INPUT')) atributos(n); }
  }
  var titulo = function () { var t = api.t(document.title); if (t !== document.title) document.title = t; };

  var obs = new MutationObserver(function (lista) {
    for (var i = 0; i < lista.length; i++) {
      var m = lista[i];
      if (m.type === 'childList') { for (var j = 0; j < m.addedNodes.length; j++) percorrer(m.addedNodes[j]); if (m.target.nodeName === 'TITLE') titulo(); }
      else if (m.type === 'characterData') { textoNo(m.target); if (m.target.parentNode && m.target.parentNode.nodeName === 'TITLE') titulo(); }
      else if (m.type === 'attributes') atributos(m.target);
    }
  });
  obs.observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATRS });
  function inicio() { percorrer(document.body || document.documentElement); titulo(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', inicio); else inicio();
})();
