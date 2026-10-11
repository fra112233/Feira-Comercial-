/* ============================================================
   Feira Comercial — supabase-config.js (partilhado por TODAS as páginas)
   ============================================================ */

const SUPABASE_URL = 'https://bljnkwrhqnpawclybqrw.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_qvUvtBjpAKtMevafHRJe8g_W-aUkOb0';

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

window.FC = window.FC || {};

/* ---------- Sessão ---------- */
FC.getSession = async function () {
  const { data: { session } } = await supabaseClient.auth.getSession();
  return session;
};

FC.requireAuth = async function (loginPage = 'Portal.html') {
  const session = await FC.getSession();
  if (!session) {
    // volta a esta página depois de entrar (ex.: vídeo ou anúncio partilhado)
    const aqui = (location.pathname.split('/').pop() || 'index.html') + location.search + location.hash;
    window.location.href = loginPage + (aqui && aqui !== 'index.html' ? '?voltar=' + encodeURIComponent(aqui) : '');
    return null;
  }
  return session;
};

FC.signOut = async function () {
  await supabaseClient.auth.signOut();
  localStorage.removeItem('fc_profile');
  window.location.href = 'Portal.html';
};

/* ---------- Ler um perfil com os campos que posso ver ----------
   O próprio vê tudo; dos outros só vêm os dados públicos (e os contactos
   comerciais, se for empresa). NUIT, e-mail e celular pessoais ficam privados. */
FC.lerPerfil = async function (id) {
  const r = await supabaseClient.rpc('perfil_completo', { pid: id });
  if (!r.error) return { data: r.data || null, error: null };
  // base de dados ainda sem a função (antes da migração 011)
  if (/perfil_completo|function|schema cache/i.test(r.error.message || '')) {
    return await supabaseClient.from('perfis').select('*').eq('id', id).maybeSingle();
  }
  return { data: null, error: r.error };
};

/* ---------- Perfil (tabela "perfis", com cache local) ---------- */
FC.loadMyProfile = async function () {
  const session = await FC.getSession();
  if (!session) return null;

  // cache só para render imediato, e só se for do utilizador atual
  const cached = localStorage.getItem('fc_profile');
  if (cached) {
    try {
      const c = JSON.parse(cached);
      if (c && c.id === session.user.id) FC.me = c;
    } catch (e) {}
  }

  const { data, error } = await FC.lerPerfil(session.user.id);

  if (!error && data) {
    FC.me = { ...data, email: session.user.email };
    localStorage.setItem('fc_profile', JSON.stringify(FC.me));
  } else if (!FC.me) {
    FC.me = {
      id: session.user.id,
      full_name: session.user.email.split('@')[0],
      email: session.user.email,
      avatar_url: null
    };
  }
  return FC.me;
};

/* ---------- Identidade visual: FOTO + NOME ---------- */
FC.applyIdentity = async function (opts = {}) {
  const me = await FC.loadMyProfile();
  if (!me) return null;

  const avatarUrl = me.avatar_url ||
    ('https://ui-avatars.com/api/?name=' + encodeURIComponent(me.full_name || 'U') +
     '&background=random&color=fff&size=256');
  const name = me.full_name || 'Utilizador';

  document.querySelectorAll('[data-fc-avatar]').forEach(img => { img.src = avatarUrl; });
  document.querySelectorAll('[data-fc-name]').forEach(el => { el.textContent = name; });
  document.querySelectorAll('[data-fc-email]').forEach(el => { el.textContent = me.email || ''; });

  if (opts.avatar) { const a = document.querySelector(opts.avatar); if (a) a.src = avatarUrl; }
  if (opts.name)  { const n = document.querySelector(opts.name);  if (n) n.textContent = name; }

  return me;
};

/* ---------- Upload para Storage ---------- */
FC.uploadImage = async function (bucket, file, path) {
  const { error } = await supabaseClient.storage
    .from(bucket).upload(path, file, { upsert: true, contentType: file.type });
  if (error) throw error;
  const { data } = supabaseClient.storage.from(bucket).getPublicUrl(path);
  return data.publicUrl;
};

