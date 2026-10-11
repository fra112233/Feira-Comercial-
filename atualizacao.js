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

  function recarregar() {
    if (aCarregar) return;
    aCarregar = true;
    location.reload();
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

  function verificar(aoRegressar) {
    return obterVersao().then(function (v) {
      if (!v) return;
      if (!versaoInicial) { versaoInicial = v; return; }
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
