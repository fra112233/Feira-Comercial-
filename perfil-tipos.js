/* ============================================================
   Feira Comercial — perfil-tipos.js
   Mostra e edita o perfil de forma diferente para EMPRESA e PESSOA.
   Usado por perfil.html (precisa de perfil-campos.js e supabase-config.js).
   ============================================================ */

let perfilAtual = null;          // linha da tabela "perfis" do perfil mostrado
const VER_ID = new URLSearchParams(location.search).get('id'); // perfil.html?id=... → perfil de outra pessoa/empresa
let alvoId = null;               // id do perfil mostrado
let modoVisita = !!VER_ID;       // true quando vejo o perfil de outra pessoa
let localizacaoEditada;          // undefined = não mexer; null = remover; {latitude, longitude} = nova

const ehEmpresa = p => p && p.type === 'empresa';

function linhaInfo(icone, rotulo, valorHtml) {
  if (!valorHtml) return '';
  return `<div class="info-item">
            <div class="info-icon"><i class="fas ${icone}"></i></div>
            <div class="info-label">${rotulo}</div>
            <div class="info-value" style="text-align:right;word-break:break-word;">${valorHtml}</div>
          </div>`;
}

function moradaCompleta(p) {
  return [p.morada, p.city, p.province].filter(Boolean).join(', ');
}

function botoesContacto(p) {
  const e = FCP.esc;
  const wa = FCP.numeroWhatsApp(p.whatsapp || (ehEmpresa(p) ? '' : p.phone));
  const estilo = 'display:inline-flex;align-items:center;gap:6px;padding:8px 12px;border-radius:var(--radius-md);font-size:13px;font-weight:600;text-decoration:none;';
  return `<div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:12px;">
      ${p.phone ? `<a href="tel:${e(p.phone.replace(/\s/g, ''))}" style="${estilo}background:var(--primary);color:#fff;"><i class="fas fa-phone"></i> Ligar</a>` : ''}
      ${wa ? `<a href="https://wa.me/${wa}" target="_blank" rel="noopener" style="${estilo}background:#25d366;color:#fff;"><i class="fab fa-whatsapp"></i> WhatsApp</a>` : ''}
      ${p.email ? `<a href="mailto:${e(p.email)}" style="${estilo}background:var(--bg-tertiary);color:var(--text-primary);"><i class="fas fa-envelope"></i> E-mail</a>` : ''}
    </div>`;
}