/* ---------- Mensagens por ler (bolinha vermelha nos links de Mensagens) ---------- */
// Número de mensagens por ler: ícones de mensagens, item do menu ☰, ponto no botão ☰
// e no título do separador "(2) Feira Comercial". Tempo real + verificação de reserva.
FC._msgsNaoLidas = 0;
FC.badgeMensagens = async function () {
  if (FC._badgeLigado) return;
  const session = await FC.getSession();
  if (!session) return;
  FC._badgeLigado = true;
  const uid = session.user.id;

  if (!document.getElementById('fc-badge-css')) {
    const css = document.createElement('style');
    css.id = 'fc-badge-css';
    css.textContent =
      '.fc-msg-badge{position:absolute;top:-4px;right:-6px;min-width:18px;height:18px;padding:0 5px;border-radius:9px;background:#ef4444;color:#fff;font-size:11px;font-weight:700;line-height:18px;text-align:center;box-shadow:0 0 0 2px var(--bg-card,#18191a)}' +
      '.fc-menu-ponto{position:absolute;top:4px;right:4px;width:10px;height:10px;border-radius:50%;background:#ef4444;box-shadow:0 0 0 2px var(--bg-card,#18191a);pointer-events:none}' +
      '.fc-msg-menu{margin-left:auto;min-width:22px;height:22px;padding:0 7px;border-radius:11px;background:#ef4444;color:#fff;font-size:12px;font-weight:700;line-height:22px;text-align:center}';
    document.head.appendChild(css);
  }

  const mostrar = n => {
    FC._msgsNaoLidas = n;
    const txt = n > 99 ? '99+' : String(n);
    document.querySelectorAll('[data-fc-msgs]').forEach(el => { el.textContent = txt; el.style.display = n ? '' : 'none'; });
    document.querySelectorAll('[onclick*="FCMenu.abrir"]').forEach(b => {
      let d = b.querySelector('.fc-menu-ponto');
      if (!d) { d = document.createElement('span'); d.className = 'fc-menu-ponto'; if (getComputedStyle(b).position === 'static') b.style.position = 'relative'; b.appendChild(d); }
      d.style.display = n ? '' : 'none';
    });
    const base = document.title.replace(/^\(\d+\+?\) /, '');
    document.title = n ? '(' + txt + ') ' + base : base;
    document.dispatchEvent(new CustomEvent('fc:mensagens', { detail: n }));
  };
  let aContar = null;
  const contar = () => {
    clearTimeout(aContar);
    aContar = setTimeout(async () => {
      const { count, error } = await supabaseClient.from('messages')
        .select('id', { count: 'exact', head: true })
        .eq('receiver_id', uid).is('read_at', null).eq('deleted', false).eq('cleared_by_receiver', false);
      if (!error) mostrar(count || 0);
    }, 250);
  };
  contar();
  supabaseClient.channel('badge-msgs-' + uid)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'messages', filter: `receiver_id=eq.${uid}` }, contar)
    .subscribe();
  // reserva: se a ligação em tempo real cair (dados móveis), volta a contar
  setInterval(() => { if (document.visibilityState === 'visible') contar(); }, 45000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') contar(); });
  window.addEventListener('focus', contar);
};

/* ---------- Quem está em direto (Live) ----------
   Mostra em todas as páginas: uma pílula "🔴 AO VIVO · Loja X está em direto"
   e um selo nos links/itens "Live". Atualiza em tempo real. */
