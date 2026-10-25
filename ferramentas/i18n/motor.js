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

  // O dicionário e o tradutor (i18n-en.js, ~110 KB) só se descarregam para quem usa o site em inglês.
  // Em português, cada página carrega só este ficheiro pequeno.
  var src = 'i18n-en.js';
  if (document.readyState === 'loading') document.write('<script src="' + src + '"><\/script>');   // carrega já, antes do resto da página
  else { var s = document.createElement('script'); s.src = src; (document.head || document.documentElement).appendChild(s); }
})();
