/* ============================================================
   Feira Comercial — perfil-campos.js
   Listas e funções partilhadas pelo registo (Formulario.html)
   e pela página de perfil (perfil.html)
   ============================================================ */
window.FCP = (function () {
  const PROVINCIAS = ['Maputo Cidade', 'Maputo Província', 'Gaza', 'Inhambane', 'Sofala', 'Manica',
                      'Tete', 'Zambézia', 'Nampula', 'Cabo Delgado', 'Niassa'];

  const SETORES = ['Comércio / Loja', 'Restauração e Bebidas', 'Agricultura e Pecuária', 'Construção e Materiais',
                   'Transporte e Logística', 'Tecnologia e Informática', 'Saúde e Farmácia', 'Educação e Formação',
                   'Beleza e Estética', 'Moda e Vestuário', 'Turismo e Hotelaria', 'Serviços Financeiros',
                   'Imobiliário', 'Indústria', 'Eventos e Entretenimento', 'Outro'];

  const GENEROS = ['Masculino', 'Feminino', 'Outro', 'Prefiro não dizer'];

  const DIAS = [
    ['seg', 'Segunda'], ['ter', 'Terça'], ['qua', 'Quarta'], ['qui', 'Quinta'],
    ['sex', 'Sexta'], ['sab', 'Sábado'], ['dom', 'Domingo']
  ];

  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function opcoes(lista, atual, vazio) {
    return (vazio ? `<option value="">${esc(vazio)}</option>` : '') +
      lista.map(v => `<option value="${esc(v)}" ${v === atual ? 'selected' : ''}>${esc(v)}</option>`).join('');
  }

  // horário padrão: seg–sex 08:00–17:00, sábado 08:00–13:00, domingo fechado
  function horarioPadrao() {
    const h = {};
    DIAS.forEach(([k]) => { h[k] = { aberto: k !== 'dom', de: '08:00', ate: k === 'sab' ? '13:00' : '17:00' }; });
    return h;
  }

  // HTML dos campos de horário (um por dia), com prefixo para os ids
  function camposHorario(prefixo, horario) {
    const h = horario || horarioPadrao();
    return DIAS.map(([k, nome]) => {
      const d = h[k] || { aberto: false, de: '08:00', ate: '17:00' };
      return `
      <div class="fcp-dia" style="display:flex;align-items:center;gap:6px;margin-bottom:6px;">
        <label style="flex:0 0 92px;display:flex;align-items:center;gap:6px;font-weight:600;margin:0;font-size:14px;">
          <input type="checkbox" id="${prefixo}-${k}-aberto" ${d.aberto ? 'checked' : ''}
                 onchange="FCP.alternarDia('${prefixo}','${k}')" style="width:auto;"> ${nome}
        </label>
        <input type="time" id="${prefixo}-${k}-de" value="${esc(d.de || '08:00')}" ${d.aberto ? '' : 'disabled'} style="flex:1;min-width:0;width:auto;padding:6px 4px;font-size:13px;">
        <span style="font-size:13px;">às</span>
        <input type="time" id="${prefixo}-${k}-ate" value="${esc(d.ate || '17:00')}" ${d.aberto ? '' : 'disabled'} style="flex:1;min-width:0;width:auto;padding:6px 4px;font-size:13px;">
        <span id="${prefixo}-${k}-fechado" style="color:#94a3b8;font-size:12px;${d.aberto ? 'display:none' : ''}">Fechado</span>
      </div>`;
    }).join('');
  }

  function alternarDia(prefixo, k) {
    const aberto = document.getElementById(`${prefixo}-${k}-aberto`).checked;
    document.getElementById(`${prefixo}-${k}-de`).disabled = !aberto;
    document.getElementById(`${prefixo}-${k}-ate`).disabled = !aberto;
    document.getElementById(`${prefixo}-${k}-fechado`).style.display = aberto ? 'none' : '';
  }

  function lerHorario(prefixo) {
    const h = {};
    DIAS.forEach(([k]) => {
      h[k] = {
        aberto: document.getElementById(`${prefixo}-${k}-aberto`).checked,
        de: document.getElementById(`${prefixo}-${k}-de`).value || '08:00',
        ate: document.getElementById(`${prefixo}-${k}-ate`).value || '17:00'
      };
    });
    return h;
  }

  // "Aberto agora · fecha às 17:00" / "Fechado · abre segunda às 08:00"
  function estadoAgora(horario) {
    if (!horario) return null;
    const agora = new Date();
    const idx = (agora.getDay() + 6) % 7; // 0 = segunda
    const hhmm = agora.toTimeString().slice(0, 5);
    const hoje = horario[DIAS[idx][0]];
    if (hoje && hoje.aberto && hhmm >= hoje.de && hhmm < hoje.ate) {
      return { aberto: true, texto: `Aberto agora · fecha às ${hoje.ate}` };
    }
    for (let i = 0; i < 7; i++) {
      const j = (idx + i) % 7;
      const d = horario[DIAS[j][0]];
      if (!d || !d.aberto) continue;
      if (i === 0 && hhmm >= d.de) continue;
      const quando = i === 0 ? 'hoje' : (i === 1 ? 'amanhã' : DIAS[j][1].toLowerCase());
      return { aberto: false, texto: `Fechado · abre ${quando} às ${d.de}` };
    }
    return { aberto: false, texto: 'Fechado' };
  }

  function horarioEmLinhas(horario) {
    if (!horario) return '';
    return DIAS.map(([k, nome]) => {
      const d = horario[k];
      const txt = d && d.aberto ? `${d.de} – ${d.ate}` : 'Fechado';
      return `<div style="display:flex;justify-content:space-between;gap:12px;padding:3px 0;">
                <span>${nome}</span><span style="font-weight:600;">${txt}</span></div>`;
    }).join('');
  }

  // número para link do WhatsApp: só dígitos, com 258 (Moçambique) se faltar
  function numeroWhatsApp(n) {
    let d = String(n || '').replace(/\D/g, '');
    if (!d) return '';
    if (d.length === 9 && d.startsWith('8')) d = '258' + d;
    return d;
  }

  function linkSite(url) {
    if (!url) return '';
    return /^https?:\/\//i.test(url) ? url : 'https://' + url;
  }

  // mapa (sem chave de API) a partir das coordenadas ou da morada
  function destinoMapa(p) {
    if (p.latitude != null && p.longitude != null) return `${p.latitude},${p.longitude}`;
    return [p.morada, p.city, p.province, 'Moçambique'].filter(Boolean).join(', ');
  }
  function mapaEmbed(p) {
    return `https://maps.google.com/maps?q=${encodeURIComponent(destinoMapa(p))}&z=15&output=embed`;
  }
  function linkComoChegar(p) {
    return `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(destinoMapa(p))}`;
  }

  // pede a localização ao navegador
  function obterLocalizacao() {
    return new Promise((ok, erro) => {
      if (!navigator.geolocation) { erro(new Error('O navegador não permite obter a localização.')); return; }
      navigator.geolocation.getCurrentPosition(
        pos => ok({ latitude: +pos.coords.latitude.toFixed(6), longitude: +pos.coords.longitude.toFixed(6) }),
        () => erro(new Error('Não foi possível obter a localização. Verifica se deste permissão.')),
        { enableHighAccuracy: true, timeout: 15000 }
      );
    });
  }

  return { PROVINCIAS, SETORES, GENEROS, DIAS, esc, opcoes, horarioPadrao, camposHorario, alternarDia,
           lerHorario, estadoAgora, horarioEmLinhas, numeroWhatsApp, linkSite, mapaEmbed, linkComoChegar,
           obterLocalizacao };
})();
