/* ============================================================
   Feira Comercial — menu.js
   Menu lateral (botão ☰) com navegação e definições.
   Uso: <script src="menu.js"></script> depois de supabase-config.js,
        e um botão com onclick="FCMenu.abrir()".
   ============================================================ */
window.FCMenu = (function () {
  var css = [
    '#fcm-fundo{position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:5000;opacity:0;visibility:hidden;transition:.25s}',
    '#fcm-fundo.aberto{opacity:1;visibility:visible}',
    '#fcm{position:fixed;top:0;right:0;bottom:0;width:min(330px,88vw);z-index:5001;background:var(--bg-secondary,var(--bg-card,var(--surface,#1e293b)));',
    'color:var(--text-primary,var(--text-main,var(--text,#f1f5f9)));transform:translateX(105%);transition:transform .28s ease;display:flex;flex-direction:column;',
    'box-shadow:-8px 0 30px rgba(0,0,0,.3);font-family:Inter,"Segoe UI",system-ui,sans-serif;padding-bottom:env(safe-area-inset-bottom)}',
    '#fcm.aberto{transform:none}',
    '#fcm .cab{display:flex;align-items:center;justify-content:space-between;padding:14px 16px;border-bottom:1px solid var(--border-color,var(--border,#334155))}',
    '#fcm .cab b{font-size:17px}',
    '#fcm .fechar{width:36px;height:36px;border-radius:50%;border:none;background:var(--bg-tertiary,var(--hover-bg,var(--hover,#334155)));color:inherit;font-size:18px;cursor:pointer}',
    '#fcm .corpo{flex:1;overflow-y:auto;padding:8px 0}',
    '#fcm .eu{display:flex;align-items:center;gap:12px;margin:8px 12px 6px;padding:12px;border-radius:14px;background:var(--bg-tertiary,var(--hover-bg,var(--hover,#334155)));text-decoration:none;color:inherit}',
    '#fcm .eu img{width:48px;height:48px;border-radius:50%;object-fit:cover;background:#475569;flex-shrink:0}',
    '#fcm .eu .n{font-weight:700;font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '#fcm .eu .t{font-size:12px;opacity:.75}',
    '#fcm .sec{font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;opacity:.6;padding:14px 20px 6px}',
    '#fcm .it{display:flex;align-items:center;gap:14px;width:100%;padding:12px 20px;border:none;background:none;color:inherit;',
    'font:inherit;font-size:15px;text-align:left;cursor:pointer;text-decoration:none}',
    '#fcm .it:hover,#fcm .it:active{background:var(--bg-tertiary,var(--hover-bg,var(--hover,#334155)))}',
    '#fcm .it i.ic{width:22px;text-align:center;color:var(--primary,#6366f1);font-size:16px}',
    '#fcm .it .dir{margin-left:auto;font-size:12px;opacity:.6}',
    '#fcm .it.perigo,#fcm .it.perigo i.ic{color:#ef4444}',
    '#fcm .sw{margin-left:auto;width:42px;height:24px;border-radius:12px;background:#64748b;position:relative;transition:.2s;flex-shrink:0}',
    '#fcm .sw::after{content:"";position:absolute;top:3px;left:3px;width:18px;height:18px;border-radius:50%;background:#fff;transition:.2s}',
    '#fcm .sw.on{background:#22c55e}#fcm .sw.on::after{left:21px}',
    '#fcm .rodape{padding:12px 20px;font-size:11px;opacity:.5;text-align:center}'
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
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') fechar(); });
  }

  function item(icone, texto, acao, extra, classe) {
    var tag = acao.indexOf('.html') > -1 && acao.indexOf('(') === -1 ? 'a' : 'button';
    var attr = tag === 'a' ? 'href="' + acao + '"' : 'onclick="' + acao + '"';
    return '<' + tag + ' class="it ' + (classe || '') + '" ' + attr + '><i class="fas ' + icone + ' ic"></i>' + texto + (extra || '') + '</' + tag + '>';
  }

  function desenhar() {
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

        '<div class="sec">Navegar</div>' +
        item('fa-home', 'Início', 'index.html') +
        item('fa-user-friends', 'Amigos', 'amigos.html') +
        item('fa-comment-dots', 'Mensagens', 'mensagen.html') +
        item('fa-play-circle', 'Vídeos', 'videos.html') +
        item('fa-bullhorn', 'Anúncios', 'anuncio.html') +
        item('fa-photo-film', 'Biblioteca', 'fotoVidio.html') +

        '<div class="sec">Conta</div>' +
        item('fa-pen', 'Editar perfil', 'FCMenu.editarPerfil()') +
        item('fa-key', 'Alterar palavra-passe', 'password.html') +

        '<div class="sec">Definições</div>' +
        (temTema() ? item(temaEscuro() ? 'fa-moon' : 'fa-sun', 'Modo escuro', 'FCMenu.tema()', '<span class="sw ' + (temaEscuro() ? 'on' : '') + '" id="fcm-sw-tema"></span>') : '') +
        item('fa-eye', 'Perfil visível na pesquisa', 'FCMenu.visibilidade()', '<span class="sw ' + (publico ? 'on' : '') + '" id="fcm-sw-vis"></span>') +
        item('fa-bell', 'Notificações de mensagens', 'FCMenu.notificacoes()', '<span class="sw ' + (notif ? 'on' : '') + '" id="fcm-sw-not"></span>') +

        '<div class="sec">Ajuda</div>' +
        item('fa-circle-info', 'Sobre a Feira Comercial', 'about.html') +
        item('fa-shield-halved', 'Políticas e privacidade', 'politicas.html') +
        item('fa-flag', 'Reclamações e sugestões', 'reclamacao.html') +

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
  }

  async function visibilidade() {
    if (!perfil || !window.supabaseClient) return;
    var novo = (perfil.visibility || 'publico') === 'publico' ? 'privado' : 'publico';
    var r = await supabaseClient.from('perfis').update({ visibility: novo }).eq('id', perfil.id);
    if (r.error) { aviso('Erro: ' + r.error.message); return; }
    perfil.visibility = novo;
    try { var c = JSON.parse(localStorage.getItem('fc_profile') || 'null'); if (c) { c.visibility = novo; localStorage.setItem('fc_profile', JSON.stringify(c)); } } catch (e) {}
    document.getElementById('fcm-sw-vis').classList.toggle('on', novo === 'publico');
    aviso(novo === 'publico' ? 'O teu perfil aparece na pesquisa de Amigos.' : 'O teu perfil deixou de aparecer em "Descobrir".');
  }

  async function notificacoes() {
    if (!('Notification' in window)) { aviso('Este navegador não suporta notificações.'); return; }
    if (Notification.permission === 'granted') { aviso('Para desligar, use as definições do navegador (cadeado ao lado do endereço).'); return; }
    if (Notification.permission === 'denied') { aviso('As notificações foram bloqueadas. Ative-as nas definições do navegador.'); return; }
    var r = await Notification.requestPermission();
    document.getElementById('fcm-sw-not').classList.toggle('on', r === 'granted');
    if (r === 'granted') aviso('Notificações ligadas!');
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

  return { abrir: abrir, fechar: fechar, tema: tema, visibilidade: visibilidade, notificacoes: notificacoes, editarPerfil: editarPerfil, sair: sair };
})();
