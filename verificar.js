/* ============================================================
   Feira Comercial — verificar.js
   No MEU perfil de empresa: pedir a coroa dourada 👑 (loja verificada).
   Envia documento + foto da loja + telefone. Os ficheiros ficam privados
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
    '.vr-erro{color:#fca5a5;font-size:13px;margin-top:10px;display:none}';
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

  async function reduzir(f) {
    if (!f || !/^image\//.test(f.type) || f.size < 1.2 * 1024 * 1024) return f;
    try {
      const img = await createImageBitmap(f);
      const k = Math.min(1, 1800 / Math.max(img.width, img.height));
      const c = document.createElement('canvas'); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      const blob = await new Promise(r => c.toBlob(r, 'image/jpeg', 0.82));
      return blob && blob.size < f.size ? new File([blob], 'foto.jpg', { type: 'image/jpeg' }) : f;
    } catch (e) { return f; }
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
      '<div class="vr-fich" id="vrFotoCx"><i class="fas fa-store"></i><img alt=""><span>' + T('Com o nome visível, se possível') + '</span><input type="file" id="vrFoto" accept="image/*" hidden></div>' +
      '<label>3. ' + T('Telefone para a Equipa ligar') + '</label>' +
      '<input type="tel" id="vrTel" inputmode="tel" placeholder="84 123 4567" maxlength="20">' +
      '<div class="vr-priv"><i class="fas fa-lock" style="margin-top:2px"></i><span>' + T('Os documentos são privados: só a Equipa Feira Comercial os vê. Nunca aparecem no seu perfil.') + '</span></div>' +
      '<div class="vr-erro" id="vrErro"></div>' +
      '<div class="vr-acoes"><button type="button" class="nao" id="vrFechar">' + T('Cancelar') + '</button><button type="button" class="sim" id="vrEnviar">' + T('Enviar pedido') + '</button></div>' +
      '</div>';
    document.body.appendChild(m);
    const $ = id => m.querySelector('#' + id);
    try { if (perfil.phone || perfil.whatsapp) $('vrTel').value = perfil.whatsapp || perfil.phone; } catch (e) {}
    const fich = {};
    [['vrDocCx', 'vrDoc'], ['vrFotoCx', 'vrFoto']].forEach(([cx, inp]) => {
      $(cx).onclick = () => $(inp).click();
      $(inp).onchange = () => {
        const f = $(inp).files[0]; if (!f) return;
        fich[inp] = f; $(cx).classList.add('tem');
        $(cx).querySelector('span').textContent = '✓ ' + (f.name || T('Ficheiro escolhido')).slice(0, 40);
        const img = $(cx).querySelector('img');
        if (/^image\//.test(f.type)) img.src = URL.createObjectURL(f); else img.removeAttribute('src');
      };
    });
    const fechar = () => m.remove();
    $('vrFechar').onclick = fechar;
    m.addEventListener('click', e => { if (e.target === m) fechar(); });
    $('vrEnviar').onclick = async () => {
      const erro = t => { $('vrErro').textContent = t; $('vrErro').style.display = 'block'; };
      const tel = $('vrTel').value.trim();
      if (!fich.vrDoc) return erro(T('Tire uma foto do documento.'));
      if (!fich.vrFoto) return erro(T('Tire uma foto da loja ou da banca.'));
      if (tel.replace(/\D/g, '').length < 9) return erro(T('Escreva um telefone com 9 dígitos.'));
      const b = $('vrEnviar'); b.disabled = true; b.textContent = T('A enviar…');
      const enviados = [];
      try {
        const subir = async (f, nome) => {
          f = await reduzir(f);
          if (f.size > 6 * 1024 * 1024) throw new Error(T('Ficheiro grande demais (máximo 6 MB).'));
          const ext = f.type === 'application/pdf' ? 'pdf' : (f.type.split('/')[1] || 'jpg').replace('jpeg', 'jpg');
          const cam = perfil.id + '/' + Date.now() + '-' + nome + '.' + ext;
          const r = await supabaseClient.storage.from('verificacoes').upload(cam, f, { contentType: f.type });
          if (r.error) throw r.error;
          enviados.push(cam); return cam;
        };
        const doc = await subir(fich.vrDoc, 'documento');
        const foto = await subir(fich.vrFoto, 'loja');
        const { error } = await supabaseClient.rpc('pedir_verificacao', { p_tipo: $('vrTipo').value, p_documento: doc, p_foto: foto, p_telefone: tel });
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
