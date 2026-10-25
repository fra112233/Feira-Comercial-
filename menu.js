/* ============================================================
   Feira Comercial — menu.js
   Menu lateral (botão ☰) com navegação e definições.
   Uso: <script src="menu.js"></script> depois de supabase-config.js,
        e um botão com onclick="FCMenu.abrir()".
   ============================================================ */
window.FCMenu = (function () {
  var css = [
    // cores próprias do menu, escuro ou claro conforme o tema da página (antes usava as variáveis de cada
    // página e, nas Mensagens em tema branco, ficava fundo escuro com letras escuras)
    '#fcm{--fcm-bg:#1e293b;--fcm-tx:#f1f5f9;--fcm-hover:#334155;--fcm-borda:#334155}',
    '#fcm.claro{--fcm-bg:#ffffff;--fcm-tx:#0f172a;--fcm-hover:#f1f5f9;--fcm-borda:#e2e8f0}',
    '#fcm-fundo{position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:5000;opacity:0;visibility:hidden;transition:.25s}',
    '#fcm-fundo.aberto{opacity:1;visibility:visible}',
    '#fcm{position:fixed;top:0;right:0;bottom:0;width:min(330px,88vw);z-index:5001;background:var(--fcm-bg);',
    'color:var(--fcm-tx);transform:translateX(105%);transition:transform .28s ease;display:flex;flex-direction:column;',
    'box-shadow:-8px 0 30px rgba(0,0,0,.3);font-family:Inter,"Segoe UI",system-ui,sans-serif;padding-bottom:env(safe-area-inset-bottom)}',
    '#fcm.aberto{transform:none}',
    '#fcm .cab{display:flex;align-items:center;justify-content:space-between;padding:14px 16px;border-bottom:1px solid var(--fcm-borda)}',
    '#fcm .cab b{font-size:17px}',
    '#fcm .fechar{width:36px;height:36px;border-radius:50%;border:none;background:var(--fcm-hover);color:inherit;font-size:18px;cursor:pointer}',
    '#fcm .corpo{flex:1;overflow-y:auto;padding:8px 0}',
    '#fcm .eu{display:flex;align-items:center;gap:12px;margin:8px 12px 6px;padding:12px;border-radius:14px;background:var(--fcm-hover);text-decoration:none;color:inherit}',
    '#fcm .eu img{width:48px;height:48px;border-radius:50%;object-fit:cover;background:#475569;flex-shrink:0}',
    '#fcm .eu .n{font-weight:700;font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '#fcm .eu .t{font-size:12px;opacity:.75}',
    '#fcm .sec{font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;opacity:.6;padding:14px 20px 6px}',
    '#fcm .it{display:flex;align-items:center;gap:14px;width:100%;padding:12px 20px;border:none;background:none;color:inherit;',
    'font:inherit;font-size:15px;text-align:left;cursor:pointer;text-decoration:none}',
    '#fcm .it:hover,#fcm .it:active{background:var(--fcm-hover)}',
    '#fcm .it i.ic{width:22px;text-align:center;color:var(--primary,#6366f1);font-size:16px}',
    '#fcm .it .dir{margin-left:auto;font-size:12px;opacity:.6}',
    '#fcm .it.perigo,#fcm .it.perigo i.ic{color:#ef4444}',
    '#fcm .sw{margin-left:auto;width:42px;height:24px;border-radius:12px;background:#64748b;position:relative;transition:.2s;flex-shrink:0}',
    '#fcm .sw::after{content:"";position:absolute;top:3px;left:3px;width:18px;height:18px;border-radius:50%;background:#fff;transition:.2s}',
    '#fcm .sw.on{background:#22c55e}#fcm .sw.on::after{left:21px}',
    '#fcm .rodape{padding:12px 20px;font-size:11px;opacity:.5;text-align:center}',
    /* atalhos em grelha (3 por linha) — o menu não cresce para baixo a cada nova página */
    '#fcm .grade{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;padding:6px 12px 4px}',
    '#fcm .tile{position:relative;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;min-height:72px;padding:10px 4px;',
    'border-radius:14px;border:none;background:var(--fcm-hover);color:inherit;font:inherit;font-size:12px;font-weight:600;',
    'text-align:center;line-height:1.15;cursor:pointer;text-decoration:none;transition:transform .12s}',
    '#fcm .tile:active{transform:scale(.96)}#fcm .tile:hover{filter:brightness(1.12)}',
    '#fcm .tile i.ic{font-size:20px;color:var(--primary,#6366f1)}',
    '#fcm .tile .lb{max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
    '#fcm .tile .fc-msg-menu{position:absolute;top:6px;right:6px;margin:0;min-width:20px;height:20px;line-height:20px;font-size:11px;padding:0 6px}',
    '#fcm .tile .fc-aovivo-chip{position:absolute;top:6px;right:6px;margin:0;max-width:calc(100% - 12px);font-size:9.5px;padding:1px 6px}',
    '#fcm .tile .dir{position:absolute;top:6px;right:8px;font-size:10px;opacity:.75;margin:0}',
    /* grupos que abrem e fecham */
    '#fcm details.grupo{margin:2px 0}',
    '#fcm details.grupo>summary{list-style:none}#fcm details.grupo>summary::-webkit-details-marker{display:none}',
    '#fcm details.grupo>summary .seta{margin-left:auto;font-size:12px;opacity:.6;transition:transform .2s}',
    '#fcm details.grupo[open]>summary .seta{transform:rotate(180deg)}',
    '#fcm details.grupo>summary b{font-weight:600}',
    '#fcm details.grupo .dentro .it{padding-left:56px;font-size:14px}',
    '#fcm details.grupo .dentro .it i.ic{display:none}',
    '#fcm .linha{height:1px;background:var(--fcm-borda);margin:8px 16px;opacity:.6}'
  ].join('');

  var montado = false, perfil = null;

  function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'); }

  function temTema() { return typeof window.toggleTheme === 'function' || typeof window.toggleDarkMode === 'function'; }

  function temaEscuro() {
    // perfil.html usa body.light-mode; index.html usa body[data-theme="dark"]
    if (document.body.hasAttribute('data-theme')) return document.body.getAttribute('data-theme') === 'dark';
    return !document.body.classList.contains('light-mode');
  }

  function montar() {
    if (montado) return;
    montado = true;
    var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);
    var fundo = document.createElement('div'); fundo.id = 'fcm-fundo'; fundo.onclick = fechar;
    var m = document.createElement('aside'); m.id = 'fcm'; m.setAttribute('aria-label', 'Menu');
    document.body.appendChild(fundo); document.body.appendChild(m);
    m.addEventListener('toggle', function (e) {
      var d = e.target; if (!d.classList || !d.classList.contains('grupo')) return;
      try { localStorage.setItem('fcm_g_' + d.getAttribute('data-g'), d.open ? '1' : '0'); } catch (x) {}
    }, true);
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') fechar(); });
  }

  function item(icone, texto, acao, extra, classe) {
    var tag = acao.indexOf('.html') > -1 && acao.indexOf('(') === -1 ? 'a' : 'button';
    var attr = tag === 'a' ? 'href="' + acao + '"' : 'onclick="' + acao + '"';
    return '<' + tag + ' class="it ' + (classe || '') + '" ' + attr + '><i class="fas ' + icone + ' ic"></i>' + texto + (extra || '') + '</' + tag + '>';
  }

  function tile(icone, texto, acao, extra) {
    var tag = acao.indexOf('.html') > -1 && acao.indexOf('(') === -1 ? 'a' : 'button';
    var attr = tag === 'a' ? 'href="' + acao + '"' : 'onclick="' + acao + '"';
    return '<' + tag + ' class="tile" ' + attr + '><i class="fas ' + icone + ' ic"></i><span class="lb">' + texto + '</span>' + (extra || '') + '</' + tag + '>';
  }

  // grupos abertos/fechados ficam lembrados neste aparelho
  function grupoAberto(g) { try { return localStorage.getItem('fcm_g_' + g) === '1'; } catch (e) { return false; } }
  function grupo(g, icone, titulo, dentro) {
    return '<details class="grupo" data-g="' + g + '"' + (grupoAberto(g) ? ' open' : '') + '><summary class="it"><i class="fas ' + icone + ' ic"></i><b>' + titulo +
      '</b><i class="fas fa-chevron-down seta"></i></summary><div class="dentro">' + dentro + '</div></details>';
  }

  function mensalidadeTxt(p) {
    if (!window.FC || !FC.mensalidade) return '';
    var m = FC.mensalidade(p);
    if (!m.ate) return '';
    return m.ativa ? '<span class="dir">' + (m.dias <= 5 ? '⚠️ ' : '') + (m.dias <= 0 ? 'termina hoje' : m.dias === 1 ? '1 dia' : m.dias + ' dias') + '</span>' : '<span class="dir" style="color:#ef4444;opacity:1">Expirada</span>';
  }

  function desenhar() {
    var caixa = document.getElementById('fcm'); if (caixa) caixa.classList.toggle('claro', !temaEscuro());
    var p = perfil || {};
    var foto = p.avatar_url || ('https://ui-avatars.com/api/?name=' + encodeURIComponent(p.full_name || 'U') + '&background=random&color=fff&size=128');
    var empresa = p.type === 'empresa';
    var publico = (p.visibility || 'publico') === 'publico';
    var notif = ('Notification' in window) && Notification.permission === 'granted';
    document.getElementById('fcm').innerHTML =
      '<div class="cab"><b>Menu</b><button class="fechar" onclick="FCMenu.fechar()" aria-label="Fechar"><i class="fas fa-times"></i></button></div>' +
      '<div class="corpo">' +
        '<a class="eu" href="perfil.html"><img src="' + esc(foto) + '" alt=""><div style="min-width:0"><div class="n">' + esc(p.full_name || 'O meu perfil') + '</div>' +
          '<div class="t">' + (empresa ? '<i class="fas fa-building"></i> Empresa' : '<i class="fas fa-user"></i> Pessoa') + ' · ver o meu perfil</div></div></a>' +

        '<div class="grade">' +
          tile('fa-home', 'Início', 'index.html') +
          ((window.FC && FC.abrirNotificacoes) ? tile('fa-bell', 'Notificações', 'FC.abrirNotificacoes()',
            '<span class="fc-msg-menu" data-fc-notif style="' + (FC._notifNaoLidas ? '' : 'display:none') + '">' + (FC._notifNaoLidas > 99 ? '99+' : (FC._notifNaoLidas || '')) + '</span>') : '') +
          tile('fa-user-friends', 'Amigos', 'amigos.html') +
          tile('fa-comment-dots', 'Mensagens', 'mensagen.html',
            '<span data-fc-msgs class="fc-msg-menu" style="' + ((window.FC && FC._msgsNaoLidas) ? '' : 'display:none') + '">' + ((window.FC && FC._msgsNaoLidas) > 99 ? '99+' : ((window.FC && FC._msgsNaoLidas) || '')) + '</span>') +
          tile('fa-play-circle', 'Vídeos', 'videos.html') +
          tile('fa-magnifying-glass', 'Produtos', 'produtos.html') +
          tile('fa-bullhorn', 'Anúncios', 'anuncio.html') +
          tile('fa-tower-broadcast', 'Live', 'live.html', (window.FC && FC._livesAgora && FC._livesAgora.length)
            ? '<span class="fc-aovivo-chip"><span class="fc-aovivo-ponto"></span>' + (FC._livesAgora.length === 1 ? 'AO VIVO' : FC._livesAgora.length + ' ao vivo') + '</span>' : '') +
          (empresa ? tile('fa-chart-column', 'Estatísticas', 'estatisticas.html') : '') +
          (empresa ? tile('fa-credit-card', 'Mensalidade', 'mensalidade.html', mensalidadeTxt(p)) : '') +
          (empresa ? tile('fa-file-invoice', 'Recibos', 'recibos.html') : '') +
          (p.role === 'admin' ? tile('fa-user-shield', 'Administração', 'admin.html') : p.role === 'ajudante' ? tile('fa-headset', 'Ajuda da Equipa', 'admin.html') : '') +
        '</div>' +
        '<div class="linha"></div>' +

        grupo('conta', 'fa-gear', 'Definições e privacidade',
          item('fa-pen', 'Editar perfil', 'FCMenu.editarPerfil()') +
          item('fa-key', 'Alterar palavra-passe', 'password.html') +
          item('fa-shield-halved', 'Privacidade e segurança', 'privacidade.html') +
          (temTema() ? item(temaEscuro() ? 'fa-moon' : 'fa-sun', 'Modo escuro', 'FCMenu.tema()', '<span class="sw ' + (temaEscuro() ? 'on' : '') + '" id="fcm-sw-tema"></span>') : '') +
          item('fa-eye', 'Perfil visível na pesquisa', 'FCMenu.visibilidade()', '<span class="sw ' + (publico ? 'on' : '') + '" id="fcm-sw-vis"></span>') +
          item('fa-language', 'Idioma / Language', 'FCI18N.alternar()', '<b style="margin-left:auto;font-size:12px;padding:2px 8px;border-radius:999px;border:1px solid currentColor;opacity:.8">' + ((window.FCI18N && FCI18N.lang === 'en') ? 'EN' : 'PT') + '</b>') +
          item('fa-mobile-screen', 'Avisos no telemóvel', 'FCMenu.notificacoes()', '<span class="sw ' + (notif ? 'on' : '') + '" id="fcm-sw-not"></span>')) +

        grupo('ajuda', 'fa-circle-question', 'Ajuda e informações',
          ((window.FC && FC.appInstalada && !FC.appInstalada()) ? item('fa-download', 'Instalar aplicação', 'FCMenu.instalar()') : '') +
          item('fa-circle-info', 'Sobre a Feira Comercial', 'about.html') +
          item('fa-shield-halved', 'Políticas e privacidade', 'politicas.html') +
          item('fa-flag', 'Reclamações e sugestões', 'reclamacao.html')) +

        '<div style="height:8px"></div>' +
        item('fa-sign-out-alt', 'Sair', 'FCMenu.sair()', '', 'perigo') +
      '</div>' +
      '<div class="rodape">Feira Comercial · Explore, Exiba, Expanda</div>';
  }

  async function abrir() {
    montar();
    try { perfil = JSON.parse(localStorage.getItem('fc_profile') || 'null') || perfil; } catch (e) {}
    desenhar();
    document.getElementById('fcm-fundo').classList.add('aberto');
    document.getElementById('fcm').classList.add('aberto');
    document.body.style.overflow = 'hidden';
    if (window.FC && FC.loadMyProfile) {
      try { var p = await FC.loadMyProfile(); if (p) { perfil = p; desenhar(); } } catch (e) {}
    }
  }

  function fechar() {
    var m = document.getElementById('fcm'); if (!m) return;
    m.classList.remove('aberto');
    document.getElementById('fcm-fundo').classList.remove('aberto');
    document.body.style.overflow = '';
  }

  function aviso(t) {
    if (typeof window.showToast === 'function') return window.showToast(t);
    if (typeof window.toast === 'function') return window.toast(t);
    alert(t);
  }

  function tema() {
    if (typeof window.toggleTheme === 'function') window.toggleTheme();
    else if (typeof window.toggleDarkMode === 'function') window.toggleDarkMode();
    var sw = document.getElementById('fcm-sw-tema'); if (sw) sw.classList.toggle('on', temaEscuro());
    var caixa = document.getElementById('fcm'); if (caixa) caixa.classList.toggle('claro', !temaEscuro());
  }

  async function visibilidade() {
    if (!perfil || typeof supabaseClient === 'undefined') return;   // supabaseClient é 'const' global (não fica em window)
    var novo = (perfil.visibility || 'publico') === 'publico' ? 'privado' : 'publico';
    var r = await supabaseClient.from('perfis').update({ visibility: novo }).eq('id', perfil.id);
    if (r.error) { aviso('Erro: ' + FC.traduzirErro(r.error)); return; }
    perfil.visibility = novo;
    try { var c = JSON.parse(localStorage.getItem('fc_profile') || 'null'); if (c) { c.visibility = novo; localStorage.setItem('fc_profile', JSON.stringify(c)); } } catch (e) {}
    document.getElementById('fcm-sw-vis').classList.toggle('on', novo === 'publico');
    aviso(novo === 'publico' ? 'O seu perfil aparece na pesquisa de Amigos.' : 'O seu perfil deixou de aparecer em "Descobrir".');
  }

  async function notificacoes() {
    if (!('Notification' in window)) { aviso('Este navegador não suporta notificações.'); return; }
    if (Notification.permission === 'denied') { aviso('As notificações foram bloqueadas. Ative-as nas definições do navegador (cadeado ao lado do endereço).'); return; }
    if (Notification.permission === 'granted') {
      if (window.FC && FC.ativarPush) await FC.ativarPush(false);
      aviso('Os avisos estão ligados. Para desligar, use as definições do navegador.'); return;
    }
    var ok = (window.FC && FC.ativarPush) ? await FC.ativarPush(true) : (await Notification.requestPermission()) === 'granted';
    document.getElementById('fcm-sw-not').classList.toggle('on', !!ok);
    if (ok) aviso('Avisos ligados! Vai recebê-los mesmo com a aplicação fechada.');
  }

  function editarPerfil() {
    fechar();
    if (location.pathname.indexOf('perfil.html') > -1 && !new URLSearchParams(location.search).get('id') && typeof window.openModal === 'function') openModal('modalEdit');
    else location.href = 'perfil.html#editar';
  }

  function sair() {
    if (!confirm('Sair da conta?')) return;
    if (window.FC && FC.signOut) FC.signOut(); else location.href = 'Portal.html';
  }

  function instalar() { fechar(); if (window.FC && FC.instalarApp) FC.instalarApp(); }

  return { instalar: instalar, abrir: abrir, fechar: fechar, tema: tema, visibilidade: visibilidade, notificacoes: notificacoes, editarPerfil: editarPerfil, sair: sair };
})();
