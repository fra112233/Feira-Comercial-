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

  const { data, error } = await supabaseClient
    .from('perfis')
    .select('*')
    .eq('id', session.user.id)
    .maybeSingle();

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
FC.badgeMensagens = async function () {
  const els = document.querySelectorAll('[data-fc-msgs]');
  if (!els.length || FC._badgeLigado) return;
  const session = await FC.getSession();
  if (!session) return;
  FC._badgeLigado = true;
  const uid = session.user.id;
  const mostrar = n => els.forEach(el => { el.textContent = n > 99 ? '99+' : n; el.style.display = n ? '' : 'none'; });
  const contar = async () => {
    const { count, error } = await supabaseClient.from('messages')
      .select('id', { count: 'exact', head: true })
      .eq('receiver_id', uid).is('read_at', null).eq('deleted', false).eq('cleared_by_receiver', false);
    if (!error) mostrar(count || 0);
  };
  await contar();
  supabaseClient.channel('badge-msgs-' + uid)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'messages', filter: `receiver_id=eq.${uid}` }, contar)
    .subscribe();
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
  if (me && me.type === 'empresa') FC.carregarConfig().then(() => FC.lembreteMensalidade(me));
  return me;
};