FC._livesAgora = [];
FC.vigiarLives = async function () {
  if (FC._livesLigado) return;
  const session = await FC.getSession();
  if (!session) return;
  FC._livesLigado = true;
  const uid = session.user.id;
  const naPaginaLive = /live\.html/i.test(location.pathname);

  if (!document.getElementById('fc-live-css')) {
    const css = document.createElement('style');
    css.id = 'fc-live-css';
    css.textContent =
      '#fc-aovivo{position:fixed;left:0;right:0;margin:0 auto;width:max-content;z-index:4500;display:flex;align-items:center;gap:8px;max-width:calc(100vw - 24px);box-sizing:border-box;' +
      'background:#18181b;color:#f4f4f5;border:1px solid rgba(239,68,68,.45);border-radius:999px;padding:6px 6px 6px 12px;box-shadow:0 8px 24px rgba(0,0,0,.35);' +
      'font:600 13px Inter,"Segoe UI",system-ui,sans-serif;animation:fcAoVivoEntra .25s ease-out}' +
      '@keyframes fcAoVivoEntra{from{opacity:0;transform:translateY(-8px)}to{opacity:1;transform:none}}' +
      '#fc-aovivo a{color:inherit;text-decoration:none;display:flex;align-items:center;gap:8px;min-width:0}' +
      '#fc-aovivo .sl{background:#ef4444;color:#fff;font-size:10.5px;font-weight:800;letter-spacing:.06em;padding:2px 7px;border-radius:6px;flex-shrink:0}' +
      '#fc-aovivo .tx{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
      '#fc-aovivo .vr{color:#f3c64e;flex-shrink:0}' +
      '#fc-aovivo img{width:24px;height:24px;border-radius:50%;object-fit:cover;flex-shrink:0;box-shadow:0 0 0 2px #ef4444}' +
      '#fc-aovivo button{border:none;background:#2c2c34;color:#a1a1aa;width:24px;height:24px;border-radius:50%;cursor:pointer;flex-shrink:0;font-size:14px;line-height:1}' +
      '.fc-aovivo-ponto{display:inline-block;width:8px;height:8px;border-radius:50%;background:#ef4444;animation:fcPisca 1.2s infinite}' +
      '@keyframes fcPisca{50%{opacity:.3}}' +
      '.fc-aovivo-chip{display:inline-flex;align-items:center;gap:5px;margin-left:auto;background:rgba(239,68,68,.15);color:#ef4444;font-size:11px;font-weight:800;' +
      'padding:2px 8px;border-radius:999px;white-space:nowrap;max-width:150px;overflow:hidden;text-overflow:ellipsis}';
    document.head.appendChild(css);
  }

  const texto = lista => {
    const n = lista.map(l => (l.autor && l.autor.full_name) || 'Uma empresa');
    if (n.length === 1) return n[0] + ' está em direto';
    if (n.length === 2) return n[0] + ' e ' + n[1] + ' estão em direto';
    return n[0] + ', ' + n[1] + ' e mais ' + (n.length - 2) + ' estão em direto';
  };
  const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');

  const posicionar = () => {
    const el = document.getElementById('fc-aovivo'); if (!el) return;
    const cab = document.querySelector('header, nav.top-nav, .topbar');
    const fundo = cab ? cab.getBoundingClientRect().bottom : 0;
    el.style.top = Math.max(10, fundo + 8) + 'px';
  };
  window.addEventListener('scroll', () => requestAnimationFrame(posicionar), { passive: true });
  window.addEventListener('resize', posicionar);

  const mostrar = lista => {
    FC._livesAgora = lista;
    // selos nos links para a Live
    document.querySelectorAll('a[href="live.html"], a[href^="live.html?"]').forEach(a => {
      let c = a.querySelector('.fc-aovivo-chip');
      if (!lista.length) { if (c) c.remove(); return; }
      if (!c) { c = document.createElement('span'); c.className = 'fc-aovivo-chip'; a.appendChild(c); }
      c.innerHTML = '<span class="fc-aovivo-ponto"></span>' + (lista.length === 1 ? esc((lista[0].autor && lista[0].autor.full_name) || 'AO VIVO') : lista.length + ' ao vivo');
    });
    document.dispatchEvent(new CustomEvent('fc:lives', { detail: lista }));
    // pílula (não aparece na própria página da Live nem se a pessoa a fechou para estas lives)
    let el = document.getElementById('fc-aovivo');
    const chave = lista.map(l => l.id).sort().join(',');
    let fechada = '';
    try { fechada = sessionStorage.getItem('fc_aovivo_fechado') || ''; } catch (e) {}
    if (!lista.length || naPaginaLive || fechada === chave) { if (el) el.remove(); return; }
    if (!el) { el = document.createElement('div'); el.id = 'fc-aovivo'; el.setAttribute('role', 'status'); document.body.appendChild(el); }
    const l0 = lista[0], a0 = l0.autor || {};
    const foto = a0.avatar_url || ('https://ui-avatars.com/api/?name=' + encodeURIComponent(a0.full_name || 'L') + '&background=random&color=fff&size=64');
    el.innerHTML = '<a href="live.html' + (lista.length === 1 ? '?id=' + esc(l0.id) : '') + '"><img src="' + esc(foto) + '" alt=""><span class="sl">AO VIVO</span>' +
      '<span class="tx">' + esc(texto(lista)) + '</span><span class="vr">Ver ›</span></a>' +
      '<button type="button" aria-label="Fechar" title="Fechar">×</button>';
    el.querySelector('button').onclick = () => { try { sessionStorage.setItem('fc_aovivo_fechado', chave); } catch (e) {} el.remove(); };
    posicionar();
  };

  let t = null;
  const carregar = () => {
    clearTimeout(t);
    t = setTimeout(async () => {
      const limite = new Date(Date.now() - 90 * 1000).toISOString();
      const { data, error } = await supabaseClient.from('lives')
        .select('id,user_id,titulo,autor:perfis!lives_user_id_fkey(full_name,avatar_url)')
        .eq('estado', 'ao_vivo').gte('atualizado_em', limite)
        .order('started_at', { ascending: false }).limit(6);
      if (!error) mostrar((data || []).filter(l => l.user_id !== uid));
    }, 300);
  };
  carregar();
  supabaseClient.channel('lives-agora-' + uid)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'lives' }, carregar)
    .subscribe();
  setInterval(() => { if (document.visibilityState === 'visible') carregar(); }, 60000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') carregar(); });
};

