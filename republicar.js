/* ============================================================
   Feira Comercial — republicar.js
   ↻ Republicar: a empresa volta a pôr no topo uma publicação sua, com as mesmas
   fotos/vídeos (já guardados: publica na hora, sem enviar nada). O texto pode mudar.
   As publicações ficam 4 dias no feed; depois disso, o dono pode voltar a pô-las no topo.
   O servidor (migrações 069/070) só deixa as próprias, quando já saíram do feed (4 dias desde
   a última vez), e não deixa trocar as fotos/vídeos. O botão aparece na galeria "Mídia" do meu perfil.

   FCRepublicar.DIAS                         → 4 (dias que a publicação fica no feed)
   FCRepublicar.botao(postId, compacto)      → HTML do botão (pôr dentro da mídia, que tem position:relative)
   FCRepublicar.abrir(post, { aoTerminar })  → post = { id, text, timestamp, media:[{url,type}] }
   ============================================================ */
(function () {
  if (window.FCRepublicar) return;
  const T = s => (window.FC && FC.t) ? FC.t(s) : s;
  const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const U = u => (window.FC && FC.u) ? FC.u(u) : u;
  const sb = () => window.supabaseClient || (window.FC && FC.sb) || null;
  const aviso = (t, x, o) => (window.FCMedia && FCMedia.aviso) ? FCMedia.aviso(t, x, o) : alert(t + '\n\n' + x);

  const css = document.createElement('style');
  css.textContent =
    '.btn-republicar{position:absolute;left:10px;top:10px;z-index:3;display:inline-flex;align-items:center;gap:6px;padding:7px 12px;border:0;border-radius:999px;' +
    'background:rgba(0,0,0,.62);color:#fff;font:inherit;font-size:12.5px;font-weight:700;cursor:pointer;backdrop-filter:blur(4px);-webkit-backdrop-filter:blur(4px);box-shadow:0 2px 8px rgba(0,0,0,.25)}' +
    '.btn-republicar i{color:#f3c64e}.btn-republicar:active{transform:scale(.96)}' +
    '.btn-republicar.compacto{left:6px;top:6px;padding:5px 9px;font-size:11.5px;gap:4px}' +
    '#modal-republicar{position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,.55);display:flex;align-items:flex-end;justify-content:center}' +
    '#modal-republicar .cx{width:100%;max-width:460px;background:var(--bg-card,var(--bg-secondary,#1e293b));color:var(--text-main,var(--text-primary,#f1f5f9));border-radius:18px 18px 0 0;padding:18px 16px calc(18px + env(safe-area-inset-bottom))}' +
    '@media(min-width:600px){#modal-republicar{align-items:center}#modal-republicar .cx{border-radius:18px}}' +
    '#modal-republicar h3{margin:0 0 4px;font-size:18px}#modal-republicar p{margin:0 0 12px;font-size:13px;color:var(--text-secondary,var(--text-tertiary,#94a3b8))}' +
    '#modal-republicar .mr-midia{display:flex;gap:6px;overflow-x:auto;margin-bottom:10px}' +
    '#modal-republicar .mr-midia img,#modal-republicar .mr-midia video{width:76px;height:76px;object-fit:cover;border-radius:10px;flex:none;background:#000}' +
    '#modal-republicar label{display:block;font-size:12px;font-weight:700;color:var(--text-secondary,var(--text-tertiary,#94a3b8));margin:6px 0 4px}' +
    '#modal-republicar textarea{width:100%;box-sizing:border-box;min-height:90px;padding:10px;border-radius:10px;border:1px solid var(--border,var(--border-color,#334155));background:var(--bg-body,var(--bg-primary,transparent));color:inherit;font:inherit;font-size:15px;resize:vertical}' +
    '#modal-republicar .bts{display:flex;gap:8px;margin-top:14px}#modal-republicar .bts button{flex:1;padding:12px;border-radius:12px;border:0;font:inherit;font-weight:700;cursor:pointer}' +
    '#modal-republicar .bts .nao{background:var(--hover-bg,rgba(127,127,127,.15));color:inherit}#modal-republicar .bts .ok{background:var(--primary,#e94560);color:#fff}#modal-republicar .bts .ok:disabled{opacity:.6}';
  document.head.appendChild(css);

  const DIAS = 4;
  function botao(id, compacto) {
    return '<button type="button" class="btn-republicar' + (compacto ? ' compacto' : '') + '" onclick="event.stopPropagation();FCRepublicar._clique(' + Number(id) + ')" title="' +
      esc(T('Voltar a pôr esta publicação no topo, com as mesmas fotos e vídeos')) + '"><i class="fas fa-rotate-right"></i> ' + esc(T('Republicar')) + '</button>';
  }

  // cada página regista como encontrar a publicação pelo id e o que fazer depois
  let procurar = () => null, depois = () => {};
  function ligar(fnProcurar, fnDepois) { procurar = fnProcurar; depois = fnDepois || (() => {}); }
  function _clique(id) { const p = procurar(id); if (p) abrir(p); }

  function abrir(p) {
    const agora = (window.FC && FC.agora) ? FC.agora() : Date.now();
    if (agora - p.timestamp < DIAS * 864e5) {
      const quando = new Date(p.timestamp + DIAS * 864e5).toLocaleDateString('pt-PT', { day: '2-digit', month: '2-digit' });
      aviso(T('Ainda está no feed'), T('Esta publicação ainda aparece no feed (as publicações ficam 4 dias). Pode voltar a pô-la no topo a partir de') + ' ' + quando + '.', { icone: 'fa-rotate-right' });
      return;
    }
    const velho = document.getElementById('modal-republicar'); if (velho) velho.remove();
    const m = document.createElement('div'); m.id = 'modal-republicar';
    m.innerHTML = '<div class="cx" role="dialog" aria-modal="true"><h3>↻ ' + esc(T('Republicar')) + '</h3>' +
      '<p>' + esc(T('Volta ao topo do feed com as mesmas fotos e vídeos. Já estão guardados, por isso publica na hora.')) + '</p>' +
      '<div class="mr-midia">' + (p.media || []).slice(0, 6).map(x => x.type === 'video'
        ? '<video src="' + esc(U(x.url)) + '#t=0.5" muted playsinline preload="metadata"></video>' : '<img src="' + esc(U(x.url)) + '" alt="">').join('') + '</div>' +
      '<label for="mr-texto">' + esc(T('Texto (pode mudar, por exemplo o preço)')) + '</label>' +
      '<textarea id="mr-texto" maxlength="5000" data-no-i18n></textarea>' +
      '<div class="bts"><button type="button" class="nao">' + esc(T('Cancelar')) + '</button><button type="button" class="ok">' + esc(T('Republicar')) + '</button></div></div>';
    document.body.appendChild(m);
    m.querySelector('#mr-texto').value = p.text || '';
    const fechar = () => m.remove();
    m.querySelector('.nao').onclick = fechar;
    m.addEventListener('click', e => { if (e.target === m) fechar(); });
    const ok = m.querySelector('.ok');
    ok.onclick = async () => {
      ok.disabled = true;
      const cli = sb();
      const { data: s } = await cli.auth.getSession();
      const eu = s && s.session && s.session.user && s.session.user.id;
      const texto = m.querySelector('#mr-texto').value.trim();
      const foto = (p.media || []).find(x => x.type === 'image');
      const { error } = await cli.from('posts').insert({
        user_id: eu, content: texto || null, republicado_de: p.id,
        media: p.media || [], image_url: foto ? foto.url : null });   // o servidor confirma e usa as originais
      ok.disabled = false;
      if (error) {
        const msg = (error.message || '').replace(/^.*?: /, '');
        aviso(T('Não foi possível republicar'), /row-level security/i.test(error.message || '')
          ? T('Mensalidade em atraso: só empresas com a mensalidade em dia podem publicar.') : (msg || T('Tente outra vez.')), { erro: true });
        return;
      }
      fechar();
      try { await depois(p); } catch (e) {}
      if (window.FC && FC.toast) FC.toast('✅ ' + T('Publicação de volta ao topo'));
    };
  }

  window.FCRepublicar = { DIAS, botao, abrir, ligar, _clique };
})();
