/* ============================================================
   Feira Comercial — verificar.js
   No MEU perfil de empresa: pedir a coroa dourada 👑 (loja verificada).
   Envia documento (com marca de água) + foto da loja tirada na hora, com carimbo de data, hora e
   localização (estilo Timestamp) + telefone. Os ficheiros ficam privados
   (só a Equipa vê). Mostra o estado: em análise, recusado (com motivo) ou verificada.
   ============================================================ */
(function () {
  if (window.FCVerificar) return;
  const T = s => (window.FC && FC.t) ? FC.t(s) : s;
  const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  let perfil = null;

  const css = document.createElement('style');
  css.textContent =
    '.vr-cartao{margin:10px auto 4px;max-width:420px;border-radius:14px;padding:12px 14px;display:flex;gap:12px;align-items:center;text-align:left;font-size:14px;line-height:1.4}' +
    '.vr-cartao .ic{font-size:22px;flex-shrink:0}.vr-cartao b{display:block}.vr-cartao small{color:var(--text-tertiary,#94a3b8);font-size:12.5px}' +
    '.vr-cartao.convite{background:linear-gradient(135deg,rgba(243,198,78,.16),rgba(243,198,78,.05));border:1px solid rgba(243,198,78,.45)}' +
    '.vr-cartao.analise{background:rgba(96,165,250,.1);border:1px solid rgba(96,165,250,.35)}' +
    '.vr-cartao.recusa{background:rgba(248,113,113,.08);border:1px solid rgba(248,113,113,.35)}' +
    '.vr-cartao.ok{background:rgba(243,198,78,.1);border:1px solid rgba(243,198,78,.4)}' +
    '.vr-bt{margin-left:auto;flex-shrink:0;padding:9px 14px;border-radius:10px;border:0;background:#f3c64e;color:#111;font:700 13.5px inherit;font-family:inherit;cursor:pointer}' +
    '#vr-modal{position:fixed;inset:0;z-index:7000;background:rgba(0,0,0,.6);display:flex;align-items:flex-end;justify-content:center}' +
    '@media(min-width:640px){#vr-modal{align-items:center}}' +
    '#vr-modal .cx{background:var(--bg-secondary,#1e293b);color:var(--text-primary,#f1f5f9);width:100%;max-width:460px;max-height:92vh;overflow:auto;border-radius:20px 20px 0 0;padding:20px 18px calc(18px + env(safe-area-inset-bottom))}' +
    '@media(min-width:640px){#vr-modal .cx{border-radius:20px}}' +
    '#vr-modal h3{margin:0 0 4px;font-size:19px}#vr-modal p.s{margin:0 0 14px;color:var(--text-tertiary,#94a3b8);font-size:13.5px;line-height:1.45}' +
    '#vr-modal label{display:block;font-size:13px;font-weight:700;margin:12px 0 6px}' +
    '#vr-modal select,#vr-modal input[type=tel]{width:100%;padding:11px 12px;border-radius:10px;border:1px solid var(--border-color,#334155);background:var(--bg-primary,#0f172a);color:inherit;font:inherit;font-size:15px}' +
    '.vr-fich{display:flex;gap:10px;align-items:center;padding:12px;border:1.5px dashed var(--border-color,#334155);border-radius:12px;cursor:pointer;font-size:14px}' +
    '.vr-fich img{width:46px;height:46px;border-radius:8px;object-fit:cover;display:none}.vr-fich.tem{border-style:solid;border-color:#10b981}.vr-fich.tem img{display:block}' +
    '.vr-fich i{font-size:20px;color:#f3c64e;width:46px;text-align:center}.vr-fich.tem i{display:none}' +
    '.vr-priv{margin-top:14px;font-size:12.5px;color:var(--text-tertiary,#94a3b8);display:flex;gap:8px;line-height:1.4}' +
    '.vr-acoes{display:flex;gap:10px;margin-top:16px}.vr-acoes button{flex:1;padding:13px;border-radius:12px;border:0;font:700 15px inherit;font-family:inherit;cursor:pointer}' +
    '.vr-acoes .sim{background:#f3c64e;color:#111}.vr-acoes .nao{background:transparent;color:inherit;border:1px solid var(--border-color,#334155)}' +
    '.vr-erro{color:#fca5a5;font-size:13px;margin-top:10px;display:none}' +
    '.vr-nota{display:block;margin-top:6px;font-size:12px;color:var(--text-tertiary,#94a3b8);line-height:1.4}';
  document.head.appendChild(css);

  function lugar() {
    let el = document.getElementById('vr-estado');
    if (!el) {
      el = document.createElement('div'); el.id = 'vr-estado';
      const ref = document.getElementById('cartaoOficial') || document.getElementById('tipoBadge');
      if (!ref || !ref.parentNode) return null;
      ref.parentNode.insertBefore(el, ref.nextSibling);
    }
    return el;
  }

  async function mostrarEstado() {
    const el = lugar(); if (!el || !perfil) return;
    if (perfil.type !== 'empresa' || perfil.role === 'admin' || perfil.role === 'equipa') { el.innerHTML = ''; return; }
    const coroa = window.FC && FC._selos && FC._selos.get(perfil.id) === 'verificada';
    if (coroa) {
      el.innerHTML = '<div class="vr-cartao ok"><span class="ic">👑</span><div><b>' + T('A sua loja está verificada') + '</b><small>' + T('Os clientes veem a coroa dourada ao lado do seu nome.') + '</small></div></div>';
      return;
    }
    const { data } = await supabaseClient.from('verificacoes').select('estado,motivo,criado').eq('empresa_id', perfil.id).order('criado', { ascending: false }).limit(1);
    const u = data && data[0];
    if (u && u.estado === 'pendente') {
      el.innerHTML = '<div class="vr-cartao analise"><span class="ic">⏳</span><div><b>' + T('Pedido de verificação em análise') + '</b><small>' + T('A Equipa vai ligar-lhe em breve. Normalmente leva 1 a 3 dias.') + '</small></div></div>';
    } else if (u && u.estado === 'recusada') {
      el.innerHTML = '<div class="vr-cartao recusa"><span class="ic">⚠️</span><div><b>' + T('Ainda não foi possível verificar') + '</b><small>' + esc(u.motivo || '') + '</small></div><button type="button" class="vr-bt" data-vr>' + T('Pedir de novo') + '</button></div>';
    } else {
      el.innerHTML = '<div class="vr-cartao convite"><span class="ic">👑</span><div><b>' + T('Ganhe a coroa dourada') + '</b><small>' + T('Mostre aos clientes que a sua loja é real e de confiança.') + '</small></div><button type="button" class="vr-bt" data-vr>' + T('Verificar') + '</button></div>';
    }
    const b = el.querySelector('[data-vr]'); if (b) b.onclick = abrir;
  }

  /* ---------- carimbo (estilo Timestamp): hora, data e localização gravadas na foto ---------- */
  const agora = () => new Date((window.FC && FC.agora) ? FC.agora() : Date.now());   // relógio do servidor, não o do telemóvel
  const fmt = (d, o) => d.toLocaleString('pt-PT', Object.assign({ timeZone: 'Africa/Maputo' }, o));

  function localizacao() {
    return new Promise((ok, falha) => {
      if (!navigator.geolocation) return falha(new Error('sem GPS'));
      navigator.geolocation.getCurrentPosition(
        p => ok({ lat: p.coords.latitude, lng: p.coords.longitude, precisao: Math.round(p.coords.accuracy || 0) }),
        e => falha(e), { enableHighAccuracy: true, timeout: 20000, maximumAge: 60000 });
    });
  }
  async function endereco(lat, lng) {   // rua / bairro / cidade (OpenStreetMap); se falhar, ficam só as coordenadas
    try {
      const c = new AbortController(); const t = setTimeout(() => c.abort(), 6000);
      const r = await fetch('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&accept-language=pt&lat=' + lat + '&lon=' + lng, { signal: c.signal });
      clearTimeout(t);
      const a = (await r.json()).address || {};
      return [[a.road, a.house_number].filter(Boolean).join(' '), a.neighbourhood || a.suburb || a.quarter || a.village,
              a.city || a.town || a.county, a.state].filter(Boolean).filter((x, i, l) => l.indexOf(x) === i).join(', ').slice(0, 160);
    } catch (e) { return ''; }
  }
  async function imagem(f) {
    const bmp = await createImageBitmap(f, { imageOrientation: 'from-image' });
    const k = Math.min(1, 1800 / Math.max(bmp.width, bmp.height));
    const c = document.createElement('canvas'); c.width = Math.round(bmp.width * k); c.height = Math.round(bmp.height * k);
    const g = c.getContext('2d'); g.drawImage(bmp, 0, 0, c.width, c.height);
    return { c, g };
  }
  function partir(g, texto, largura) {   // divide o texto em linhas que cabem na largura
    const ps = String(texto).split(' '), out = []; let l = '';
    ps.forEach(p => { const t = l ? l + ' ' + p : p; if (g.measureText(t).width > largura && l) { out.push(l); l = p; } else l = t; });
    if (l) out.push(l); return out;
  }
  const paraFicheiro = (c, nome) => new Promise(ok => c.toBlob(b => ok(new File([b], nome, { type: 'image/jpeg' })), 'image/jpeg', 0.85));

  // foto da loja: faixa em baixo com hora grande, data, morada, coordenadas e o nome da loja
  async function carimbarLoja(f, loc, morada) {
    const { c, g } = await imagem(f);
    const W = c.width, H = c.height, u = Math.max(14, Math.round(Math.min(W, H) * 0.034)), m = Math.round(u * 0.9);
    const d = agora(), fonte = 'Inter, Roboto, "Segoe UI", system-ui, sans-serif';
    g.font = '600 ' + u + 'px ' + fonte;
    const lMorada = partir(g, '📍 ' + (morada || 'Localização GPS'), W - 2 * m).slice(0, 2);
    const linhas = 1 + lMorada.length + 2, alt = Math.round(u * 2.6 + (linhas - 1) * u * 1.4 + m * 1.6);
    const grad = g.createLinearGradient(0, H - alt - u * 2, 0, H);
    grad.addColorStop(0, 'rgba(0,0,0,0)'); grad.addColorStop(0.35, 'rgba(0,0,0,.55)'); grad.addColorStop(1, 'rgba(0,0,0,.78)');
    g.fillStyle = grad; g.fillRect(0, H - alt - u * 2, W, alt + u * 2);
    g.shadowColor = 'rgba(0,0,0,.6)'; g.shadowBlur = u * 0.25;
    let y = H - alt + u * 1.9;
    g.fillStyle = '#ffffff'; g.font = '800 ' + Math.round(u * 2.3) + 'px ' + fonte;
    const hora = fmt(d, { hour: '2-digit', minute: '2-digit' }); g.fillText(hora, m, y);
    const xh = m + g.measureText(hora).width + u * 0.7;
    g.fillStyle = '#f3c64e'; g.fillRect(xh - u * 0.35, y - u * 1.75, Math.max(2, u * 0.16), u * 1.9);
    g.fillStyle = '#ffffff'; g.font = '700 ' + u + 'px ' + fonte;
    g.fillText(fmt(d, { day: '2-digit', month: '2-digit', year: 'numeric' }), xh, y - u * 0.95);
    g.font = '500 ' + u + 'px ' + fonte; g.fillText(fmt(d, { weekday: 'long' }), xh, y);
    g.font = '600 ' + u + 'px ' + fonte;
    lMorada.forEach(l => { y += u * 1.4; g.fillText(l, m, y); });
    y += u * 1.4; g.font = '500 ' + Math.round(u * 0.85) + 'px ' + fonte; g.fillStyle = 'rgba(255,255,255,.9)';
    g.fillText(loc.lat.toFixed(5) + ', ' + loc.lng.toFixed(5) + '  ·  ±' + loc.precisao + ' m', m, y);
    y += u * 1.4; g.fillStyle = '#f3c64e'; g.font = '700 ' + Math.round(u * 0.85) + 'px ' + fonte;
    g.fillText(('Feira Comercial · Verificação · ' + (perfil.full_name || '')).slice(0, 80), m, y);
    return paraFicheiro(c, 'loja.jpg');
  }

  // documento: marca de água em diagonal — se a foto sair daqui, não serve para mais nada
  async function carimbarDocumento(f) {
    const { c, g } = await imagem(f);
    const W = c.width, H = c.height, u = Math.max(14, Math.round(Math.min(W, H) * 0.04));
    const txt = 'SÓ PARA VERIFICAÇÃO NA FEIRA COMERCIAL · ' + fmt(agora(), { day: '2-digit', month: '2-digit', year: 'numeric' });
    g.save(); g.translate(W / 2, H / 2); g.rotate(-Math.PI / 7);
    g.font = '800 ' + u + 'px Inter, Roboto, system-ui, sans-serif'; g.textAlign = 'center';
    g.fillStyle = 'rgba(220,38,38,.30)'; g.strokeStyle = 'rgba(255,255,255,.25)'; g.lineWidth = Math.max(1, u * 0.05);
    const passo = u * 4.2, R = Math.hypot(W, H), larg = g.measureText(txt).width + u * 2;
    let n = 0;
    for (let yy = -R / 2; yy <= R / 2; yy += passo, n++)
      for (let xx = -R / 2 - (n % 2) * larg / 2; xx <= R / 2 + larg; xx += larg) { g.fillText(txt, xx, yy); g.strokeText(txt, xx, yy); }
    g.restore();
    return paraFicheiro(c, 'documento.jpg');
  }

  function abrir() {
    const m = document.createElement('div'); m.id = 'vr-modal';
    m.innerHTML = '<div class="cx" role="dialog" aria-modal="true">' +
      '<h3>👑 ' + T('Verificar a minha loja') + '</h3>' +
      '<p class="s">' + T('Envie 2 fotos e um número. A Equipa liga-lhe para confirmar e a coroa dourada aparece ao lado do seu nome.') + '</p>' +
      '<label>1. ' + T('Documento') + '</label>' +
      '<select id="vrTipo"><option value="alvara">' + T('Alvará') + '</option><option value="certidao">' + T('Certidão comercial') + '</option><option value="nuit">NUIT</option><option value="bi">' + T('BI do responsável (vendedor sem alvará)') + '</option><option value="outro">' + T('Outro documento') + '</option></select>' +
      '<div class="vr-fich" id="vrDocCx" style="margin-top:8px"><i class="fas fa-file-image"></i><img alt=""><span>' + T('Tirar foto do documento') + '</span><input type="file" id="vrDoc" accept="image/*,application/pdf" hidden></div>' +
      '<label>2. ' + T('Foto da loja ou da banca') + '</label>' +
      '<div class="vr-fich" id="vrFotoCx"><i class="fas fa-store"></i><img alt=""><span>' + T('Tirar foto agora, com o nome visível') + '</span><input type="file" id="vrFoto" accept="image/*" capture="environment" hidden></div>' +
      '<small class="vr-nota">📍 ' + T('A foto leva a data, a hora e a localização, para a Equipa confirmar que a loja existe. Permita o acesso à localização.') + '</small>' +
      '<label>3. ' + T('Telefone para a Equipa ligar') + '</label>' +
      '<input type="tel" id="vrTel" inputmode="tel" placeholder="84 123 4567" maxlength="20">' +
      '<div class="vr-priv"><i class="fas fa-lock" style="margin-top:2px"></i><span>' + T('Os documentos são privados: só a Equipa Feira Comercial os vê. Nunca aparecem no seu perfil.') + '</span></div>' +
      '<div class="vr-erro" id="vrErro"></div>' +
      '<div class="vr-acoes"><button type="button" class="nao" id="vrFechar">' + T('Cancelar') + '</button><button type="button" class="sim" id="vrEnviar">' + T('Enviar pedido') + '</button></div>' +
      '</div>';
    document.body.appendChild(m);
    const $ = id => m.querySelector('#' + id);
    try { if (perfil.phone || perfil.whatsapp) $('vrTel').value = perfil.whatsapp || perfil.phone; } catch (e) {}
    const fich = {}; let loc = null, pedidoLoc = null;
    const erro = t => { $('vrErro').textContent = t; $('vrErro').style.display = t ? 'block' : 'none'; };
    const SEM_GPS = T('Sem localização não é possível verificar a loja. Ligue a localização (GPS) do telemóvel, permita o acesso quando o navegador pedir e tire a foto outra vez.');
    const pronto = (cx, f, rotulo) => {
      $(cx).classList.add('tem'); $(cx).querySelector('span').textContent = '✓ ' + rotulo;
      const img = $(cx).querySelector('img');
      if (/^image\//.test(f.type)) img.src = URL.createObjectURL(f); else img.removeAttribute('src');
    };
    const aEspera = (cx, t) => { $(cx).classList.remove('tem'); $(cx).querySelector('span').textContent = t; };

    $('vrDocCx').onclick = e => { if (e.target !== $('vrDoc')) $('vrDoc').click(); };
    $('vrDoc').onchange = async () => {
      const f = $('vrDoc').files[0]; if (!f) return;
      erro(''); delete fich.vrDoc; aEspera('vrDocCx', T('A preparar…'));
      try { fich.vrDoc = /^image\//.test(f.type) ? await carimbarDocumento(f) : f; }
      catch (e) { fich.vrDoc = f; }
      pronto('vrDocCx', fich.vrDoc, /^image\//.test(f.type) ? T('Documento marcado: só para verificação') : (f.name || T('Ficheiro escolhido')).slice(0, 40));
    };

    // loja: a localização começa a ser pedida no toque (o telemóvel mostra logo o pedido de permissão)
    $('vrFotoCx').onclick = e => {
      if (e.target === $('vrFoto')) return;   // o clique do próprio campo sobe até aqui: não pedir a localização duas vezes
      pedidoLoc = localizacao(); pedidoLoc.catch(() => {}); $('vrFoto').click();
    };
    $('vrFoto').onchange = async () => {
      const f = $('vrFoto').files[0]; if (!f) return;
      erro(''); delete fich.vrFoto; loc = null;
      // foto antiga (da galeria)? tem de ser tirada agora
      if (f.lastModified && Date.now() - f.lastModified > 10 * 60 * 1000) {
        aEspera('vrFotoCx', T('Tirar foto agora, com o nome visível'));
        return erro(T('Esta foto não é de agora. Toque outra vez na foto da loja e fotografe-a agora, com a câmara.'));
      }
      aEspera('vrFotoCx', '📍 ' + T('A obter a localização…'));
      try { loc = await (pedidoLoc || localizacao()); }
      catch (e) { aEspera('vrFotoCx', T('Tirar foto agora, com o nome visível')); return erro(SEM_GPS); }
      aEspera('vrFotoCx', T('A carimbar a foto…'));
      loc.endereco = await endereco(loc.lat, loc.lng);
      try { fich.vrFoto = await carimbarLoja(f, loc, loc.endereco); }
      catch (e) { aEspera('vrFotoCx', T('Tirar foto agora, com o nome visível')); return erro(T('Não foi possível preparar a foto. Tente outra vez.')); }
      pronto('vrFotoCx', fich.vrFoto, (loc.endereco || T('Localização registada')).slice(0, 48));
    };
    const fechar = () => m.remove();
    $('vrFechar').onclick = fechar;
    m.addEventListener('click', e => { if (e.target === m) fechar(); });
    $('vrEnviar').onclick = async () => {
      const tel = $('vrTel').value.trim();
      if (!fich.vrDoc) return erro(T('Tire uma foto do documento.'));
      if (!fich.vrFoto) return erro(T('Tire uma foto da loja ou da banca.'));
      if (!loc) return erro(SEM_GPS);
      if (tel.replace(/\D/g, '').length < 9) return erro(T('Escreva um telefone com 9 dígitos.'));
      const b = $('vrEnviar'); b.disabled = true; b.textContent = T('A enviar…');
      const enviados = [];
      try {
        const subir = async (f, nome) => {
          if (f.size > 6 * 1024 * 1024) throw new Error(T('Ficheiro grande demais (máximo 6 MB).'));
          const ext = f.type === 'application/pdf' ? 'pdf' : (f.type.split('/')[1] || 'jpg').replace('jpeg', 'jpg');
          const cam = perfil.id + '/' + Date.now() + '-' + nome + '.' + ext;
          const r = await supabaseClient.storage.from('verificacoes').upload(cam, f, { contentType: f.type });
          if (r.error) throw r.error;
          enviados.push(cam); return cam;
        };
        const doc = await subir(fich.vrDoc, 'documento');
        const foto = await subir(fich.vrFoto, 'loja');
        const { error } = await supabaseClient.rpc('pedir_verificacao', { p_tipo: $('vrTipo').value, p_documento: doc, p_foto: foto, p_telefone: tel,
          p_lat: loc.lat, p_lng: loc.lng, p_precisao: loc.precisao, p_endereco: loc.endereco || null });
        if (error) throw error;
        fechar();
        mostrarEstado();
        if (window.FC && FC.toast) FC.toast('✅ ' + T('Pedido enviado. A Equipa vai ligar-lhe em breve.'));
      } catch (e) {
        if (enviados.length) supabaseClient.storage.from('verificacoes').remove(enviados).then(() => {}, () => {});
        erro((window.FC && FC.traduzirErro) ? FC.traduzirErro(e) : (e.message || String(e)));
        b.disabled = false; b.textContent = T('Enviar pedido');
      }
    };
  }

  window.FCVerificar = {
    iniciar(p) {
      perfil = p; mostrarEstado();
      document.addEventListener('fc:selos', mostrarEstado);
    }
  };
})();