// ---------- cartões de informação ----------
function cartoesEmpresa(p, completo) {
  const e = FCP.esc;
  const estado = FCP.estadoAgora(p.opening_hours);
  const site = p.website ? `<a href="${e(FCP.linkSite(p.website))}" target="_blank" rel="noopener" style="color:var(--primary);">${e(p.website)}</a>` : '';
  const temLocal = p.latitude != null || p.morada;

  const contactos = `
    <div class="info-card">
      <div class="info-card-title"><i class="fas fa-address-book"></i> Contactos</div>
      ${linhaInfo('fa-phone', 'Telefone', e(p.phone))}
      ${linhaInfo('fa-comment', 'WhatsApp', e(p.whatsapp))}
      ${linhaInfo('fa-envelope', 'E-mail', e(p.email))}
      ${linhaInfo('fa-globe', 'Website', site)}
      ${linhaInfo('fa-thumbs-up', 'Facebook', e(p.facebook))}
      ${linhaInfo('fa-camera', 'Instagram', e(p.instagram))}
      ${botoesContacto(p)}
    </div>`;

  const horario = p.opening_hours ? `
    <div class="info-card">
      <div class="info-card-title"><i class="fas fa-clock"></i> Horário de trabalho</div>
      ${estado ? `<div style="display:inline-block;padding:4px 10px;border-radius:999px;font-size:12px;font-weight:700;margin-bottom:10px;
                  background:${estado.aberto ? 'rgba(34,197,94,.15)' : 'rgba(239,68,68,.15)'};
                  color:${estado.aberto ? '#16a34a' : '#dc2626'};">${e(estado.texto)}</div>` : ''}
      <div style="font-size:13px;color:var(--text-secondary);">${FCP.horarioEmLinhas(p.opening_hours)}</div>
    </div>` : '';

  const local = temLocal ? `
    <div class="info-card">
      <div class="info-card-title"><i class="fas fa-map-marker-alt"></i> Localização</div>
      <div style="font-size:13px;color:var(--text-secondary);margin-bottom:10px;">${e(moradaCompleta(p))}</div>
      ${completo ? `<iframe src="${FCP.mapaEmbed(p)}" loading="lazy" referrerpolicy="no-referrer-when-downgrade"
                     style="width:100%;height:220px;border:0;border-radius:var(--radius-md);"></iframe>` : ''}
      <a href="${FCP.linkComoChegar(p)}" target="_blank" rel="noopener"
         style="display:inline-flex;align-items:center;gap:6px;margin-top:10px;padding:8px 12px;border-radius:var(--radius-md);
                background:var(--primary);color:#fff;font-size:13px;font-weight:600;text-decoration:none;">
         <i class="fas fa-route"></i> Como chegar</a>
    </div>` : '';

  const sobre = completo ? `
    <div class="info-card">
      <div class="info-card-title"><i class="fas fa-building"></i> Sobre a empresa</div>
      ${linhaInfo('fa-industry', 'Setor', e(p.sector))}
      ${linhaInfo('fa-id-card', 'NUIT', e(p.nuit))}
      ${p.bio ? `<p style="font-size:13px;color:var(--text-secondary);margin-top:10px;line-height:1.5;">${e(p.bio)}</p>` : ''}
    </div>` : '';

  return completo ? sobre + contactos + horario + local : contactos + horario + local;
}

function cartoesPessoa(p) {
  const e = FCP.esc;
  return `
    <div class="info-card">
      <div class="info-card-title"><i class="fas fa-user"></i> Informações pessoais</div>
      ${linhaInfo('fa-user', 'Nome', e(p.full_name))}
      ${linhaInfo('fa-venus-mars', 'Género', e(p.gender))}
      ${linhaInfo('fa-mobile-alt', 'Celular', e(p.phone))}
      ${linhaInfo('fa-envelope', 'E-mail', e(p.email))}
      ${linhaInfo('fa-home', 'Morada', e(moradaCompleta(p)))}
      ${botoesContacto(p)}
    </div>`;
}

// ---------- aplicar o perfil à página ----------
function aplicarPerfil() {
  const p = perfilAtual;
  if (!p) return;
  ajustarPublicar();
  const e = FCP.esc;

  if (modoVisita) {
    // perfil de outra pessoa: não mexer no meu nome/foto guardados
    setTxt('userName', p.full_name || 'Utilizador');
    const foto = p.avatar_url || ('https://ui-avatars.com/api/?name=' + encodeURIComponent(p.full_name || 'U') + '&background=random&color=fff&size=256');
    const img = document.getElementById('profileImg'); if (img) img.src = foto;
  } else {
    if (p.full_name) definirNome(p.full_name);
    if (p.avatar_url) definirAvatar(p.avatar_url);
  }
  if (p.username) setTxt('profileHandle', '@' + p.username);

  const bio = document.getElementById('dispBio');
  if (bio) {
    bio.textContent = p.bio || (ehEmpresa(p) ? (p.sector || '') : '');
    bio.style.display = bio.textContent ? '' : 'none';
  }
  setTxt('dispMorada', moradaCompleta(p) || 'Localização não indicada');

  const site = document.getElementById('dispWebsite');
  if (site) {
    site.closest('.profile-meta-item').style.display = p.website ? '' : 'none';
    site.innerHTML = p.website ? `<a href="${e(FCP.linkSite(p.website))}" target="_blank" rel="noopener" style="color:inherit;">${e(p.website)}</a>` : '';
  }
  if (p.created_at) {
    const d = new Date(p.created_at);
    setTxt('dispDesde', 'Membro desde ' + d.toLocaleDateString('pt-PT', { month: 'short', year: 'numeric' }));
  }

  const selo = document.getElementById('tipoBadge');
  if (selo) {
    selo.innerHTML = ehEmpresa(p)
      ? `<span style="display:inline-flex;align-items:center;gap:6px;padding:4px 12px;border-radius:999px;background:rgba(99,102,241,.15);color:var(--primary);font-size:12px;font-weight:700;">
           <i class="fas fa-building"></i> Empresa${p.sector ? ' · ' + e(p.sector) : ''}</span>`
      : `<span style="display:inline-flex;align-items:center;gap:6px;padding:4px 12px;border-radius:999px;background:var(--bg-tertiary);color:var(--text-secondary);font-size:12px;font-weight:700;">
           <i class="fas fa-user"></i> Pessoa</span>`;
  }

  const info = document.getElementById('infoTipo');
  if (info) info.innerHTML = ehEmpresa(p) ? cartoesEmpresa(p, true) : cartoesPessoa(p);
  const lado = document.getElementById('sidebarTipo');
  if (lado) lado.innerHTML = ehEmpresa(p) ? cartoesEmpresa(p, false) : cartoesPessoa(p);

  const tabInfo = document.querySelector('.tab-btn[onclick*="\'info\'"]');
  if (tabInfo) tabInfo.innerHTML = ehEmpresa(p) ? '<i class="fas fa-building"></i> Empresa' : '<i class="fas fa-info-circle"></i> Sobre';
}

// ---------- editar ----------
function campo(id, rotulo, valor, tipo = 'text', extra = '') {
  return `<div class="form-group"><label for="${id}">${rotulo}</label>
          <input type="${tipo}" id="${id}" value="${FCP.esc(valor || '')}" ${extra}></div>`;
}
function lista(id, rotulo, opcoes, valor) {
  return `<div class="form-group"><label for="${id}">${rotulo}</label>
          <select id="${id}" style="width:100%;padding:10px;background:var(--bg-tertiary);border:1px solid var(--border-color);border-radius:var(--radius-md);color:var(--text-primary);font-size:14px;">
            ${FCP.opcoes(opcoes, valor, 'Escolher...')}</select></div>`;
}

function textoLocalizacao() {
  const p = perfilAtual || {};
  const loc = localizacaoEditada === undefined
    ? (p.latitude != null ? { latitude: p.latitude, longitude: p.longitude } : null)
    : localizacaoEditada;
  return loc ? `📍 Guardada: ${loc.latitude}, ${loc.longitude}` : 'Sem localização no mapa (usa-se a morada).';
}

async function editarUsarLocalizacao() {
  const hint = document.getElementById('ed-loc-hint');
  hint.textContent = 'A obter localização...';
  try {
    localizacaoEditada = await FCP.obterLocalizacao();
    hint.textContent = textoLocalizacao();
  } catch (err) { hint.textContent = err.message; }
}
function editarRemoverLocalizacao() {
  localizacaoEditada = null;
  document.getElementById('ed-loc-hint').textContent = textoLocalizacao();
}

function loadEditFormData() {
  const p = perfilAtual || {};
  const empresa = ehEmpresa(p);
  localizacaoEditada = undefined;
  const corpo = document.getElementById('editTipo');
  if (!corpo) return;

  let html = `<div class="form-section-title" style="margin-top:0;border-top:none;padding-top:0;">${empresa ? 'Empresa' : 'Dados pessoais'}</div>`;
  html += campo('ed-nome', empresa ? 'Nome da empresa' : 'Nome completo', p.full_name);
  if (empresa) {
    html += lista('ed-setor', 'Setor de atividade', FCP.SETORES, p.sector);
    html += `<div class="form-group"><label for="ed-bio">O que a empresa faz</label>
             <textarea id="ed-bio" placeholder="Produtos, serviços, entregas...">${FCP.esc(p.bio || '')}</textarea></div>`;
    html += campo('ed-nuit', 'NUIT', p.nuit, 'text', 'inputmode="numeric" maxlength="9"');
  } else {
    html += lista('ed-genero', 'Género', FCP.GENEROS, p.gender);
    html += `<div class="form-group"><label for="ed-bio">Sobre mim <span style="font-weight:400;color:var(--text-tertiary)">(opcional)</span></label>
             <textarea id="ed-bio">${FCP.esc(p.bio || '')}</textarea></div>`;
  }

  html += `<div class="form-section-title">Contacto</div>`;
  html += campo('ed-telefone', empresa ? 'Telefone' : 'Celular', p.phone, 'tel', 'placeholder="+258 8X XXX XXXX"');
  if (empresa) {
    html += campo('ed-whatsapp', 'WhatsApp', p.whatsapp, 'tel', 'placeholder="+258 8X XXX XXXX"');
    html += campo('ed-website', 'Website', p.website, 'text', 'placeholder="www.minhaempresa.co.mz"');
    html += campo('ed-facebook', 'Facebook', p.facebook, 'text', 'placeholder="facebook.com/minhaempresa"');
    html += campo('ed-instagram', 'Instagram', p.instagram, 'text', 'placeholder="@minhaempresa"');
  }
  html += `<div class="form-group"><label>E-mail</label>
           <input type="email" value="${FCP.esc(p.email || '')}" disabled style="opacity:.7;">
           <small style="color:var(--text-tertiary);font-size:12px;">É o e-mail da conta (usado para entrar).</small></div>`;

  html += `<div class="form-section-title">${empresa ? 'Localização' : 'Morada'}</div>`;
  html += campo('ed-morada', 'Morada', p.morada, 'text', 'placeholder="Av. / Rua, número, bairro"');
  html += lista('ed-provincia', 'Província', FCP.PROVINCIAS, p.province);
  html += campo('ed-cidade', 'Cidade / Distrito', p.city);
  if (empresa) {
    html += `<div class="form-group"><label>Ponto no mapa</label>
             <div style="display:flex;gap:8px;flex-wrap:wrap;">
               <button type="button" class="btn btn-secondary" onclick="editarUsarLocalizacao()"><i class="fas fa-location-crosshairs"></i> Usar localização atual</button>
               <button type="button" class="btn btn-secondary" onclick="editarRemoverLocalizacao()">Remover</button>
             </div>
             <small id="ed-loc-hint" style="display:block;margin-top:6px;color:var(--text-tertiary);font-size:12px;">${FCP.esc(textoLocalizacao())}</small></div>`;
    html += `<div class="form-section-title">Horário de trabalho</div>
             <div class="form-group">${FCP.camposHorario('ed', p.opening_hours || FCP.horarioPadrao())}</div>`;
  }
  corpo.innerHTML = html;
}

async function savePerfil() {
  const p = perfilAtual;
  if (!p || !meuId) { alert('Sessão expirada. Entra novamente.'); return; }
  const v = id => { const el = document.getElementById(id); return el ? el.value.trim() : undefined; };
  const empresa = ehEmpresa(p);

  const upd = {
    full_name: v('ed-nome') || p.full_name,
    bio: v('ed-bio') || null,
    phone: v('ed-telefone') || null,
    morada: v('ed-morada') || null,
    province: v('ed-provincia') || null,
    city: v('ed-cidade') || null
  };
  if (empresa) {
    Object.assign(upd, {
      sector: v('ed-setor') || null,
      nuit: v('ed-nuit') || null,
      whatsapp: v('ed-whatsapp') || null,
      website: v('ed-website') || null,
      facebook: v('ed-facebook') || null,
      instagram: v('ed-instagram') || null,
      opening_hours: FCP.lerHorario('ed')
    });
    if (localizacaoEditada !== undefined) {
      upd.latitude = localizacaoEditada ? localizacaoEditada.latitude : null;
      upd.longitude = localizacaoEditada ? localizacaoEditada.longitude : null;
    }
  } else {
    upd.gender = v('ed-genero') || null;
  }

  const botao = document.querySelector('#modalEdit .btn-primary');
  if (botao) { botao.disabled = true; botao.textContent = 'A guardar...'; }
  const { data, error } = await getSB().from('perfis').update(upd).eq('id', meuId).select().maybeSingle();
  if (botao) { botao.disabled = false; botao.textContent = 'Guardar'; }
  if (error) { alert('Não foi possível guardar: ' + error.message); return; }

  perfilAtual = data || Object.assign({}, p, upd);
  guardarPerfilLocal();
  aplicarPerfil();
  try { localStorage.removeItem('fc_profile'); sessionStorage.removeItem('fc_feed_cache_v1'); } catch (e) {}
  closeModals();
  showToast('Perfil atualizado com sucesso!');
}

// cache local do perfil (só para mostrar logo ao abrir a página)
function guardarPerfilLocal() {
  if (!perfilAtual) return;
  try {
    localStorage.setItem('fc_perfil_v2', JSON.stringify(perfilAtual));
    if (perfilAtual.full_name) localStorage.setItem('fc_name', perfilAtual.full_name);
  } catch (e) {}
}

function carregarPerfilLocal() {
  try {
    const p = JSON.parse(localStorage.getItem('fc_perfil_v2') || 'null');
    if (p && p.id) { perfilAtual = p; aplicarPerfil(); }
  } catch (e) {}
}

// número real de seguidores / seguindo (tabela followers)
async function contarSeguidores() {
  if (!alvoId) return;
  const sb = getSB();
  const [a, b] = await Promise.all([
    sb.from('followers').select('id', { count: 'exact', head: true }).eq('following_id', alvoId),
    sb.from('followers').select('id', { count: 'exact', head: true }).eq('follower_id', alvoId)
  ]);
  if (!a.error) setTxt('seguidoresCount', a.count || 0);
  if (!b.error) setTxt('seguindoCount', b.count || 0);
}

// ---------- ver o perfil de outra pessoa / empresa ----------
function prepararModoVisita() {
  modoVisita = true;
  const dono = document.getElementById('acoesDono'); if (dono) dono.style.display = 'none';
  const visita = document.getElementById('acoesVisita'); if (visita) visita.style.display = '';
  document.querySelectorAll('.profile-pic-edit, .create-post-card').forEach(el => el.style.display = 'none');
  const vazio = document.getElementById('emptyState');
  if (vazio) vazio.innerHTML = '<p>Sem publicações nas últimas 36 horas.</p>';
}

function mostrarModoDono() {
  modoVisita = false;
  const dono = document.getElementById('acoesDono'); if (dono) dono.style.display = '';
  const visita = document.getElementById('acoesVisita'); if (visita) visita.style.display = 'none';
  document.querySelectorAll('.profile-pic-edit, .create-post-card').forEach(el => el.style.display = '');
  ajustarPublicar();
}

// Só as empresas fazem publicações no feed (as pessoas usam os Stories)
function ajustarPublicar() {
  if (modoVisita) return;
  const empresa = ehEmpresa(perfilAtual);
  const b = document.getElementById('btnPublicar'); if (b) b.style.display = empresa ? '' : 'none';
  document.querySelectorAll('.create-post-card').forEach(el => el.style.display = empresa ? '' : 'none');
}

let sigoEste = false;
function desenharBotaoSeguir() {
  const b = document.getElementById('btnSeguir');
  if (!b) return;
  b.innerHTML = sigoEste ? '<i class="fas fa-check"></i> A seguir' : '<i class="fas fa-plus"></i> Seguir';
  b.className = 'btn ' + (sigoEste ? 'btn-secondary' : 'btn-primary');
}

async function verificarSeSigo() {
  const { data } = await getSB().from('followers').select('id')
    .eq('follower_id', meuId).eq('following_id', alvoId).maybeSingle();
  sigoEste = !!data;
  desenharBotaoSeguir();
}

async function alternarSeguirPerfil() {
  if (!meuId || !alvoId || meuId === alvoId) return;
  const b = document.getElementById('btnSeguir'); if (b) b.disabled = true;
  const sb = getSB();
  const { error } = sigoEste
    ? await sb.from('followers').delete().eq('follower_id', meuId).eq('following_id', alvoId)
    : await sb.from('followers').insert({ follower_id: meuId, following_id: alvoId, created_at: Date.now() });
  if (b) b.disabled = false;
  if (error) { alert('Não foi possível: ' + error.message); return; }
  sigoEste = !sigoEste;
  desenharBotaoSeguir();
  contarSeguidores();
  showToast(sigoEste ? 'Agora segues ' + (perfilAtual ? perfilAtual.full_name : '') : 'Deixaste de seguir');
}
