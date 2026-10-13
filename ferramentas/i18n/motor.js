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
    definir: function (l) { try { localStorage.setItem(CHAVE, l); } catch (e) {} location.reload(); },
    alternar: function () { api.definir(lang === 'en' ? 'pt' : 'en'); },
    t: function (s) { return s; }
  };

  // botão PT / EN nas páginas sem menu (entrar, criar conta, recuperar palavra-passe, vídeos)
  function pilula() {
    if (window.FCMenu || document.getElementById('fc-lang')) return;
    var b = document.createElement('button');
    b.id = 'fc-lang'; b.type = 'button';
    b.setAttribute('data-no-i18n', '');
    b.innerHTML = lang === 'en' ? '🌐 Português' : '🌐 English';
    b.style.cssText = 'position:fixed;right:12px;bottom:12px;z-index:5000;padding:8px 14px;border-radius:999px;border:1px solid rgba(243,198,78,.45);background:rgba(22,22,26,.92);color:#f3c64e;font:600 13px Inter,system-ui,sans-serif;cursor:pointer;box-shadow:0 6px 20px rgba(0,0,0,.35)';
    b.onclick = api.alternar;
    document.body.appendChild(b);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { setTimeout(pilula, 50); });
  else setTimeout(pilula, 50);

  if (lang !== 'en') return;
  document.documentElement.lang = 'en';

  var D = __DICIONARIO__;

  // palavras soltas (horários, dias) para o resto de frases compostas
  var W = { 'segunda': 'Monday', 'terça': 'Tuesday', 'quarta': 'Wednesday', 'quinta': 'Thursday', 'sexta': 'Friday', 'sábado': 'Saturday', 'domingo': 'Sunday',
    'às': 'at', 'amanhã': 'tomorrow', 'hoje': 'today', 'e': 'and', 'dias': 'days', 'dia': 'day', 'meses': 'months', 'mês': 'month', 'em': 'in' };

  var REGRAS = [
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
    if (r == null) for (var i = 0; i < REGRAS.length; i++) { if (REGRAS[i][0].test(k)) { r = k.replace(REGRAS[i][0], REGRAS[i][1]); break; } }
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
