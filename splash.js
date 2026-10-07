/* ============================================================
   Feira Comercial — splash.js
   Animação de entrada com o logótipo (globo + carrinho + moeda).
   Aparece uma vez por sessão, enquanto a página carrega.
   Uso: <script src="splash.js"></script> logo no início do <body>.
   ============================================================ */
(function () {
  var CHAVE = 'fc_splash_visto';
  try { if (sessionStorage.getItem(CHAVE)) return; sessionStorage.setItem(CHAVE, '1'); } catch (e) {}

  var reduzir = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var MINIMO = reduzir ? 600 : 2200;   // tempo mínimo visível (ms)
  var MAXIMO = 4500;                   // nunca fica mais do que isto
  var inicio = Date.now();

  var css = [
    '#fc-splash{position:fixed;inset:0;z-index:2147483647;background:#000;display:flex;flex-direction:column;',
    'align-items:center;justify-content:center;gap:6px;font-family:Inter,"Segoe UI",system-ui,sans-serif;',
    'transition:opacity .45s ease,visibility .45s ease}',
    '#fc-splash.sair{opacity:0;visibility:hidden}',
    '#fc-splash svg{width:min(62vw,280px);height:auto;overflow:visible}',
    '#fc-splash .ouro{stroke:url(#fcOuro);fill:none;stroke-linecap:round;stroke-linejoin:round}',
    /* globo: as linhas desenham-se */
    '#fc-splash .linha{stroke-dasharray:400;stroke-dashoffset:400;animation:fcDesenhar 1.1s ease forwards}',
    '#fc-splash .l2{animation-delay:.15s}#fc-splash .l3{animation-delay:.3s}#fc-splash .l4{animation-delay:.45s}',
    /* meridianos a rodar */
    '#fc-splash .meridiano{transform-box:fill-box;transform-origin:center;animation:fcDesenhar 1.1s ease .45s forwards,fcGirar 2.6s linear 1.2s infinite}',
    '#fc-splash .m2{animation:fcDesenhar 1.1s ease .45s forwards,fcGirar 2.6s linear 1.85s infinite}',
    /* carrinho entra da esquerda */
    '#fc-splash .carrinho{animation:fcEntrar .9s cubic-bezier(.2,.9,.3,1.2) .35s both}',
    '#fc-splash .roda{transform-box:fill-box;transform-origin:center;animation:fcRoda .9s ease-out .35s both}',
    /* moeda cai e roda */
    '#fc-splash .moeda{transform-box:fill-box;transform-origin:center;animation:fcMoeda 1s cubic-bezier(.3,1.4,.5,1) 1s both}',
    /* texto */
    '#fc-splash .nome{font-size:clamp(26px,7vw,40px);font-weight:800;letter-spacing:.5px;margin-top:4px;',
    'background:linear-gradient(100deg,#b8862a 0%,#f3c64e 40%,#fff3c4 50%,#f3c64e 60%,#b8862a 100%);',
    'background-size:250% 100%;-webkit-background-clip:text;background-clip:text;color:transparent;',
    'animation:fcSubir .7s ease 1.1s both,fcBrilho 2.2s linear 1.6s infinite}',
    '#fc-splash .lema{display:flex;gap:10px;color:#e8b53a;font-size:clamp(13px,3.6vw,17px);font-weight:500}',
    '#fc-splash .lema span{opacity:0;animation:fcSubir .5s ease forwards}',
    '#fc-splash .lema span:nth-child(1){animation-delay:1.45s}',
    '#fc-splash .lema span:nth-child(2){animation-delay:1.65s}',
    '#fc-splash .lema span:nth-child(3){animation-delay:1.85s}',
    '#fc-splash .barra{width:min(46vw,190px);height:3px;border-radius:3px;background:rgba(232,181,58,.18);',
    'margin-top:22px;overflow:hidden}',
    '#fc-splash .barra i{display:block;height:100%;width:40%;border-radius:3px;',
    'background:linear-gradient(90deg,transparent,#f3c64e,transparent);animation:fcCarregar 1.1s ease-in-out infinite}',
    '@keyframes fcDesenhar{to{stroke-dashoffset:0}}',
    '@keyframes fcGirar{0%{transform:scaleX(1)}50%{transform:scaleX(-1)}100%{transform:scaleX(1)}}',
    '@keyframes fcEntrar{from{transform:translateX(-140px);opacity:0}to{transform:none;opacity:1}}',
    '@keyframes fcRoda{from{transform:rotate(-540deg)}to{transform:rotate(0)}}',
    '@keyframes fcMoeda{0%{transform:translateY(-70px) scaleX(1);opacity:0}60%{transform:translateY(4px) scaleX(-1);opacity:1}100%{transform:none}}',
    '@keyframes fcSubir{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}',
    '@keyframes fcBrilho{from{background-position:120% 0}to{background-position:-120% 0}}',
    '@keyframes fcCarregar{from{transform:translateX(-110%)}to{transform:translateX(260%)}}',
    '@media (prefers-reduced-motion:reduce){#fc-splash *{animation-duration:.01s!important;animation-delay:0s!important;animation-iteration-count:1!important}}'
  ].join('');

  // grelha do cesto do carrinho
  var grelha = '';
  [58, 72, 86, 100].forEach(function (x) { grelha += '<line x1="' + x + '" y1="98" x2="' + (x - 3) + '" y2="136"/>'; });
  [110, 123].forEach(function (y) { grelha += '<line x1="' + (44 + (y - 98) * 0.27) + '" y1="' + y + '" x2="' + (118 - (y - 98) * 0.2) + '" y2="' + y + '"/>'; });

  var svg =
    '<svg viewBox="0 0 240 190" role="img" aria-label="Feira Comercial">' +
      '<defs><linearGradient id="fcOuro" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="240" y2="190">' +
        '<stop offset="0" stop-color="#f6cc55"/><stop offset=".55" stop-color="#e2a82e"/><stop offset="1" stop-color="#b8862a"/>' +
      '</linearGradient></defs>' +
      // globo
      '<g class="ouro" stroke-width="5">' +
        '<circle class="linha" cx="142" cy="80" r="58"/>' +
        '<line class="linha l2" x1="84" y1="80" x2="200" y2="80"/>' +
        '<line class="linha l3" x1="93" y1="50" x2="191" y2="50"/>' +
        '<line class="linha l3" x1="93" y1="110" x2="191" y2="110"/>' +
        '<line class="linha l4" x1="142" y1="22" x2="142" y2="138"/>' +
        '<ellipse class="linha l4 meridiano" cx="142" cy="80" rx="27" ry="58"/>' +
        '<ellipse class="linha l4 meridiano m2" cx="142" cy="80" rx="46" ry="58"/>' +
      '</g>' +
      // carrinho (com fundo preto para ficar à frente do globo)
      '<g class="carrinho">' +
        '<path d="M44 98 L122 98 L113 140 L56 140 Z" fill="#000"/>' +
        '<g class="ouro" stroke-width="5">' +
          '<path d="M14 84 L34 84 L44 98 L122 98 L113 140 L56 140 L44 98"/>' +
          '<g stroke-width="3.5">' + grelha + '</g>' +
          '<path d="M56 140 L50 154 L118 154"/>' +
        '</g>' +
        '<circle class="roda" cx="62" cy="166" r="8" fill="#000" stroke="url(#fcOuro)" stroke-width="5" stroke-dasharray="8 3"/>' +
        '<circle class="roda" cx="108" cy="166" r="8" fill="#000" stroke="url(#fcOuro)" stroke-width="5" stroke-dasharray="8 3"/>' +
      '</g>' +
      // moeda $
      '<g class="moeda">' +
        '<circle cx="34" cy="46" r="17" fill="url(#fcOuro)"/>' +
        '<text x="34" y="53.5" text-anchor="middle" font-size="22" font-weight="800" font-family="Arial,sans-serif" fill="#000">$</text>' +
      '</g>' +
    '</svg>';

  var el = document.createElement('div');
  el.id = 'fc-splash';
  el.setAttribute('aria-hidden', 'true');
  el.innerHTML = '<style>' + css + '</style>' + svg +
    '<div class="nome">Feira comercial</div>' +
    '<div class="lema"><span>Explore,</span><span>Exiba,</span><span>Expanda</span></div>' +
    '<div class="barra"><i></i></div>';
  (document.body || document.documentElement).appendChild(el);

  var fechado = false;
  function fechar() {
    if (fechado) return;
    fechado = true;
    var falta = Math.max(0, MINIMO - (Date.now() - inicio));
    setTimeout(function () {
      el.classList.add('sair');
      setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 500);
    }, falta);
  }
  if (document.readyState === 'complete') fechar();
  else window.addEventListener('load', fechar);
  setTimeout(fechar, MAXIMO);
  el.addEventListener('click', fechar);   // tocar para saltar
})();
