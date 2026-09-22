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
  if (!session) { window.location.href = loginPage; return null; }
  return session;
};

FC.signOut = async function () {
  await supabaseClient.auth.signOut();
  localStorage.removeItem('fc_profis');
  window.location.href = 'Portal.html';
};

/* ---------- Perfil (tabela "perfis", com cache local) ---------- */
FC.loadMyProfile = async function () {
  const session = await FC.getSession();
  if (!session) return null;

  // cache só para render imediato, e só se for do utilizador atual
  const cached = localStorage.getItem('fc_profis');
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
    localStorage.setItem('fc_profis', JSON.stringify(FC.me));
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
  const me = await FC.loadMyProfis();
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

/* ---------- Arranque padrão ---------- */
FC.boot = async function (opts = {}) {
  const session = await FC.requireAuth(opts.loginPage);
  if (!session) return null;
  return await FC.applyIdentity(opts);
};
