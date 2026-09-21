/* ============================================================
   Feira Comercial — supabase-config.js (partilhado por TODAS as páginas)
   - Cria o cliente Supabase UMA vez
   - Garante sessão (expulsa para Portal.html se não houver login)
   - Carrega o perfil do utilizador e identifica-o com FOTO + NOME
     em qualquer página (basta usar data-fc-avatar / data-fc-name)
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
  localStorage.removeItem('fc_profile');
  window.location.href = 'Portal.html';
};

/* ---------- Perfil (com cache local para abrir rápido) ---------- */
FC.loadMyProfile = async function () {
  const session = await FC.getSession();
  if (!session) return null;

  // cache (só para render imediato; depois atualiza)
  const cached = localStorage.getItem('fc_profile');
  if (cached) { try { FC.me = JSON.parse(cached); } catch (e) {} }

  const { data, error } = await supabaseClient
    .from('profiles')
    .select('*')
    .eq('id', session.user.id)
    .maybeSingle();

  if (!error && data) {
    FC.me = data;
    localStorage.setItem('fc_profile', JSON.stringify(data));
  } else if (!FC.me) {
    // fallback: mínimo a partir do auth
    FC.me = {
      id: session.user.id,
      full_name: session.user.email.split('@')[0],
      email: session.user.email,
      avatar_url: null
    };
  }
  return FC.me;
};

/* ---------- Identidade visual: aplica FOTO + NOME em toda a rede ----------
   No HTML de qualquer página basta:
   <img data-fc-avatar>  e  <span data-fc-name></span>
   Ou: FC.applyIdentity({ avatar: '#meuImg', name: '#meuNome' })
------------------------------------------------------------------------- */
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

/* ---------- Upload para Storage (foto de perfil / capa / documentos) ---------- */
FC.uploadImage = async function (bucket, file, path) {
  const { error } = await supabaseClient.storage
    .from(bucket).upload(path, file, { upsert: true, contentType: file.type });
  if (error) throw error;
  const { data } = supabaseClient.storage.from(bucket).getPublicUrl(path);
  return data.publicUrl;
};

/* ---------- Arranque padrão: exige login + aplica identidade ---------- */
FC.boot = async function (opts = {}) {
  const session = await FC.requireAuth(opts.loginPage);
  if (!session) return null;
  return await FC.applyIdentity(opts);
};