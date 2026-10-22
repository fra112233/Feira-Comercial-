/* ============================================================
   Feira Comercial — atualizacao.js
   Garante que quem tem o site aberto (ou guardado em cache no
   telemóvel) recebe as novas versões sem ter de limpar nada.

   Como funciona:
   - Cada deploy no Vercel gera version.json com o código do commit.
   - Ao abrir a página guarda-se a versão atual.
   - Ao voltar ao separador / app e a cada 5 minutos, compara-se com
     o version.json do servidor. Se mudou:
       * ao regressar à página: recarrega sozinha (exceto na Live ou
         se houver texto a meio de escrever);
       * caso contrário: mostra o aviso "Nova versão — Atualizar".
   Uso: <script src="atualizacao.js"></script> em todas as páginas.
   ============================================================ */
(function () {
  if (window.FCAtualizacao) return;

  var INTERVALO = 5 * 60 * 1000;
  var versaoInicial = null;
  var aviso = null;
  var aCarregar = false;

  function obterVersao() {
    return fetch('/version.json?t=' + Date.now(), { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) { return j && j.versao ? String(j.versao) : null; })
      .catch(function () { return null; });
  }

  // Não recarregar sozinho se isso fizer a pessoa perder alguma coisa.
  function podeRecarregarSozinho() {
    if (/live\.html$/i.test(location.pathname)) return false;
    var campos = document.querySelectorAll('textarea, input[type="text"], input:not([type])');
    for (var i = 0; i < campos.length; i++) {
      if (campos[i].value && campos[i].value.trim() && !campos[i].readOnly &&
          campos[i].type !== 'search') return false;
    }
    return true;
  }

  // a página pode ter vindo da cópia guardada no telemóvel (sw.js): antes de recarregar,
  // limpa-se essa cópia para vir mesmo a versão nova
  // Só as páginas e o código do próprio site (html/js/css). As bibliotecas (Supabase, ícones,
  // letras) e as imagens ficam guardadas — antes apagava-se tudo e, depois de uma atualização,
  // o telemóvel tinha de descarregar outra vez centenas de kB antes de mostrar a página.
  function limparCopia() {
    try {
      if (!window.caches) return Promise.resolve();
      var meu = location.origin;
      return caches.keys().then(function (ks) {
        return Promise.all(ks.filter(function (k) { return k.indexOf('fc-site') === 0; }).map(function (k) {
          return caches.open(k).then(function (c) {
            return c.keys().then(function (pedidos) {
              return Promise.all(pedidos.filter(function (r) {
                var u = new URL(r.url);
                return u.origin === meu && (u.pathname === '/' || /\.(html|js|css)$/i.test(u.pathname));
              }).map(function (r) { return c.delete(r); }));
            });
          });
        }));
      }).catch(function () {});
    } catch (e) { return Promise.resolve(); }
  }
  // pede ao service worker para pôr a cópia em dia (só descarrega o que mudou); se não
  // responder a tempo (telemóvel com o service worker antigo), apaga-se a cópia do código
  function atualizarCopia() {
    return new Promise(function (feito) {
      var acabou = false;
      function fim(ok) { if (acabou) return; acabou = true; feito(ok); }
      setTimeout(function () { fim(false); }, 8000);
      try {
        if (!navigator.serviceWorker) return fim(false);
        navigator.serviceWorker.getRegistration().then(function (reg) {
          var sw = reg && reg.active;
          if (!sw) return fim(false);
          var canal = new MessageChannel();
          canal.port1.onmessage = function (e) { fim(e.data === 'ok'); };
          sw.postMessage({ tipo: 'fc-atualizar' }, [canal.port2]);
        }, function () { fim(false); });
      } catch (e) { fim(false); }
    });
  }
  function recarregar() {
    if (aCarregar) return;
    aCarregar = true;
    var ir = function () { location.reload(); };
    atualizarCopia().then(function (ok) { return ok ? null : limparCopia(); }).then(ir, ir);
  }

  function mostrarAviso() {
    if (aviso) return;
    var css = document.createElement('style');
    css.textContent =
      '#fc-atualizar{position:fixed;left:50%;bottom:calc(16px + env(safe-area-inset-bottom));transform:translateX(-50%);' +
      'z-index:9999;display:flex;align-items:center;gap:12px;max-width:calc(100vw - 32px);padding:10px 10px 10px 16px;' +
      'border-radius:14px;background:#18181b;color:#f4f4f5;box-shadow:0 8px 30px rgba(0,0,0,.35);' +
      'font:500 14px/1.3 Inter,"Segoe UI",system-ui,sans-serif;border:1px solid rgba(243,198,78,.35)}' +
      '#fc-atualizar button{border:none;border-radius:10px;padding:9px 14px;font:700 14px Inter,system-ui,sans-serif;cursor:pointer}' +
      '#fc-atualizar .sim{background:#f3c64e;color:#18181b}' +
      '#fc-atualizar .nao{background:transparent;color:#a1a1aa;padding:9px 6px}';
    document.head.appendChild(css);

    aviso = document.createElement('div');
    aviso.id = 'fc-atualizar';
    aviso.setAttribute('role', 'status');
    aviso.innerHTML =
      '<span>Há uma nova versão da Feira Comercial.</span>' +
      '<button class="sim" type="button">Atualizar</button>' +
      '<button class="nao" type="button" aria-label="Mais tarde">✕</button>';
    aviso.querySelector('.sim').onclick = recarregar;
    aviso.querySelector('.nao').onclick = function () { aviso.style.display = 'none'; };
    document.body.appendChild(aviso);
  }

  function lerGuardada() { try { return localStorage.getItem('fc_versao'); } catch (e) { return null; } }
  function guardar(v) { try { localStorage.setItem('fc_versao', v); } catch (e) {} }

  function verificar(aoRegressar) {
    return obterVersao().then(function (v) {
      if (!v) return;
      if (!versaoInicial) {
        // primeira verificação desta página: se a última versão vista neste telemóvel é outra,
        // esta página pode ter vindo da cópia antiga → limpa e recarrega (uma vez)
        var antes = lerGuardada();
        guardar(v);
        versaoInicial = v;
        var jaTentou = false;
        try { jaTentou = sessionStorage.getItem('fc_recarregou') === v; } catch (e) {}
        if (antes && antes !== v && !jaTentou && navigator.serviceWorker && navigator.serviceWorker.controller) {
          try { sessionStorage.setItem('fc_recarregou', v); } catch (e) {}
          if (podeRecarregarSozinho()) recarregar(); else if (document.body) mostrarAviso();
        }
        return;
      }
      if (v !== versaoInicial) guardar(v);
      if (v === versaoInicial) return;
      if (aoRegressar && podeRecarregarSozinho()) recarregar();
      else if (document.body) mostrarAviso();
    });
  }

  verificar(false);
  setInterval(function () {
    if (document.visibilityState === 'visible') verificar(false);
  }, INTERVALO);

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') verificar(true);
  });

  // Página restaurada do histórico do navegador (botão voltar, app reaberta)
  window.addEventListener('pageshow', function (e) {
    if (e.persisted) verificar(true);
  });

  window.FCAtualizacao = { verificar: verificar };
})();