/* ---------- Mensalidade das empresas ---------- */
// Devolve { empresa, ativa (paga/em período grátis), pode (pode usar as funções pagas),
//           ate (Date|null), dias (dias que faltam) }.
// Contas pessoais: não pagam (ativa e pode = true).
// Se a configuração 'bloquear_sem_pagamento' não for 'sim', quem não paga só recebe avisos.
FC._config = FC._config || null;
FC.carregarConfig = async function () {
  if (FC._config) return FC._config;
  try {
    const { data, error } = await supabaseClient.from('config').select('chave,valor');
    if (!error && data) { FC._config = {}; data.forEach(r => FC._config[r.chave] = r.valor); }
  } catch (e) {}
  return FC._config || {};
};
FC.mensalidade = function (me) {
  me = me || FC.me || {};
  if (me.type !== 'empresa') return { empresa: false, ativa: true, pode: true, ate: null, dias: null };
  // sem a coluna ainda (antes da migração 010) não mostramos nada
  if (!('assinatura_ate' in me)) return { empresa: true, ativa: true, pode: true, ate: null, dias: null };
  const ate = me.assinatura_ate ? new Date(me.assinatura_ate) : null;
  const dias = ate ? Math.ceil((ate - Date.now()) / 86400000) : 0;
  const ativa = !!ate && ate > new Date();
  const bloqueia = !!(FC._config && FC._config.bloquear_sem_pagamento === 'sim');
  return { empresa: true, ativa, pode: ativa || !bloqueia, ate, dias };
};

// Aviso a cada 48 horas às empresas com a mensalidade a terminar (≤3 dias) ou terminada
FC.lembreteMensalidade = function (me) {
  const m = FC.mensalidade(me);
  if (!m.empresa || !m.ate || (m.ativa && m.dias > 3)) return;
  if (/mensalidade\.html/.test(location.pathname)) return;
  const chave = 'fc_lembrete_mens_' + me.id;
  try { if (Date.now() - Number(localStorage.getItem(chave) || 0) < 48 * 3600 * 1000) return; localStorage.setItem(chave, String(Date.now())); } catch (e) { return; }
  const quando = m.ativa ? (m.dias <= 1 ? 'termina amanhã' : 'termina em ' + m.dias + ' dias') : 'terminou';
  const el = document.createElement('div');
  el.id = 'fc-lembrete';
  el.innerHTML =
    '<style>#fc-lembrete{position:fixed;inset:0;z-index:6000;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;padding:16px;font-family:Inter,"Segoe UI",system-ui,sans-serif}' +
    '#fc-lembrete .c{background:#16161a;color:#f4f4f5;border:1px solid rgba(243,198,78,.35);border-radius:20px;max-width:380px;width:100%;padding:24px;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.5)}' +
    '#fc-lembrete .i{font-size:40px}#fc-lembrete h3{margin:8px 0 6px;font-size:19px}#fc-lembrete p{color:#a1a1aa;font-size:14px;line-height:1.5;margin:0 0 18px}' +
    '#fc-lembrete a,#fc-lembrete button{display:block;width:100%;padding:13px;border-radius:12px;font:inherit;font-weight:700;font-size:15px;cursor:pointer;text-decoration:none;box-sizing:border-box}' +
    '#fc-lembrete a{background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#000;border:none;margin-bottom:8px}#fc-lembrete button{background:#1f1f25;color:#f4f4f5;border:1px solid #2c2c34}</style>' +
    '<div class="c" role="dialog" aria-modal="true"><div class="i">💳</div><h3>A mensalidade ' + quando + '</h3>' +
    '<p>Pague <b style="color:#f3c64e">100 MT</b> por M-Pesa ou e-Mola para a sua empresa <b>não ficar sem acesso</b> a publicações, anúncios e Live.</p>' +
    '<a href="mensalidade.html">Pagar agora</a><button type="button">Mais tarde</button></div>';
  el.querySelector('button').onclick = () => el.remove();
  el.addEventListener('click', e => { if (e.target === el) el.remove(); });
  document.body.appendChild(el);
};

/* ---------- Arranque padrão ---------- */
FC.boot = async function (opts = {}) {
  const session = await FC.requireAuth(opts.loginPage);
  if (!session) return null;
  const me = await FC.applyIdentity(opts);
  FC.badgeMensagens();
  FC.vigiarLives();
  if (me && me.type === 'empresa') FC.carregarConfig().then(() => FC.lembreteMensalidade(me));
  return me;
};
