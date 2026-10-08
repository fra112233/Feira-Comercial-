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

/* ---------- Arranque padrão ---------- */
FC.boot = async function (opts = {}) {
  const session = await FC.requireAuth(opts.loginPage);
  if (!session) return null;
  const me = await FC.applyIdentity(opts);
  FC.badgeMensagens();
  return me;
};
