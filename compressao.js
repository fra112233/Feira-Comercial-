/* ============================================================
   Feira Comercial — compressao.js
   Otimiza fotos e vídeos NO TELEMÓVEL antes de enviar, para poupar
   dados e espaço sem perder qualidade visível.

   • Fotos: até 100 MB à entrada → JPG de boa qualidade (lado maior 1600 px — nítido no telemóvel e rápido a enviar).
   • Vídeos: até 3 minutos → MP4 (H.264) 720p, 30 fps, 1 Mbps, com o som original;
     o resultado fica sempre abaixo do limite de envio. Vídeos que já são
     leves vão como estão. A otimização começa logo ao escolher o vídeo
     (FCMedia.iniciar) e usa o codificador de hardware do telemóvel.
   • Avisos claros (janela) e barra de progresso.

   Usa a biblioteca Mediabunny (WebCodecs, MPL-2.0), carregada só quando
   é preciso otimizar um vídeo.

   Uso:
     const f = await FCMedia.preparar(ficheiro, { aoProgresso: p => ... });
     FCMedia.validar(ficheiro)  → verifica tamanho/duração antes de escolher
     FCMedia.mostrarErro(err)   → janela com a explicação
   ============================================================ */
(function () {
  if (window.FCMedia) return;

  var MB = 1024 * 1024;
  var LIMITES = {
    fotoEntrada: 100 * MB,      // foto escolhida pelo utilizador
    videoSegundos: 180,         // 3 minutos
    videoEntrada: 1024 * MB,    // ficheiro de vídeo escolhido (1 GB)
    envio: 48 * MB,             // máximo aceite pelo servidor (50 MB, com margem)
    alvo: 44 * MB,              // tamanho máximo do vídeo otimizado
    videoLeve: 12 * MB          // abaixo disto o vídeo vai sem mexer
  };
  var CODEC = window.FC_VIDEO_CODEC || 'avc';           // H.264: toca em todos os telemóveis
  var URL_LIB = window.FC_MEDIABUNNY_URL || 'https://cdn.jsdelivr.net/npm/mediabunny@1.61.3/dist/bundles/mediabunny.min.mjs';
  var _lib = null;
  function lib() { if (!_lib) _lib = import(URL_LIB); return _lib; }

  function mb(n) { return (n / MB).toFixed(n < 10 * MB ? 1 : 0).replace('.', ',') + ' MB'; }
  function tempo(s) { s = Math.round(s); var m = Math.floor(s / 60), r = s % 60; return m ? m + ' min' + (r ? ' ' + r + ' s' : '') : r + ' s'; }
  function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  function Erro(titulo, texto) { var e = new Error(texto); e.fc = true; e.titulo = titulo; e.texto = texto; return e; }

  /* ---------- interface: janela de aviso e barra de progresso ---------- */
  function estilos() {
    if (document.getElementById('fcmedia-css')) return;
    var css = document.createElement('style');
    css.id = 'fcmedia-css';
    css.textContent =
      '#fcm-aviso{position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;padding:20px;' +
      'font-family:Inter,"Segoe UI",system-ui,sans-serif}' +
      '#fcm-aviso .cx{background:#18181b;color:#f4f4f5;border:1px solid #2c2c34;border-radius:18px;max-width:380px;width:100%;padding:22px 20px 18px;box-shadow:0 20px 60px rgba(0,0,0,.5);text-align:center}' +
      '#fcm-aviso .ic{width:54px;height:54px;border-radius:16px;margin:0 auto 12px;display:flex;align-items:center;justify-content:center;font-size:24px;background:rgba(243,198,78,.14);color:#f3c64e}' +
      '#fcm-aviso .ic.erro{background:rgba(248,113,113,.14);color:#f87171}' +
      '#fcm-aviso h3{font-size:18px;margin:0 0 8px;font-weight:800}' +
      '#fcm-aviso p{font-size:14.5px;line-height:1.5;color:#d4d4d8;margin:0}' +
      '#fcm-aviso ul{text-align:left;margin:12px 0 0;padding-left:20px;font-size:13.5px;color:#a1a1aa;line-height:1.6}' +
      '#fcm-aviso button{margin-top:18px;width:100%;padding:12px;border:none;border-radius:12px;background:#f3c64e;color:#18181b;font-family:inherit;font-size:15px;font-weight:700;cursor:pointer}' +
      '#fcm-prog{position:fixed;left:50%;bottom:calc(16px + env(safe-area-inset-bottom));transform:translateX(-50%);z-index:8999;width:min(360px,calc(100vw - 32px));' +
      'background:#18181b;color:#f4f4f5;border:1px solid #2c2c34;border-radius:14px;padding:12px 14px;box-shadow:0 10px 30px rgba(0,0,0,.4);font:500 13.5px Inter,system-ui,sans-serif}' +
      '#fcm-prog .l{display:flex;justify-content:space-between;gap:10px;margin-bottom:8px}' +
      '#fcm-prog .b{height:6px;border-radius:6px;background:#2c2c34;overflow:hidden}' +
      '#fcm-prog .b i{display:block;height:100%;width:0;background:#f3c64e;transition:width .2s}' +
      '#fcm-prog small{display:block;color:#a1a1aa;margin-top:6px;font-size:12px}';
    document.head.appendChild(css);
  }

  function aviso(titulo, texto, opcoes) {
    opcoes = opcoes || {};
    estilos();
    return new Promise(function (ok) {
      var velho = document.getElementById('fcm-aviso'); if (velho) velho.remove();
      var el = document.createElement('div');
      el.id = 'fcm-aviso';
      el.setAttribute('role', 'alertdialog');
      el.innerHTML = '<div class="cx"><div class="ic ' + (opcoes.erro ? 'erro' : '') + '"><i class="fas ' + (opcoes.icone || (opcoes.erro ? 'fa-triangle-exclamation' : 'fa-circle-info')) + '"></i></div>' +
        '<h3>' + esc(titulo) + '</h3><p>' + esc(texto) + '</p>' +
        (opcoes.dicas ? '<ul>' + opcoes.dicas.map(function (d) { return '<li>' + esc(d) + '</li>'; }).join('') + '</ul>' : '') +
        '<button type="button">Entendi</button></div>';
      document.body.appendChild(el);
      var fechar = function () { el.remove(); ok(); };
      el.querySelector('button').onclick = fechar;
      el.addEventListener('click', function (e) { if (e.target === el) fechar(); });
      el.querySelector('button').focus();
    });
  }

  function progresso(texto) {
    estilos();
    var el = document.getElementById('fcm-prog');
    if (!el) { el = document.createElement('div'); el.id = 'fcm-prog'; document.body.appendChild(el); }
    el.innerHTML = '<div class="l"><span class="t"></span><b class="p"></b></div><div class="b"><i></i></div><small>Mantenha esta página aberta até terminar.</small>';
    var api = {
      atualizar: function (p, t) {
        if (t) el.querySelector('.t').textContent = t;
        if (p == null) { el.querySelector('.p').textContent = ''; return; }
        var pc = Math.max(0, Math.min(100, Math.round(p * 100)));
        el.querySelector('.p').textContent = pc + '%';
        el.querySelector('.b i').style.width = pc + '%';
      },
      fechar: function () { el.remove(); }
    };
    api.atualizar(null, texto);
    return api;
  }

  var DICAS_VIDEO = [
    'Na câmara do telemóvel, grave em 720p ou 1080p a 30 fps (não em 4K).',
    'Corte o vídeo na galeria antes de publicar.',
    'Vídeos até 3 minutos.'
  ];

  function mostrarErro(err) {
    if (err && err.fc) return aviso(err.titulo, err.texto, { erro: true, dicas: err.dicas });
    var m = (err && err.message) || String(err || '');
    if (/exceeded the maximum allowed size|too large|payload/i.test(m))
      return aviso('Ficheiro demasiado grande', 'O ficheiro ultrapassa o limite de envio de 50 MB.', { erro: true, dicas: DICAS_VIDEO });
    if (/mime type|not supported/i.test(m))
      return aviso('Tipo de ficheiro não aceite', 'Use fotos (JPG, PNG, WEBP) ou vídeos (MP4, MOV).', { erro: true });
    if (/Failed to fetch|NetworkError|network/i.test(m))
      return aviso('Sem ligação à internet', 'Verifique a ligação e tente outra vez.', { erro: true, icone: 'fa-wifi' });
    return aviso('Não foi possível enviar', m || 'Tente outra vez.', { erro: true });
  }

  /* ---------- medir a duração de um vídeo ---------- */
  function duracao(file) {
    return new Promise(function (ok) {
      var v = document.createElement('video'), url = URL.createObjectURL(file), feito = false;
      var fim = function (d) { if (feito) return; feito = true; URL.revokeObjectURL(url); ok(d); };
      v.preload = 'metadata'; v.muted = true;
      v.onloadedmetadata = function () { fim(isFinite(v.duration) ? v.duration : null); };
      v.onerror = function () { fim(null); };
      setTimeout(function () { fim(null); }, 8000);
      v.src = url;
    });
  }

  /* ---------- validar logo ao escolher (rápido, sem comprimir) ---------- */
  async function validar(file) {
    if (!file) return;
    var tipo = file.type || '';
    if (tipo.indexOf('image/') === 0) {
      if (file.size > LIMITES.fotoEntrada)
        throw Erro('Foto demasiado grande', 'Esta foto tem ' + mb(file.size) + '. O máximo é 100 MB por foto.');
      return;
    }
    if (tipo.indexOf('video/') === 0) {
      if (file.size > LIMITES.videoEntrada)
        throw Object.assign(Erro('Vídeo demasiado grande', 'Este vídeo tem ' + mb(file.size) + '. Escolha um vídeo mais curto (máximo 3 minutos).'), { dicas: DICAS_VIDEO });
      var d = await duracao(file);
      if (d && d > LIMITES.videoSegundos + 0.5)
        throw Object.assign(Erro('Vídeo demasiado longo', 'Este vídeo tem ' + tempo(d) + '. O máximo é 3 minutos.'), { dicas: ['Corte o vídeo na galeria do telemóvel e volte a escolhê-lo.'] });
    }
  }

  /* ---------- fotos ---------- */
  async function prepararFoto(file) {
    await validar(file);
    if (file.type === 'image/gif') {
      if (file.size > 10 * MB) throw Erro('GIF demasiado grande', 'Este GIF tem ' + mb(file.size) + '. O máximo para GIF é 10 MB.');
      return file;
    }
    try {
      var bmp = await createImageBitmap(file);
      var lado = 1600, k = Math.min(1, lado / Math.max(bmp.width, bmp.height));   // era 1920: ~30% mais leve, igual no ecrã do telemóvel
      var c = document.createElement('canvas');
      c.width = Math.round(bmp.width * k); c.height = Math.round(bmp.height * k);
      var ctx = c.getContext('2d');
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height);   // PNG transparente → fundo branco
      ctx.drawImage(bmp, 0, 0, c.width, c.height);
      if (bmp.close) bmp.close();
      var blob = await new Promise(function (r) { c.toBlob(r, 'image/jpeg', 0.82); });
      if (blob && blob.size < file.size) {
        var nome = (file.name || 'foto').replace(/\.\w+$/, '') + '.jpg';
        return new File([blob], nome, { type: 'image/jpeg' });
      }
    } catch (e) { /* formato que o navegador não lê: segue o original se couber */ }
    if (file.size > LIMITES.envio) throw Erro('Não foi possível preparar a foto', 'Este telemóvel não conseguiu reduzir a foto de ' + mb(file.size) + '. Tente uma foto em JPG ou tire uma captura de ecrã dela.');
    return file;
  }

  /* ---------- vídeos ---------- */
  // Converte uma vez; tenta primeiro o codificador de hardware do telemóvel (muito mais rápido)
  // e, se o aparelho não o tiver para esta resolução, usa o normal.
  async function converter(M, file, cfg, aoProgresso) {
    var modos = ['prefer-hardware', 'no-preference'], ultimoErro = null;
    for (var i = 0; i < modos.length; i++) {
      try {
        var input = new M.Input({ formats: M.ALL_FORMATS, source: new M.BlobSource(file) });
        var output = new M.Output({ format: new M.Mp4OutputFormat({ fastStart: 'in-memory' }), target: new M.BufferTarget() });
        var conv = await M.Conversion.init({
          input: input, output: output,
          video: { width: cfg.w, height: cfg.h, fit: 'contain', codec: CODEC, quality: new M.Quality({ bitrate: cfg.bitrate }),
                   frameRate: cfg.frameRate, allowTransformationMetadata: false, hardwareAcceleration: modos[i] }
          // o som é copiado tal como está quando possível (sem perder qualidade)
        });
        if (!conv.isValid) throw new Error('conversão inválida');
        conv.onProgress = function (p) { aoProgresso(p); };
        await conv.execute();
        return output.target.buffer;
      } catch (e) { ultimoErro = e; aoProgresso(0); }
    }
    throw ultimoErro || new Error('conversão falhou');
  }

  async function prepararVideo(file, opcoes) {
    opcoes = opcoes || {};
    await validar(file);
    if (file.size <= LIMITES.videoLeve) {                // já é leve (e com bitrate baixo): vai já, sem esperar
      var dLeve = await duracao(file);
      if (!dLeve || file.size * 8 / dLeve <= 1.4e6) return file;
    }

    var aoProgresso = opcoes.aoProgresso || function () {};
    var trava = null;
    try { if (navigator.wakeLock) trava = await navigator.wakeLock.request('screen'); } catch (e) {}
    try {
      if (typeof VideoEncoder === 'undefined') throw new Error('sem WebCodecs');
      var M = await lib();
      var input = new M.Input({ formats: M.ALL_FORMATS, source: new M.BlobSource(file) });
      var vt = await input.getPrimaryVideoTrack();
      if (!vt) throw new Error('sem faixa de vídeo');
      var dur = await input.computeDuration();
      if (dur > LIMITES.videoSegundos + 0.5)
        throw Object.assign(Erro('Vídeo demasiado longo', 'Este vídeo tem ' + tempo(dur) + '. O máximo é 3 minutos.'), { dicas: ['Corte o vídeo na galeria do telemóvel e volte a escolhê-lo.'] });

      // 720p: qualidade ideal para ecrãs de telemóvel e muito mais rápido de processar
      var dw = await vt.getDisplayWidth(), dh = await vt.getDisplayHeight();
      var k = Math.min(1, 1280 / Math.max(dw, dh));
      var w = Math.max(2, Math.round(dw * k / 2) * 2), h = Math.max(2, Math.round(dh * k / 2) * 2);

      var orcamento = (LIMITES.alvo * 8) / Math.max(dur, 1) - 192e3;   // cabe sempre no limite
      // 720p a 1 Mbps: nítido no ecrã do telemóvel, envio ~1/3 mais rápido e menos dados para quem vê
      // (era 1,5 Mbps: um vídeo de 1 min 40 s ficava com 21 MB; agora fica com ~14 MB)
      var bitrate = Math.max(6e5, Math.min(1.0e6, orcamento));

      // não vale a pena: já é 720p (ou menos) e leve — vai como está, sem esperar
      var bitrateOriginal = file.size * 8 / Math.max(dur, 1);
      if (k === 1 && bitrateOriginal <= bitrate * 1.35 && file.size <= LIMITES.envio) return file;

      var fps = null;
      try { fps = (await vt.computeFrameRateMetrics({ targetPacketCount: 90 })).bestGuessFrameRate; } catch (e) {}
      var frameRate = fps && fps > 31 ? 30 : undefined;      // 60 fps → 30 fps (metade do trabalho)

      if (!(await M.canEncodeVideo(CODEC, { width: w, height: h, bitrate: bitrate })))
        throw new Error('este navegador não codifica H.264');

      var buf = await converter(M, file, { w: w, h: h, bitrate: bitrate, frameRate: frameRate }, aoProgresso);
      var novo = new File([buf], (file.name || 'video').replace(/\.\w+$/, '') + '.mp4', { type: 'video/mp4' });
      if (novo.size >= file.size && file.size <= LIMITES.envio) return file;   // não ficou mais leve
      if (novo.size > LIMITES.envio)
        throw Object.assign(Erro('Vídeo demasiado pesado', 'Mesmo otimizado, o vídeo ficou com ' + mb(novo.size) + '. O máximo é 50 MB.'), { dicas: DICAS_VIDEO });
      return novo;
    } catch (e) {
      if (e && e.fc) throw e;
      console.warn('[FCMedia] otimização não disponível:', e && e.message);
      if (file.size <= LIMITES.envio) return file;           // segue o original, que cabe no limite
      throw Object.assign(Erro('Não foi possível otimizar o vídeo',
        'O vídeo tem ' + mb(file.size) + ' e este navegador não conseguiu reduzi-lo. O máximo para enviar sem otimização é 50 MB.'),
        { dicas: ['Atualize o Google Chrome (ou o Safari) e tente outra vez.'].concat(DICAS_VIDEO) });
    } finally {
      try { if (trava) trava.release(); } catch (e) {}
    }
  }

  /* ---------- trabalho em segundo plano ----------
     iniciar(ficheiro) começa a otimizar logo ao escolher (enquanto a pessoa escreve);
     preparar(ficheiro) depois reaproveita esse trabalho. Um vídeo de cada vez. */
  var tarefas = new WeakMap();
  var fila = Promise.resolve();

  function iniciar(file) {
    if (!file) return null;
    var t = tarefas.get(file);
    if (t) return t;
    var tipo = file.type || '';
    t = { progresso: 0, pronto: false, ouvintes: [] };
    t.ouvir = function (fn) { t.ouvintes.push(fn); fn(t.progresso, t.pronto); return function () { t.ouvintes = t.ouvintes.filter(function (x) { return x !== fn; }); }; };
    var avisar = function () { t.ouvintes.forEach(function (fn) { try { fn(t.progresso, t.pronto); } catch (e) {} }); };
    var trabalho;
    if (tipo.indexOf('image/') === 0) trabalho = function () { return prepararFoto(file); };
    else if (tipo.indexOf('video/') === 0) trabalho = function () { return prepararVideo(file, { aoProgresso: function (p) { t.progresso = p; avisar(); } }); };
    else trabalho = function () { return Promise.resolve(file); };
    // fotos em paralelo; vídeos em fila (o codificador do telemóvel trabalha melhor um de cada vez)
    if (tipo.indexOf('video/') === 0) { t.promessa = fila.then(trabalho, trabalho); fila = t.promessa.catch(function () {}); }
    else t.promessa = trabalho();
    t.promessa.then(function () { t.progresso = 1; t.pronto = true; avisar(); }, function () { t.pronto = true; avisar(); });
    t.promessa.catch(function () {});
    tarefas.set(file, t);
    return t;
  }

  /* ---------- um só ponto de entrada, com progresso no ecrã ---------- */
  async function preparar(file, opcoes) {
    opcoes = opcoes || {};
    var t = iniciar(file);
    var tipo = file && file.type || '';
    if (tipo.indexOf('video/') !== 0 || opcoes.semBarra) return t.promessa;
    var barra = null, parar = null;
    var etiqueta = opcoes.etiqueta || 'A otimizar o vídeo…';
    // só mostra a barra se ainda faltar trabalho e demorar mais de meio segundo
    var temporizador = setTimeout(function () {
      if (t.pronto) return;
      barra = progresso(etiqueta);
      parar = t.ouvir(function (p) { barra.atualizar(p); if (opcoes.aoProgresso) opcoes.aoProgresso(p); });
    }, 500);
    try { return await t.promessa; }
    finally { clearTimeout(temporizador); if (parar) parar(); if (barra) barra.fechar(); }
  }

  /* ---------- não guardar a mesma foto/vídeo duas vezes ----------
     Calcula uma "impressão digital" do ficheiro original (tamanho + início, meio e fim).
     O ficheiro é guardado com esse nome; se a empresa voltar a enviar exatamente o mesmo
     ficheiro, reaproveita-se o que já está guardado (não ocupa espaço nem tempo de envio). */
  var impressoes = new WeakMap();
  async function impressao(file) {
    if (!file || !window.crypto || !crypto.subtle) return null;
    if (impressoes.has(file)) return impressoes.get(file);
    var p = (async function () {
      var BLOCO = 1024 * 1024, partes = [];
      if (file.size <= 4 * BLOCO) partes.push(file);
      else partes.push(file.slice(0, BLOCO), file.slice(Math.floor(file.size / 2) - BLOCO / 2, Math.floor(file.size / 2) + BLOCO / 2), file.slice(file.size - BLOCO));
      var dados = new Blob([String(file.size) + '|'].concat(partes));
      var buf = await dados.arrayBuffer();
      var h = new Uint8Array(await crypto.subtle.digest('SHA-256', buf));
      var s = '';
      for (var i = 0; i < 16; i++) s += h[i].toString(16).padStart(2, '0');
      return s;
    })().catch(function () { return null; });
    impressoes.set(file, p);
    return p;
  }

  async function jaExiste(url) {
    try {
      var r = await fetch(url + (url.indexOf('?') < 0 ? '?' : '&') + 'v=' + Date.now(), { method: 'HEAD', cache: 'no-store' });
      return r.ok;
    } catch (e) { return false; }
  }

  // envia para o espaço "media" (pasta do utilizador) e devolve { url, type, repetido }
  async function enviarMedia(sb, userId, file, opcoes) {
    var tipo = (file.type || '').indexOf('video') === 0 ? 'video' : 'image';
    var balde = sb.storage.from('media');
    var h = await impressao(file);
    var caminho = h ? (userId + '/h-' + h + (tipo === 'video' ? '.mp4' : '.jpg')) : null;
    var url = caminho ? balde.getPublicUrl(caminho).data.publicUrl : null;
    if (url && await jaExiste(url)) return { url: url, type: tipo, repetido: true };
    var f = await preparar(file, opcoes);
    if (!caminho) {
      var ext = ((f.name || '').split('.').pop() || (tipo === 'video' ? 'mp4' : 'jpg')).toLowerCase().replace(/[^a-z0-9]/g, '') || (tipo === 'video' ? 'mp4' : 'jpg');
      caminho = userId + '/' + Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.' + ext;
      url = balde.getPublicUrl(caminho).data.publicUrl;
    }
    var res = await balde.upload(caminho, f, { contentType: f.type || file.type, cacheControl: '31536000' });   // ficheiro nunca muda: o telemóvel guarda-o e não volta a descarregar
    if (res.error) {
      var msg = String(res.error.message || res.error.error || '') + ' ' + String(res.error.statusCode || '');
      if (!/duplicate|already exists|409/i.test(msg)) throw res.error;   // já lá estava: reaproveita
    }
    return { url: url, type: tipo, repetido: !!res.error };
  }

  window.FCMedia = {
    LIMITES: LIMITES, validar: validar, preparar: preparar, iniciar: iniciar, prepararFoto: prepararFoto, prepararVideo: prepararVideo,
    aviso: aviso, progresso: progresso, mostrarErro: mostrarErro, duracao: duracao, mb: mb,
    impressao: impressao, enviarMedia: enviarMedia
  };
})();
