/* ============================================================
   Feira Comercial — supabase-config.js (partilhado por TODAS as páginas)
   ============================================================ */

const SUPABASE_URL = 'https://bljnkwrhqnpawclybqrw.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_qvUvtBjpAKtMevafHRJe8g_W-aUkOb0';

let FC_registarErro = null;

/* Sessão expirada (telemóvel adormecido, relógio do aparelho errado): se o servidor responder 401,
   renova a sessão uma vez e repete o pedido, em vez de mostrar erros ou um feed vazio. */
let _renovar = null;
async function _fetchComRenovacao(url, init) {
  const r = await fetch(url, init);
  const u = String(url && url.url || url);
  if (r.status >= 500 && u.indexOf('registar_erro') < 0 && typeof FC_registarErro === 'function')
    FC_registarErro('Servidor ' + r.status + ': ' + u.replace(/^https?:\/\/[^/]+/, '').replace(/\?.*$/, ''));
  if (r.status !== 401 || u.indexOf('/auth/v1/') >= 0 || !window.supabaseClient) return r;
  try {
    const h = new Headers((init && init.headers) || {});
    const antigo = h.get('Authorization') || '';
    if (!_renovar) _renovar = supabaseClient.auth.refreshSession().finally(() => setTimeout(() => { _renovar = null; }, 5000));
    const { data } = await _renovar;
    const tok = data && data.session && data.session.access_token;
    if (!tok || antigo === 'Bearer ' + tok) return r;
    h.set('Authorization', 'Bearer ' + tok);
    return await fetch(url, Object.assign({}, init, { headers: h }));
  } catch (e) { return r; }
}
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { fetch: _fetchComRenovacao } });
window.supabaseClient = supabaseClient;

/* Aviso automático de erros: quando algo falha no aparelho de alguém, fica registado
   (página, erro, aparelho) para a equipa corrigir. Não envia nada escrito pelas pessoas.
   Máximo 5 por página aberta; ignora ruído de extensões e do próprio navegador. */
(function () {
  let enviados = 0; const vistos = {};
  const RUIDO = /ResizeObserver loop|^Script error\.?$|Non-Error promise rejection|AbortError|The user aborted|Load failed|NetworkError|Failed to fetch|cancelad|cancelled|extension:\/\/|chrome-extension|moz-extension|safari-extension|webkit-masked-url|play\(\) request was interrupted|NotAllowedError/i;
  FC_registarErro = function (msg, fonte, linha, pilha) {
    try {
      msg = String(msg || '').slice(0, 300);
      if (!msg || RUIDO.test(msg) || RUIDO.test(String(fonte || '')) || RUIDO.test(String(pilha || ''))) return;
      if (enviados >= 5 || vistos[msg]) return;
      vistos[msg] = 1; enviados++;
      let versao = ''; try { versao = localStorage.getItem('fc_versao') || ''; } catch (e) {}
      supabaseClient.rpc('registar_erro', {
        p_pagina: location.pathname, p_mensagem: msg, p_fonte: fonte ? String(fonte) : null, p_linha: linha || null,
        p_pilha: pilha ? String(pilha).slice(0, 1500) : null, p_aparelho: navigator.userAgent.slice(0, 200), p_versao: versao
      }).then(() => {}, () => {});
    } catch (e) {}
  };
  window.addEventListener('error', function (ev) {
    if (ev && ev.target && ev.target !== window && !ev.message) return;   // imagem/vídeo que não carregou: não é erro do código
    FC_registarErro(ev.message || (ev.error && ev.error.message), ev.filename, ev.lineno, ev.error && ev.error.stack);
  });
  window.addEventListener('unhandledrejection', function (ev) {
    const r = ev && ev.reason;
    FC_registarErro('Promessa: ' + ((r && (r.message || r.error_description)) || String(r)), null, null, r && r.stack);
  });
})();

window.FC = window.FC || {};

/* De onde veio a pessoa: links de publicidade como www.feira-comercial.com/?o=facebook.
   Guarda-se a primeira origem durante 30 dias; vai com o registo da conta. */
(function () {
  try {
    const q = new URLSearchParams(location.search);
    const o = (q.get('o') || q.get('origem') || q.get('utm_source') || '').toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 30);
    const atual = JSON.parse(localStorage.getItem('fc_origem') || 'null');
    if (o && !(atual && atual.t > Date.now() - 30 * 864e5)) localStorage.setItem('fc_origem', JSON.stringify({ o: o, t: Date.now() }));
  } catch (e) {}
})();
FC.origem = function () {
  try { const a = JSON.parse(localStorage.getItem('fc_origem') || 'null'); return a && a.t > Date.now() - 30 * 864e5 ? a.o : ''; } catch (e) { return ''; }
};

/* Hora certa: usa a hora do SERVIDOR, não a do relógio do aparelho (que pode estar adiantado
   ou atrasado). Mostra-se sempre no fuso horário do aparelho. */
FC._desvio = 0;
FC._horaCerta = false;
FC.agora = () => Date.now() + FC._desvio;
/* Datas: conta-se em DIAS DO CALENDÁRIO, nunca em blocos de 24 horas.
   Criada ontem às 23h e vista hoje às 8h = "ontem" (só 9 h, mas é outro dia);
   criada anteontem às 22h e vista hoje às 20h = "há 2 dias" (46 h, mas 2 dias). */
FC.inicioDia = t => { const y = new Date(t); y.setHours(0, 0, 0, 0); return y.getTime(); };
FC.diasAte = d => Math.round((FC.inicioDia(new Date(d)) - FC.inicioDia(FC.agora())) / 864e5);   // 0 hoje · 1 amanhã · -1 ontem
FC.hojeISO = () => { const x = new Date(FC.agora()); return x.getFullYear() + '-' + String(x.getMonth() + 1).padStart(2, '0') + '-' + String(x.getDate()).padStart(2, '0'); };
FC.emDias = n => n <= 0 ? 'hoje' : n === 1 ? 'amanhã' : 'em ' + n + ' dias';
FC.plural = (n, um, varios) => n + ' ' + (Number(n) === 1 ? um : varios);       // "1 vez" / "3 vezes" (nunca "1 vezes")                  // "termina hoje / amanhã / em 3 dias"
FC.sincronizarHora = function () {
  if (!FC._sincHora) FC._sincHora = (async () => {
    try {
      const t0 = Date.now();
      const { data, error } = await supabaseClient.rpc('agora');
      if (error || !data) return;
      const t1 = Date.now();
      const srv = new Date(data).getTime();
      if (!isFinite(srv)) return;                              // resposta estranha: fica a hora do aparelho (nunca "Invalid Date")
      FC._desvio = srv - (t0 + t1) / 2;   // desconta metade do tempo da viagem
      FC._horaCerta = true;
    } catch (e) {}
  })();
  return FC._sincHora;
};
FC.sincronizarHora();

/* URL segura para pôr em src/href: só https, imagens embutidas, blob e caminhos do próprio site;
   aspas e < > escapadas (impede que um endereço malicioso guardado na base de dados injete código). */
FC.u = function (u) {
  u = String(u == null ? '' : u).trim();
  if (!/^(https:\/\/|data:image\/|blob:|\/|images\/)/i.test(u)) return '';
  return u.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
};

/* Poupança de tráfego (plano grátis do Supabase: 5 GB/mês de fotos e vídeos vistos).
   true  = os vídeos do feed não tocam sozinhos (toca-se para ver) e não se pré-carrega o vídeo seguinte.
   Mudar para false depois de passar ao plano Pro. */
FC.POUPAR_TRAFEGO = true;

/* Captcha anti-robôs (Cloudflare Turnstile, grátis) no registo, entrada e recuperação de palavra-passe.
   Vazio = desligado. Para ligar: 1) criar o widget em dash.cloudflare.com → Turnstile;
   2) pôr aqui a "Site Key"; 3) no Supabase → Authentication → Attack Protection → Captcha:
   escolher Turnstile e colar a "Secret Key". (Fazer o passo 2 ANTES do 3, senão ninguém entra.) */
FC.CAPTCHA_SITE_KEY = '';
FC._captchas = [];
FC.prepararCaptcha = function () {
  if (!FC.CAPTCHA_SITE_KEY) return;
  const caixas = document.querySelectorAll('.fc-captcha');
  if (!caixas.length) return;
  const desenhar = () => caixas.forEach(c => {
    if (c.dataset.pronto) return; c.dataset.pronto = '1';
    const w = { token: '', id: null };
    w.id = window.turnstile.render(c, { sitekey: FC.CAPTCHA_SITE_KEY, language: 'pt', callback: t => { w.token = t; }, 'expired-callback': () => { w.token = ''; } });
    FC._captchas.push(w);
  });
  if (window.turnstile) return desenhar();
  window.fcTurnstilePronto = desenhar;
  const s = document.createElement('script');
  s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=fcTurnstilePronto';
  s.async = true; document.head.appendChild(s);
};
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => FC.prepararCaptcha()); else FC.prepararCaptcha();
// devolve o token (ou undefined se o captcha estiver desligado) e prepara um novo para a próxima vez
FC.tokenCaptcha = function () {
  if (!FC.CAPTCHA_SITE_KEY) return undefined;
  const w = FC._captchas.find(x => x.token) || FC._captchas[0];
  const t = w && w.token;
  if (w && window.turnstile) { try { window.turnstile.reset(w.id); } catch (e) {} w.token = ''; }
  return t || undefined;
};

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
  if (!(await FC.garantir2FA())) return null;
  return session;
};

/* ---------- Verificação em dois passos (código da app autenticadora) ----------
   Quem ativou a verificação em dois passos tem de escrever o código de 6 dígitos
   depois de entrar. Sem o código, sai da conta. */
FC.pedirCodigo = function (titulo, texto) {
  return new Promise(resolve => {
    const el = document.createElement('div');
    el.id = 'fc-2fa';
    el.innerHTML =
      '<style>#fc-2fa{position:fixed;inset:0;z-index:7000;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;padding:16px;font-family:Inter,"Segoe UI",system-ui,sans-serif}' +
      '#fc-2fa .c{background:#16161a;color:#f4f4f5;border:1px solid rgba(243,198,78,.35);border-radius:20px;max-width:360px;width:100%;padding:24px;text-align:center}' +
      '#fc-2fa h3{margin:6px 0;font-size:19px}#fc-2fa p{color:#a1a1aa;font-size:14px;line-height:1.5;margin:0 0 14px}' +
      '#fc-2fa input{width:100%;box-sizing:border-box;text-align:center;font-size:26px;letter-spacing:8px;padding:12px;border-radius:12px;border:1px solid #2c2c34;background:#1f1f25;color:#fff;font-variant-numeric:tabular-nums}' +
      '#fc-2fa .e{color:#f87171;font-size:13px;min-height:18px;margin:8px 0}#fc-2fa button{display:block;width:100%;padding:12px;border-radius:12px;font:inherit;font-weight:700;font-size:15px;cursor:pointer;margin-top:8px}' +
      '#fc-2fa .ok{background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#000;border:none}#fc-2fa .nao{background:#1f1f25;color:#f4f4f5;border:1px solid #2c2c34}</style>' +
      '<form class="c" role="dialog" aria-modal="true"><div style="font-size:36px">🔐</div><h3></h3><p></p>' +
      '<input inputmode="numeric" autocomplete="one-time-code" maxlength="6" pattern="[0-9]*" aria-label="Código de 6 dígitos"><div class="e" role="alert"></div>' +
      '<button class="ok" type="submit">Confirmar</button><button class="nao" type="button">Sair da conta</button></form>';
    el.querySelector('h3').textContent = titulo || 'Verificação em dois passos';
    el.querySelector('p').textContent = texto || 'Abra a sua app autenticadora e escreva o código de 6 dígitos da Feira Comercial.';
    const inp = el.querySelector('input');
    inp.addEventListener('input', () => { inp.value = inp.value.replace(/\D/g, '').slice(0, 6); });
    el.querySelector('form').onsubmit = e => { e.preventDefault(); if (inp.value.length === 6) resolve({ codigo: inp.value, el }); };
    el.querySelector('.nao').onclick = () => { el.remove(); resolve(null); };
    document.body.appendChild(el);
    setTimeout(() => inp.focus(), 50);
  });
};
FC.garantir2FA = async function () {
  try {
    if (!supabaseClient.auth.mfa) return true;
    const { data, error } = await supabaseClient.auth.mfa.getAuthenticatorAssuranceLevel();
    if (error || !data || data.nextLevel !== 'aal2' || data.currentLevel === 'aal2') return true;
    const { data: f } = await supabaseClient.auth.mfa.listFactors();
    const fator = f && (f.totp || []).find(x => x.status === 'verified');
    if (!fator) return true;
    if (!document.body) await new Promise(r => document.addEventListener('DOMContentLoaded', r, { once: true }));
    for (;;) {
      const r = await FC.pedirCodigo();
      if (!r) { await FC.signOut(); return false; }
      const v = await supabaseClient.auth.mfa.challengeAndVerify({ factorId: fator.id, code: r.codigo });
      if (!v.error) { r.el.remove(); return true; }
      r.el.remove();
      FC.toast('Código errado ou expirado. Tente o código novo da app.');
    }
  } catch (e) { console.warn('2FA:', e); return true; }
};

FC.signOut = async function () {
  if (FC.desativarPush) await FC.desativarPush();
  await supabaseClient.auth.signOut();
  localStorage.removeItem('fc_profile');
  try { localStorage.removeItem('fc_feed_v2'); } catch (e) {}
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

  // perfil guardado neste telemóvel: a página usa-o logo e atualiza-o em segundo plano
  // (poupa uma ida ao servidor em cada mudança de página)
  let guardado = null;
  try {
    const c = JSON.parse(localStorage.getItem('fc_profile') || 'null');
    // usa-se mesmo que seja antigo (quem não entra há dias não espera); a versão nova chega logo a seguir
    if (c && c.id === session.user.id && c._em && Date.now() - c._em < 60 * 24 * 3600 * 1000) guardado = c;
  } catch (e) {}
  const buscar = FC.lerPerfil(session.user.id).then(({ data, error }) => {
    if (error || !data) return null;
    FC.me = { ...data, email: session.user.email };
    try { localStorage.setItem('fc_profile', JSON.stringify({ ...FC.me, _em: Date.now() })); } catch (e) {}
    document.dispatchEvent(new CustomEvent('fc:perfil', { detail: FC.me }));
    return FC.me;
  }, () => null);
  if (guardado) { FC.me = guardado; return FC.me; }

  const data = await buscar;
  const error = data ? null : true;

  if (!error && data) {
    FC.me = data;
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
    // número no ícone da aplicação instalada (onde o telemóvel/computador o suporta)
    try { if (navigator.setAppBadge) { n ? navigator.setAppBadge(n) : navigator.clearAppBadge(); } } catch (e) {}
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
  FC._contarMensagens = contar;
  // Para aguentar muita gente: só a página das Mensagens usa tempo real.
  // Nas outras páginas o número vem do pedido único "estado_agora" (1 por minuto e meio).
  const modoAntigo = () => {
    if (FC._badgeAntigo) return; FC._badgeAntigo = true;
    contar();
    setInterval(() => { if (document.visibilityState === 'visible') contar(); }, 60000);
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') contar(); });
  };
  if (/mensagen\.html/i.test(location.pathname)) {
    supabaseClient.channel('badge-msgs-' + uid)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'messages', filter: `receiver_id=eq.${uid}` }, contar)
      .subscribe();
    modoAntigo();
  } else {
    document.addEventListener('fc:estado', e => mostrar((e.detail && e.detail.mensagens) || 0));
    document.addEventListener('fc:estado-falhou', modoAntigo);
    FC.iniciarEstado();
  }
  window.addEventListener('focus', contar);
};

/* ---------- Sino 🔔: notificações de atividade ----------
   Gostos, comentários, respostas, novos seguidores e novidades de quem sigo
   (publicações, vídeos, Live). O sino aparece ao lado do botão ☰ em todas as páginas. */
FC._notifNaoLidas = 0;
FC._fimAvisado = new Set();
FC._notifTextos = {
  travao: '🛑 Travão automático: conta posta em revisão por denúncias',
  numero_proibido: '🚫 enviou um número de uma conta suspensa',
  cobranca: 'foi-lhe atribuída para cobrar a mensalidade 💰',
  gosto: 'gostou da sua publicação', comentario: 'comentou a sua publicação', resposta: 'respondeu ao seu comentário',
  seguir: 'começou a segui-lo', publicacao: 'fez uma publicação nova', video: 'publicou um vídeo novo',
  gosto_video: 'gostou do seu vídeo', gosto_story: 'gostou do seu story ❤️', comentario_video: 'comentou o seu vídeo', live: 'está em direto agora 🔴',
  avaliacao: 'avaliou a sua empresa', resposta_avaliacao: 'respondeu à sua avaliação',
  convite_aceite: 'criou conta com o seu convite', convite_premio: 'pagou a mensalidade: ganhou dias grátis',
  marco_publicacao: '🎉 Parabéns! A sua primeira publicação está no ar.',
  marco_seguidor: '🎉 Parabéns! Tem o seu primeiro seguidor.',
  marco_mensagem: '💬 Recebeu a sua primeira mensagem. Responda depressa!',
  gratis_fim: '— os seus dias grátis acabaram ⏰', mensalidade_fim: '— a sua mensalidade terminou ⏰',
  oferta_guardado: 'pôs em oferta algo que guardou ⚡', oferta_loja: 'fez uma oferta para si ⚡',
  resumo_semanal: '— o seu resumo da semana 📰', lojas_hoje: 'publicou hoje 🛍️'
};
FC._notifIcones = {
  gosto: 'fa-heart', gosto_video: 'fa-heart', gosto_story: 'fa-heart', comentario: 'fa-comment', comentario_video: 'fa-comment', resposta: 'fa-reply',
  seguir: 'fa-user-plus', publicacao: 'fa-newspaper', video: 'fa-play', live: 'fa-tower-broadcast',
  avaliacao: 'fa-star', resposta_avaliacao: 'fa-star', convite_aceite: 'fa-gift', convite_premio: 'fa-gift',
  marco_publicacao: 'fa-trophy', marco_seguidor: 'fa-trophy', marco_mensagem: 'fa-comment-dots', gratis_fim: 'fa-clock', mensalidade_fim: 'fa-clock',
  oferta_guardado: 'fa-bolt', oferta_loja: 'fa-bolt', resumo_semanal: 'fa-newspaper', lojas_hoje: 'fa-store', travao: 'fa-shield-halved', numero_proibido: 'fa-phone-slash', cobranca: 'fa-calendar-check'
};
FC.haQuanto = function (d) {
  const s = Math.max(0, (FC.agora() - new Date(d).getTime()) / 1000);
  if (s < 60) return 'agora';
  if (s < 3600) return 'há ' + Math.floor(s / 60) + ' min';
  if (s < 86400) return 'há ' + Math.floor(s / 3600) + ' h';
  const n = -FC.diasAte(d);   // dias do calendário
  if (n <= 1) return 'ontem';
  if (n < 7) return 'há ' + n + ' dias';
  return new Date(d).toLocaleDateString('pt-PT', { day: 'numeric', month: 'short' });
};
// "hoje às 10:29", "ontem às 9:44", "amanhã às 03:45", "sex., 17 out. às 03:45"
// a página está em tema branco? (index/mensagens usam body[data-theme], o perfil usa body.light-mode)
FC.temaClaro = function () {
  const b = document.body; if (!b) return false;
  if (b.hasAttribute('data-theme')) return b.getAttribute('data-theme') !== 'dark';
  return b.classList.contains('light-mode');
};
FC.diaHora = function (d) {
  const x = new Date(d), h = x.toLocaleTimeString('pt-PT', { hour: '2-digit', minute: '2-digit' });
  const dia = t => { const y = new Date(t); y.setHours(0, 0, 0, 0); return y.getTime(); };
  const dif = Math.round((dia(x) - dia(FC.agora())) / 864e5);
  if (dif === 0) return 'hoje às ' + h;
  if (dif === -1) return 'ontem às ' + h;
  if (dif === 1) return 'amanhã às ' + h;
  return x.toLocaleDateString('pt-PT', { weekday: 'short', day: 'numeric', month: 'short' }) + ' às ' + h;
};
// "hoje, 15/10/2026, às 11:20" — data completa e hora
FC.dataHora = function (d) {
  const x = new Date(d), h = x.toLocaleTimeString('pt-PT', { hour: '2-digit', minute: '2-digit' });
  const data = x.toLocaleDateString('pt-PT', { day: '2-digit', month: '2-digit', year: 'numeric' });
  const rel = FC.diaHora(d).split(' às ')[0];
  return (/^(hoje|ontem|amanhã)$/.test(rel) ? rel + ', ' : '') + data + ', às ' + h;
};
// texto da notificação conforme o estado ATUAL da live / da oferta
FC.textoNotificacao = function (n) {
  // uma só linha por dia: "Sapataria Boa e mais 10 lojas publicaram hoje"
  if (n.tipo === 'lojas_hoje') {
    const k = Math.max(0, ((n.lojas && n.lojas.length) || 1) - 1);
    return { txt: k ? FC.t('e mais') + ' ' + k + ' ' + FC.t(k === 1 ? 'loja publicaram hoje 🛍️' : 'lojas publicaram hoje 🛍️') : FC.t('publicou hoje 🛍️'),
             extra: FC.t('Toque para ver no feed') };
  }
  if (n.tipo === 'live' && n.live) {
    const l = n.live;
    // o servidor fecha sozinho as lives sem sinal (migração 030); com a hora certa basta uma margem de 3 min
    const margem = FC._horaCerta ? 3 * 60000 : 10 * 60000;
    const ativa = l.estado === 'ao_vivo' && !l.ended_at && (FC.agora() - new Date(l.atualizado_em).getTime()) < margem;
    if (!ativa) {
      const fim = l.ended_at || l.atualizado_em;
      return { txt: 'terminou a live', extra: 'Terminou ' + (fim ? FC.dataHora(fim) : ''), terminada: true };
    }
    return { txt: FC._notifTextos.live, extra: n.texto };
  }
  if ((n.tipo === 'publicacao' || n.tipo === 'oferta_guardado' || n.tipo === 'oferta_loja') && n.post && n.post.oferta_ate) {
    const fim = new Date(n.post.oferta_ate).getTime(), acabou = fim <= FC.agora();
    const preco = n.post.oferta_preco != null ? Math.round(n.post.oferta_preco).toLocaleString('pt-PT') + ' MT' : '';
    return { txt: n.tipo === 'publicacao' ? 'publicou uma oferta relâmpago ⚡' : FC._notifTextos[n.tipo],
             extra: [preco, acabou ? 'Terminou ' + FC.dataHora(fim) : 'Válida até ' + FC.dataHora(fim)].filter(Boolean).join(' · '),
             terminada: acabou };
  }
  return { txt: FC._notifTextos[n.tipo] || '', extra: n.texto };
};
FC.linkNotificacao = function (n) {
  if (n.tipo === 'marco_mensagem') return 'mensagen.html';
  if (n.tipo === 'marco_seguidor') return 'perfil.html';
  if (n.tipo === 'avaliacao') return 'perfil.html#avaliacoes';
  if (n.tipo === 'resposta_avaliacao') return 'perfil.html?id=' + encodeURIComponent(n.autor_id || '') + '#avaliacoes';
  if (n.tipo && n.tipo.indexOf('convite') === 0) return 'mensalidade.html#convites';
  if (n.tipo === 'gratis_fim' || n.tipo === 'mensalidade_fim') return 'mensalidade.html';
  if (n.tipo === 'resumo_semanal' || n.tipo === 'lojas_hoje') return 'index.html';
  if (n.tipo === 'travao') return 'admin.html';
  if (n.tipo === 'numero_proibido') return 'admin.html#suspeitos';
  if (n.tipo === 'cobranca') return 'admin.html#mensalidades';
  if (n.tipo === 'gosto_story') return 'index.html';   // conta posta em revisão pelo travão automático
  if (n.post_id) return 'index.html?post=' + n.post_id;
  if (n.video_id) return 'videos.html?v=' + n.video_id;
  if (n.live_id && n.live && FC.textoNotificacao(n).terminada) return 'perfil.html?id=' + encodeURIComponent(n.autor_id || '');
  if (n.live_id) return 'live.html?id=' + encodeURIComponent(n.live_id);
  return 'perfil.html?id=' + encodeURIComponent(n.autor_id || '');
};
FC.sino = async function () {
  if (FC._sinoLigado) return;
  const session = await FC.getSession();
  if (!session) return;
  const uid = session.user.id;
  // a tabela ainda não existe (migração 022 por correr): não mostra o sino
  const teste = await supabaseClient.from('notificacoes').select('id', { count: 'exact', head: true }).eq('user_id', uid).eq('lida', false);
  if (teste.error) return;
  FC._sinoLigado = true;
  const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  if (!document.getElementById('fc-sino-css')) {
    const css = document.createElement('style');
    css.id = 'fc-sino-css';
    css.textContent =
      '.fc-sino-btn{position:relative}' +
      '.fc-notif-badge{position:absolute;top:-4px;right:-6px;min-width:18px;height:18px;padding:0 5px;border-radius:9px;background:#ef4444;color:#fff;font:700 11px/18px Inter,system-ui,sans-serif;text-align:center;box-shadow:0 0 0 2px var(--bg-card,#18191a);pointer-events:none}' +
      // cores próprias do painel (escuro/claro conforme o tema): nas Mensagens em tema branco ficava fundo escuro com letras escuras
      '#fcn{--fcn-bg:#1e293b;--fcn-tx:#f1f5f9;--fcn-hover:#334155;--fcn-borda:#334155}#fcn.claro{--fcn-bg:#ffffff;--fcn-tx:#0f172a;--fcn-hover:#f1f5f9;--fcn-borda:#e2e8f0}' +
      '#fcn-fundo{position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:5000;opacity:0;visibility:hidden;transition:.25s}#fcn-fundo.aberto{opacity:1;visibility:visible}' +
      '#fcn{position:fixed;top:0;right:0;bottom:0;width:min(400px,94vw);z-index:5001;background:var(--fcn-bg);' +
      'color:var(--fcn-tx);transform:translateX(105%);transition:transform .28s ease;display:flex;flex-direction:column;' +
      'box-shadow:-8px 0 30px rgba(0,0,0,.3);font-family:Inter,"Segoe UI",system-ui,sans-serif;padding-bottom:env(safe-area-inset-bottom)}#fcn.aberto{transform:none}' +
      '#fcn .cab{display:flex;align-items:center;gap:8px;padding:14px 16px;border-bottom:1px solid var(--fcn-borda)}#fcn .cab b{font-size:17px;flex:1}' +
      '#fcn .cab button{border:none;background:none;color:var(--primary,#f3c64e);font-weight:600;font-size:13px;font-family:inherit;cursor:pointer;padding:6px}' +
      '#fcn .fechar{width:36px;height:36px;border-radius:50%;background:var(--fcn-hover)!important;color:inherit!important;font-size:18px!important}' +
      '#fcn .lista{flex:1;overflow-y:auto}' +
      '#fcn .n{display:flex;gap:12px;align-items:flex-start;padding:12px 16px;text-decoration:none;color:inherit;border-bottom:1px solid var(--fcn-borda)}' +
      '#fcn .n:hover{background:var(--fcn-hover)}#fcn .n.nova{background:rgba(243,198,78,.08)}#fcn .n.fim .av i{background:#6b7280 !important;color:#fff !important}' +
      '#fcn .av{position:relative;flex-shrink:0}#fcn .av img{width:44px;height:44px;border-radius:50%;object-fit:cover;background:#475569}' +
      '#fcn .av i{position:absolute;right:-3px;bottom:-3px;width:20px;height:20px;border-radius:50%;background:#f3c64e;color:#111;font-size:10px;display:flex;align-items:center;justify-content:center;box-shadow:0 0 0 2px var(--fcn-bg)}' +
      '#fcn .av i.fa-heart{background:#ef4444;color:#fff}#fcn .av i.fa-tower-broadcast{background:#ef4444;color:#fff}#fcn .av i.fa-user-plus{background:#22c55e;color:#fff}' +
      '#fcn .tx{flex:1;min-width:0;font-size:14px;line-height:1.4}#fcn .tx small{display:block;opacity:.75;margin-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '#fcn .tx .q{font-size:12px;opacity:.6;margin-top:3px}#fcn .ponto{width:9px;height:9px;border-radius:50%;background:#f3c64e;flex-shrink:0;margin-top:6px}' +
      '#fcn .pref-btn{width:36px;height:36px;border-radius:50%;font-size:15px!important;background:var(--fcn-hover)!important;color:inherit!important}#fcn .tx small.todo{white-space:normal}' +
      '#fcn .pref{padding:12px 16px;border-bottom:1px solid var(--fcn-borda);background:rgba(243,198,78,.06)}#fcn .pref>span{font-weight:700;font-size:14px}' +
      '#fcn .pref .ops{display:flex;gap:6px;margin:8px 0 6px;flex-wrap:wrap}#fcn .pref .ops button{flex:1;min-width:0;padding:9px 6px;border-radius:20px;border:1px solid var(--fcn-borda);background:none;color:inherit;font:600 13px inherit;font-family:inherit;cursor:pointer;white-space:nowrap}' +
      '#fcn .pref .ops button.on{background:#f3c64e;border-color:#f3c64e;color:#111}#fcn .pref small{font-size:12px;opacity:.75}' +
      '#fcn .vazio{text-align:center;opacity:.7;padding:50px 24px;font-size:14px;line-height:1.5}#fcn .vazio i{font-size:36px;display:block;margin-bottom:10px;opacity:.6}';
    document.head.appendChild(css);
  }

  // botão do sino ao lado de cada botão ☰ (com o mesmo estilo dele)
  document.querySelectorAll('[onclick*="FCMenu.abrir"]').forEach(menu => {
    if (menu.previousElementSibling && menu.previousElementSibling.classList.contains('fc-sino-btn')) return;
    const b = document.createElement(menu.tagName === 'BUTTON' ? 'button' : 'div');
    b.className = menu.className + ' fc-sino-btn';
    b.style.cssText = menu.style.cssText;   // alguns ☰ só aparecem com o estilo próprio deles
    if (b.tagName === 'BUTTON') b.type = 'button';
    b.title = 'Notificações'; b.setAttribute('aria-label', 'Notificações'); b.setAttribute('role', 'button');
    b.innerHTML = '<i class="fas fa-bell"></i><span class="fc-notif-badge" data-fc-notif style="display:none"></span>';
    b.onclick = () => FC.abrirNotificacoes();
    menu.parentNode.insertBefore(b, menu);
  });

  const mostrar = n => {
    FC._notifNaoLidas = n;
    const txt = n > 99 ? '99+' : String(n);
    document.querySelectorAll('[data-fc-notif]').forEach(el => { el.textContent = txt; el.style.display = n ? '' : 'none'; });
    document.dispatchEvent(new CustomEvent('fc:notificacoes', { detail: n }));
  };
  let t = null;
  const contar = () => {
    clearTimeout(t);
    t = setTimeout(async () => {
      const { count, error } = await supabaseClient.from('notificacoes').select('id', { count: 'exact', head: true }).eq('user_id', uid).eq('lida', false);
      if (!error) mostrar(count || 0);
    }, 250);
  };
  mostrar(teste.count || 0);

  // painel
  const fundo = document.createElement('div'); fundo.id = 'fcn-fundo';
  const painel = document.createElement('aside'); painel.id = 'fcn'; painel.setAttribute('aria-label', 'Notificações');
  painel.innerHTML = '<div class="cab"><b>Notificações</b><button type="button" data-ler title="Marcar tudo como lido">Ler tudo</button>' +
    '<button type="button" class="pref-btn" data-pref aria-label="Avisos de lojas" title="Avisos de lojas"><i class="fas fa-sliders"></i></button>' +
    '<button type="button" class="fechar" aria-label="Fechar"><i class="fas fa-times"></i></button></div>' +
    '<div class="pref" hidden><span>🛍️ Avisos de lojas</span><div class="ops">' +
    '<button type="button" data-v="todos">Todos</button><button type="button" data-v="ofertas">Só ofertas ⚡</button><button type="button" data-v="nenhum">Nenhum</button>' +
    '</div><small></small></div><div class="lista"></div>';
  document.body.appendChild(fundo); document.body.appendChild(painel);
  const fechar = () => { painel.classList.remove('aberto'); fundo.classList.remove('aberto'); document.body.style.overflow = ''; };
  fundo.onclick = fechar; painel.querySelector('.fechar').onclick = fechar;
  document.addEventListener('keydown', e => { if (e.key === 'Escape') fechar(); });
  painel.querySelector('[data-ler]').onclick = async () => {
    await supabaseClient.from('notificacoes').update({ lida: true }).eq('user_id', uid).eq('lida', false);
    painel.querySelectorAll('.n.nova').forEach(el => { el.classList.remove('nova'); const p = el.querySelector('.ponto'); if (p) p.remove(); });
    mostrar(0);
  };
  // escolher que avisos de lojas receber (para ninguém se sentir sufocado)
  const pref = painel.querySelector('.pref');
  const EXPLICA = { todos: 'Uma linha por dia com as lojas que publicaram, e as ofertas.', ofertas: 'Só as ofertas ⚡ das lojas.', nenhum: 'Nenhum aviso de lojas. Mensagens e comentários continuam.' };
  const marcarPref = v => {
    pref.querySelectorAll('[data-v]').forEach(b => b.classList.toggle('on', b.dataset.v === v));
    pref.querySelector('small').textContent = FC.t(EXPLICA[v] || '');
  };
  painel.querySelector('[data-pref]').onclick = async () => {
    pref.hidden = !pref.hidden;
    if (pref.hidden) return;
    let v = FC.me && FC.me.avisos_lojas;
    if (!v) { const { data } = await supabaseClient.from('perfis').select('avisos_lojas').eq('id', uid).maybeSingle(); v = (data && data.avisos_lojas) || 'todos'; }
    marcarPref(v);
  };
  pref.addEventListener('click', async e => {
    const b = e.target.closest('[data-v]'); if (!b) return;
    const antes = pref.querySelector('.on'); marcarPref(b.dataset.v);
    const { error } = await supabaseClient.from('perfis').update({ avisos_lojas: b.dataset.v }).eq('id', uid);
    if (error) { if (antes) marcarPref(antes.dataset.v); FC.toast(FC.t('Não foi possível guardar. Tente outra vez.')); return; }
    if (FC.me) FC.me.avisos_lojas = b.dataset.v;
    FC.toast(FC.t('Guardado ✓'));
  });
  const lista = painel.querySelector('.lista');
  const desenhar = async () => {
    await FC.sincronizarHora();
    const base = 'id, tipo, autor_id, post_id, video_id, live_id, texto, lida, criado, autor:perfis!notificacoes_autor_id_fkey(full_name, avatar_url)';
    let { data, error } = await supabaseClient.from('notificacoes')
      .select(base + ', lojas, live:lives!notificacoes_live_id_fkey(estado, atualizado_em, ended_at), post:posts!notificacoes_post_id_fkey(oferta_ate, oferta_preco)')
      .eq('user_id', uid).order('criado', { ascending: false }).limit(60);
    if (error) ({ data, error } = await supabaseClient.from('notificacoes').select(base)   // base antiga sem colunas de oferta/lojas
      .eq('user_id', uid).order('criado', { ascending: false }).limit(60));
    if (error) { lista.innerHTML = '<div class="vazio">Não foi possível carregar as notificações.</div>'; return; }
    if (!data || !data.length) {
      lista.innerHTML = '<div class="vazio"><i class="fas fa-bell"></i>Ainda não tem notificações.<br>Siga empresas em <a href="amigos.html" style="color:var(--primary,#f3c64e)">Amigos</a> para saber das novidades delas.</div>';
      return;
    }
    lista.innerHTML = data.map(n => {
      const a = n.autor || {}, nome = a.full_name || FC.t('Alguém');
      const foto = a.avatar_url || ('https://ui-avatars.com/api/?name=' + encodeURIComponent(nome) + '&background=random&color=fff&size=88');
      const t = FC.textoNotificacao(n);
      return '<a class="n' + (n.lida ? '' : ' nova') + (t.terminada ? ' fim' : '') + '" href="' + esc(FC.linkNotificacao(n)) + '" data-id="' + n.id + '">' +
        '<span class="av"><img src="' + FC.u(foto) + '" alt="" loading="lazy"><i class="fas ' + (FC._notifIcones[n.tipo] || 'fa-bell') + '"></i></span>' +
        '<span class="tx"><b data-no-i18n>' + esc(nome) + '</b> ' + esc(t.txt) +
        // o excerto de um comentário/avaliação é texto da pessoa: não se traduz
        (t.extra ? '<small' + (n.tipo === 'resumo_semanal' ? ' class="todo"' : '') + (/coment|resposta|avaliacao/.test(n.tipo) ? ' data-no-i18n' : '') + '>' + esc(t.extra) + '</small>' : '') +
        '<span class="q" style="display:block">' + FC.haQuanto(n.criado) + ' · ' + FC.dataHora(n.criado) + '</span></span>' +
        (n.lida ? '' : '<span class="ponto"></span>') + '</a>';
    }).join('');
  };
  lista.addEventListener('click', e => {
    const a = e.target.closest('a.n'); if (!a || !a.dataset.id) return;
    e.preventDefault();
    const href = a.getAttribute('href');
    const ir = () => { location.href = href; };
    if (a.classList.contains('nova')) {
      supabaseClient.from('notificacoes').update({ lida: true }).eq('id', Number(a.dataset.id)).then(ir, ir);
      setTimeout(ir, 800);   // não espera para sempre se a rede estiver lenta
    } else ir();
  });
  FC.abrirNotificacoes = async () => {
    if (window.FCMenu) FCMenu.fechar();
    painel.classList.toggle('claro', FC.temaClaro());
    fundo.classList.add('aberto'); painel.classList.add('aberto'); document.body.style.overflow = 'hidden';
    lista.innerHTML = '<div class="vazio">A carregar…</div>';
    await desenhar();
  };

  // número do sino: vem do pedido único "estado_agora" (sem ligação em tempo real em cada página)
  let antes = null;
  document.addEventListener('fc:estado', e => {
    const n = (e.detail && e.detail.notificacoes) || 0;
    if (antes !== null && n > antes && document.visibilityState === 'visible') {
      if (painel.classList.contains('aberto')) desenhar();
      else FC.toast('🔔 ' + FC.t(n - antes === 1 ? 'Tem 1 notificação nova' : 'Tem notificações novas'));
    }
    antes = n; mostrar(n);
  });
  let sinoAntigo = false;
  document.addEventListener('fc:estado-falhou', () => { if (sinoAntigo) return; sinoAntigo = true; ligarAntigo(); });
  FC.iniciarEstado();
  const ligarAntigo = () => supabaseClient.channel('notif-' + uid)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'notificacoes', filter: `user_id=eq.${uid}` }, async payload => {
      contar();
      if (painel.classList.contains('aberto')) desenhar();
      else if (payload.eventType === 'UPDATE' && payload.new && payload.new.tipo === 'live' && payload.new.live_id &&
               !payload.new.lida && document.visibilityState === 'visible') {   // marcar como lida não avisa
        const { data: l } = await supabaseClient.from('lives').select('estado, ended_at, autor:perfis!lives_user_id_fkey(full_name)').eq('id', payload.new.live_id).maybeSingle();
        if (l && l.estado === 'terminada' && !FC._fimAvisado.has(payload.new.live_id)) {
          FC._fimAvisado.add(payload.new.live_id);
          FC.toast('⏹ ' + ((l.autor && l.autor.full_name) || 'A live') + ' terminou a live' + (l.ended_at ? ' ' + FC.dataHora(l.ended_at).replace(/^hoje, [^,]+, /, '') : ''));
        }
      }
      else if (payload.eventType === 'INSERT' && payload.new && payload.new.tipo !== 'lojas_hoje' && document.visibilityState === 'visible') {
        const n = payload.new;
        const { data: a } = await supabaseClient.from('perfis').select('full_name').eq('id', n.autor_id).maybeSingle();
        const oferta = n.tipo === 'publicacao' && /^⚡/.test(n.texto || '');
        FC.toast('🔔 ' + ((a && a.full_name) || 'Alguém') + ' ' + (oferta ? 'publicou uma oferta relâmpago ⚡' : (FC._notifTextos[n.tipo] || '')));
      }
    })
    .subscribe() && setInterval(() => { if (document.visibilityState === 'visible') contar(); }, 60000);
};

/* ---------- Estatísticas das empresas ----------
   FC.registarEvento(empresaId, 'perfil'|'whatsapp'|'ligar'|'email'|'site'|'anuncio', alvo)
   Links com data-fc-evento="whatsapp" data-empresa="<id>" são contados sozinhos ao clicar.
   A base de dados ignora o próprio dono e não conta a mesma pessoa várias vezes. */
FC.registarEvento = function (empresa, tipo, alvo) {
  if (!empresa || !tipo) return;
  try { supabaseClient.rpc('registar_evento', { p_empresa: empresa, p_tipo: tipo, p_alvo: alvo == null ? null : String(alvo) }).then(() => {}, () => {}); } catch (e) {}
};
FC._vistasPendentes = new Set();
FC.registarVista = function (postId) {   // publicação que apareceu no ecrã (envia em grupos)
  if (!postId) return;
  FC._vistasPendentes.add(Number(postId));
  clearTimeout(FC._vistasT);
  FC._vistasT = setTimeout(() => {
    const ids = [...FC._vistasPendentes].slice(0, 30); FC._vistasPendentes.clear();
    if (ids.length) supabaseClient.rpc('registar_vistas', { p_posts: ids }).then(() => {}, () => {});
  }, 2500);
};
document.addEventListener('click', e => {
  const a = e.target.closest && e.target.closest('[data-fc-evento][data-empresa]');
  if (a) FC.registarEvento(a.dataset.empresa, a.dataset.fcEvento, a.dataset.alvo);
}, true);

/* ---------- Instalar a aplicação (sem APK, sem aviso de risco) ----------
   O Chrome instala o site como aplicação: ícone no ecrã, abre em ecrã inteiro e
   atualiza-se sozinha. */
FC._instalar = null;
window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); FC._instalar = e; document.dispatchEvent(new CustomEvent('fc:instalavel')); });
window.addEventListener('appinstalled', () => { FC._instalar = null; });
FC.appInstalada = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
FC.instalarApp = async function () {
  if (FC._instalar) { FC._instalar.prompt(); try { await FC._instalar.userChoice; } catch (e) {} FC._instalar = null; return; }
  alert('Para instalar: no Chrome, toque nos 3 pontos (⋮) em cima à direita e escolha "Instalar aplicação" ou "Adicionar ao ecrã principal".');
};

/* ---------- Notificações push (mensagens novas, mesmo com a aplicação fechada) ---------- */
FC.PUSH_URL = SUPABASE_URL + '/functions/v1/push';
FC.pushSuportado = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => { navigator.serviceWorker.register('/sw.js').catch(() => {}); });
}
function _b64(u) {   // chave base64url → bytes
  const p = '='.repeat((4 - u.length % 4) % 4), b = atob((u + p).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(b, c => c.charCodeAt(0));
}
// regista este aparelho (pede autorização se ainda não foi dada). Devolve true se ficou ativo.
FC.ativarPush = async function (pedir = true) {
  try {
    if (!FC.pushSuportado()) return false;
    if (Notification.permission === 'denied') return false;
    if (Notification.permission !== 'granted') {
      if (!pedir) return false;
      if (await Notification.requestPermission() !== 'granted') return false;
    }
    const session = await FC.getSession(); if (!session) return false;
    const reg = await navigator.serviceWorker.register('/sw.js');
    await navigator.serviceWorker.ready;
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      const r = await fetch(FC.PUSH_URL, { headers: { Authorization: 'Bearer ' + SUPABASE_ANON_KEY, apikey: SUPABASE_ANON_KEY } });
      const { chave } = await r.json();
      if (!chave) return false;
      sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: _b64(chave) });
    }
    const j = sub.toJSON();
    const { error } = await supabaseClient.rpc('guardar_push', { p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth });
    if (error) { console.warn('push:', error.message); return false; }
    try { localStorage.setItem('fc_push_ok', '1'); } catch (e) {}
    return true;
  } catch (e) { console.warn('push:', e); return false; }
};
// ao sair da conta: este aparelho deixa de receber avisos desta conta
FC.desativarPush = async function () {
  try {
    if (!('serviceWorker' in navigator)) return;
    const reg = await navigator.serviceWorker.getRegistration(); if (!reg) return;
    const sub = await reg.pushManager.getSubscription(); if (!sub) return;
    await supabaseClient.rpc('apagar_push', { p_endpoint: sub.endpoint });
  } catch (e) {}
};
// conta suspensa pelo administrador: faixa no topo com o motivo e atalho para falar com a equipa
FC.avisoSuspensa = function (me) {
  if (document.getElementById('fc-suspensa')) return;
  const el = document.createElement('div');
  el.id = 'fc-suspensa';
  el.style.cssText = 'position:sticky;top:0;z-index:5200;background:#7f1d1d;color:#fff;padding:10px 14px;font:600 13.5px/1.45 Inter,system-ui,sans-serif;text-align:center';
  const motivo = (me.bloqueio_motivo || '').replace(/[<>&"]/g, '');
  el.innerHTML = '🚫 A sua conta está suspensa' + (motivo ? ': ' + motivo : '.') + ' Não pode publicar nem enviar mensagens. <a href="mensagen.html" style="color:#fde68a;text-decoration:underline">Fale com a equipa</a>';
  document.body.prepend(el);
};
FC.toast = function (txt) {
  const t = document.createElement('div');
  t.textContent = txt;
  t.style.cssText = 'position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:6500;background:#16161a;color:#f4f4f5;border:1px solid rgba(243,198,78,.35);padding:11px 16px;border-radius:12px;font:600 14px Inter,system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.4);max-width:90vw;text-align:center';
  document.body.appendChild(t); setTimeout(() => t.remove(), 3200);
};
// convite (uma vez, com calma): "Receber avisos de mensagens novas?"
FC.convitePush = function () {
  if (!FC.pushSuportado() || Notification.permission !== 'default') return;
  try { if (Date.now() - Number(localStorage.getItem('fc_push_convite') || 0) < 7 * 24 * 3600 * 1000) return; } catch (e) { return; }
  setTimeout(() => {
    if (document.getElementById('fc-push-convite') || document.getElementById('fc-lembrete')) return;
    const el = document.createElement('div');
    el.id = 'fc-push-convite';
    el.innerHTML =
      '<style>#fc-push-convite{position:fixed;left:12px;right:12px;bottom:16px;z-index:5500;max-width:420px;margin:0 auto;background:#16161a;color:#f4f4f5;border:1px solid rgba(243,198,78,.35);border-radius:16px;padding:16px;box-shadow:0 14px 40px rgba(0,0,0,.45);font-family:Inter,"Segoe UI",system-ui,sans-serif;display:flex;gap:12px;align-items:flex-start}' +
      '#fc-push-convite .i{font-size:26px;line-height:1}#fc-push-convite b{display:block;font-size:15px;margin-bottom:3px}#fc-push-convite p{margin:0 0 10px;color:#a1a1aa;font-size:13px;line-height:1.45}' +
      '#fc-push-convite .bt{display:flex;gap:8px}#fc-push-convite button{flex:1;padding:10px;border-radius:10px;font:inherit;font-weight:700;font-size:14px;cursor:pointer}' +
      '#fc-push-convite .sim{background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#000;border:none}#fc-push-convite .nao{background:#1f1f25;color:#f4f4f5;border:1px solid #2c2c34}</style>' +
      '<div class="i">🔔</div><div style="flex:1"><b>Avisos de mensagens e novidades</b><p>Saiba logo quando lhe enviam uma mensagem, comentam ou quando quem segue publica, mesmo com a aplicação fechada.</p>' +
      '<div class="bt"><button class="sim" type="button">Ativar</button><button class="nao" type="button">Agora não</button></div></div>';
    const fechar = () => { el.remove(); try { localStorage.setItem('fc_push_convite', String(Date.now())); } catch (e) {} };
    el.querySelector('.nao').onclick = fechar;
    el.querySelector('.sim').onclick = async () => { fechar(); const ok = await FC.ativarPush(true); if (ok) FC.toast('🔔 Avisos ligados.'); };
    document.body.appendChild(el);
  }, 6000);
};

/* ---------- Selos oficiais (Administrador / Equipa Feira Comercial) ----------
   Qualquer elemento com data-selo="<id do perfil>" recebe o selo, se a conta for oficial. */
FC._selos = new Map();
FC._selosDesde = new Map();
FC.carregarSelos = async function () {
  try {
    const c = sessionStorage.getItem('fc_selos');
    if (c) JSON.parse(c).forEach(r => { FC._selos.set(r.id, r.selo); if (r.desde) FC._selosDesde.set(r.id, r.desde); });
  } catch (e) {}
  FC.aplicarSelos();
  const { data, error } = await supabaseClient.rpc('selos');
  if (error || !data) return;
  FC._selos = new Map(data.map(r => [r.id, r.selo]));
  FC._selosDesde = new Map(data.filter(r => r.desde).map(r => [r.id, r.desde]));
  try { sessionStorage.setItem('fc_selos', JSON.stringify(data)); } catch (e) {}
  FC.aplicarSelos();
  document.dispatchEvent(new CustomEvent('fc:selos'));
};
FC.seloHtml = function (id) {
  const s = FC._selos.get(id);
  if (!s) return '';
  // loja verificada: coroa dourada 👑 (toque para saber o que significa)
  if (s === 'verificada') return '<span class="fc-coroa" role="img" aria-label="' + FC.t('Loja verificada') + '" title="' + FC.t('Loja verificada') + '"><svg viewBox="0 0 24 20" width="1em" height="0.84em" aria-hidden="true"><path fill="currentColor" d="M2 6.5l5.2 4.2L12 2l4.8 8.7L22 6.5 20 17H4L2 6.5z"/><rect x="4" y="18" width="16" height="2" rx="1" fill="currentColor"/></svg></span>';
  return '<span class="fc-selo" title="Conta oficial — ' + s + '"><i class="fas fa-circle-check"></i> ' + s + '</span>';
};
FC.aplicarSelos = function (raiz) {
  (raiz || document).querySelectorAll('[data-selo]').forEach(el => {
    const id = el.getAttribute('data-selo'), atual = el.querySelector(':scope > .fc-selo, :scope > .fc-coroa');
    if (atual && atual.dataset.de === id) return;
    if (atual) atual.remove();
    const h = FC.seloHtml(id); if (!h) return;
    el.insertAdjacentHTML('beforeend', h);
    el.lastElementChild.dataset.de = id;
  });
};
(function () {
  const css = document.createElement('style');
  css.textContent = '.fc-selo{display:inline-flex;align-items:center;gap:4px;margin-left:6px;padding:2px 8px;border-radius:999px;background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#111;font:700 11px/1.4 Inter,"Segoe UI",system-ui,sans-serif;vertical-align:middle;white-space:nowrap;letter-spacing:.1px}.fc-selo i{font-size:11px}' +
    '.fc-coroa{display:inline-flex;align-items:center;margin-left:5px;color:#f3c64e;font-size:.95em;vertical-align:baseline;cursor:pointer;filter:drop-shadow(0 1px 1px rgba(0,0,0,.35))}' +
    '#fc-coroa-info{position:fixed;z-index:9000;max-width:260px;background:#18181b;color:#f4f4f5;border:1px solid rgba(243,198,78,.5);border-radius:12px;padding:10px 12px;font:500 13px/1.4 Inter,system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.45)}' +
    '#fc-coroa-info b{color:#f3c64e;display:block;margin-bottom:2px}';
  // toque na coroa → explica o que é (sem abrir o perfil por baixo)
  document.addEventListener('click', function (ev) {
    const c = ev.target.closest && ev.target.closest('.fc-coroa');
    const velho = document.getElementById('fc-coroa-info'); if (velho) velho.remove();
    if (!c) return;
    ev.preventDefault(); ev.stopPropagation();
    const id = c.dataset.de, desde = FC._selosDesde.get(id);
    let quando = ''; try { if (desde) quando = new Date(desde).toLocaleDateString((window.FCI18N && FCI18N.lang) === 'en' ? 'en-GB' : 'pt-PT', { month: 'long', year: 'numeric' }); } catch (e) {}
    const d = document.createElement('div'); d.id = 'fc-coroa-info';
    d.innerHTML = '<b>👑 ' + FC.t('Loja verificada') + '</b>' + FC.t('A Equipa Feira Comercial confirmou que esta loja é real.') + (quando ? ' (' + quando + ')' : '');
    document.body.appendChild(d);
    const r = c.getBoundingClientRect();
    d.style.left = Math.max(8, Math.min(innerWidth - d.offsetWidth - 8, r.left - 20)) + 'px';
    d.style.top = (r.bottom + 8 + d.offsetHeight > innerHeight ? r.top - d.offsetHeight - 8 : r.bottom + 8) + 'px';
    setTimeout(() => { if (d.isConnected) d.remove(); }, 5000);
  }, true);
  document.head.appendChild(css);
  let pendente = false;
  new MutationObserver(() => { if (pendente || !FC._selos.size) return; pendente = true; requestAnimationFrame(() => { pendente = false; FC.aplicarSelos(); }); })
    .observe(document.documentElement, { childList: true, subtree: true });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => FC.carregarSelos()); else FC.carregarSelos();
})();

// nomes reservados à conta oficial (a base de dados também bloqueia)
FC.nomeReservado = function (nome) {
  const n = String(nome || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  return /feira\s*comercia/.test(n) || /(^|[^a-z])(administra[a-z]*|admin|moderador[a-z]*)([^a-z]|$)/.test(n);
};

/* ---------- Erros em português claro (nunca mostrar mensagens técnicas) ---------- */
FC.traduzirErro = function (err) {
  const m = String((err && (err.message || err.error_description || err.error)) || err || '');
  if (err) console.warn('[Feira Comercial]', m);
  if (/Failed to fetch|NetworkError|Load failed|network|ERR_INTERNET/i.test(m)) return 'Sem ligação à internet. Verifique a ligação e tente outra vez.';
  if (/JWT|refresh token|not authenticated|session/i.test(m)) return 'A sua sessão terminou. Entre outra vez na sua conta.';
  if (/row-level security|permission denied|not allowed|forbidden/i.test(m)) return 'Não tem permissão para fazer isto.';
  if (/nome reservado/i.test(m)) return 'Este nome é reservado à Feira Comercial. Escolha outro nome.';
  if (/conta suspensa/i.test(m)) return 'A sua conta está suspensa. Fale com a equipa da Feira Comercial pelo chat.';
  if (/duplicate key|already exists|unique/i.test(m)) return 'Isto já existe.';
  if (/exceeded the maximum allowed size|too large|payload/i.test(m)) return 'O ficheiro é demasiado grande.';
  if (/mime type|not supported/i.test(m)) return 'Este tipo de ficheiro não é aceite.';
  if (/value too long|check constraint|violates|invalid input/i.test(m)) return 'Algum dado não é válido (por exemplo, um texto vazio ou demasiado longo).';
  if (/timeout|timed out|504|503/i.test(m)) return 'O servidor demorou a responder. Tente outra vez.';
  if (/rate limit|too many/i.test(m)) return 'Muitas tentativas seguidas. Espere um minuto e tente outra vez.';
  if ((/[áàâãçéêíóôõú]/i.test(m) || /\b(tente|demasiad|aguarde|apenas|empresa|mensalidade)/i.test(m)) && !/[a-z]+_[a-z]+/i.test(m)) return m;   // já vem em português
  return 'Algo correu mal. Tente outra vez daqui a pouco.';
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
      await FC.sincronizarHora();
      const limite = new Date(FC.agora() - 150 * 1000).toISOString();   // hora do servidor; o servidor fecha as paradas
      const { data, error } = await supabaseClient.from('lives')
        .select('id,user_id,titulo,autor:perfis!lives_user_id_fkey(full_name,avatar_url)')
        .eq('estado', 'ao_vivo').gte('atualizado_em', limite)
        .order('started_at', { ascending: false }).limit(6);
      if (!error) mostrar((data || []).filter(l => l.user_id !== uid));
    }, 300);
  };
  // as lives a decorrer vêm do pedido único "estado_agora" (antes: cada página ouvia TODAS as
  // mudanças das lives e repetia a pesquisa a cada 30 s de cada live — com muita gente, rebentava)
  document.addEventListener('fc:estado', e => mostrar(((e.detail && e.detail.lives) || []).filter(l => l.user_id !== uid)));
  let livesAntigo = false;
  document.addEventListener('fc:estado-falhou', () => {
    if (livesAntigo) return; livesAntigo = true;
    carregar();
    setInterval(() => { if (document.visibilityState === 'visible') carregar(); }, 60000);
  });
  FC.iniciarEstado();
};

/* ---------- Estado agora: UM pedido a cada ~90 s com tudo o que o ecrã precisa ----------
   (mensagens por ler, notificações, lives a decorrer, ofertas perto, publicações novas).
   Só pede com a página visível; ao voltar à página pede logo. Se a base de dados ainda não
   tiver a função (migração 045), avisa "fc:estado-falhou" e cada parte volta ao modo antigo. */
FC.iniciarEstado = function () {
  if (FC._estadoLigado) return;
  FC._estadoLigado = true;
  let ultimo = 0, aPedir = false;
  const pedir = async (forcar) => {
    if (aPedir || document.visibilityState !== 'visible') return;
    if (!forcar && Date.now() - ultimo < 20000) return;
    aPedir = true; ultimo = Date.now();
    try {
      const { data, error } = await supabaseClient.rpc('estado_agora');
      if (error || !data) { FC._estadoOk = false; document.dispatchEvent(new CustomEvent('fc:estado-falhou')); return; }
      FC._estadoOk = true; FC.estado = data;
      document.dispatchEvent(new CustomEvent('fc:estado', { detail: data }));
    } finally { aPedir = false; }
  };
  FC.pedirEstado = () => pedir(true);
  const ciclo = () => setTimeout(async () => { if (FC._estadoOk !== false) { await pedir(); ciclo(); } }, 80000 + Math.random() * 20000);
  setTimeout(() => pedir(true), 50);   // deixa as partes ligarem-se aos eventos primeiro
  ciclo();
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') pedir(); });
};

/* ---------- Quem pode publicar (feed, anúncios, Live, produtos) ----------
   Empresas com a mensalidade em dia, e as contas da equipa (administrador / oficial). */
FC.contaEquipa = me => !!me && (me.role === 'admin' || me.role === 'equipa');
FC.podeComoEmpresa = me => !!me && (me.type === 'empresa' || FC.contaEquipa(me));
FC.podePublicar = function (me) {
  me = me || FC.me;
  if (!me) return false;
  if (FC.contaEquipa(me)) return true;
  return me.type === 'empresa' && FC.mensalidade(me).pode;
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
  const dias = ate ? FC.diasAte(ate) : 0;          // dias do calendário até ao fim (0 = acaba hoje)
  const ativa = !!ate && ate.getTime() > FC.agora();
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
  const quando = m.ativa ? 'termina ' + FC.emDias(m.dias) : 'terminou';
  // ainda no período de teste? (a assinatura acaba até 16 dias depois de a conta ser criada)
  const teste = me.created_at && m.ate && (m.ate - new Date(me.created_at)) < 16 * 864e5;
  const oQue = teste ? (m.ativa ? 'Os seus dias grátis' : 'Os seus dias grátis') : 'A mensalidade';
  const quando2 = teste ? (m.ativa ? 'acabam ' + FC.emDias(m.dias) : 'acabaram') : quando;
  const el = document.createElement('div');
  el.id = 'fc-lembrete';
  el.innerHTML =
    '<style>#fc-lembrete{position:fixed;inset:0;z-index:6000;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;padding:16px;font-family:Inter,"Segoe UI",system-ui,sans-serif}' +
    '#fc-lembrete .c{background:#16161a;color:#f4f4f5;border:1px solid rgba(243,198,78,.35);border-radius:20px;max-width:380px;width:100%;padding:24px;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.5)}' +
    '#fc-lembrete .i{font-size:40px}#fc-lembrete h3{margin:8px 0 6px;font-size:19px}#fc-lembrete p{color:#a1a1aa;font-size:14px;line-height:1.5;margin:0 0 18px}' +
    '#fc-lembrete a,#fc-lembrete button{display:block;width:100%;padding:13px;border-radius:12px;font:inherit;font-weight:700;font-size:15px;cursor:pointer;text-decoration:none;box-sizing:border-box}' +
    '#fc-lembrete a{background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#000;border:none;margin-bottom:8px}#fc-lembrete button{background:#1f1f25;color:#f4f4f5;border:1px solid #2c2c34}</style>' +
    '<div class="c" role="dialog" aria-modal="true"><div class="i">' + (teste ? '⏰' : '💳') + '</div><h3>' + oQue + ' ' + quando2 + '</h3>' +
    '<p>Pague <b style="color:#f3c64e">100 MT</b> por transferência bancária para a sua empresa <b>não ficar sem acesso</b> a publicações, anúncios e Live.</p>' +
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
  FC.sino();
  FC.vigiarLives();
  if (me && me.bloqueado) FC.avisoSuspensa(me);
  // o perfil guardado pode ser antigo: quando chega o atualizado, confirma a suspensão
  document.addEventListener('fc:perfil', e => { if (e.detail && e.detail.bloqueado) FC.avisoSuspensa(e.detail); });
  // idioma: num aparelho novo segue o da conta; se a pessoa escolheu outro neste aparelho, a conta passa a usar esse
  if (me && me.idioma && window.FCI18N) {
    const aqui = FCI18N.escolhido && FCI18N.escolhido();
    if (!aqui && me.idioma !== FCI18N.lang) { try { localStorage.setItem('fc_lang', me.idioma); } catch (e) {} location.reload(); return me; }
    if (aqui && aqui !== me.idioma) FCI18N.guardarNaConta(aqui);
  }
  // avisos push: renova o registo deste aparelho em silêncio, ou convida (uma vez) a ativar
  if (FC.pushSuportado() && Notification.permission === 'granted') FC.ativarPush(false); else FC.convitePush();
  if (me && me.type === 'empresa') FC.carregarConfig().then(() => FC.lembreteMensalidade(me));
  return me;
};

/* Partilhar: abre uma folha com WhatsApp, Facebook, Telegram, SMS, Copiar link e "Mais"
   (o menu do próprio telemóvel), em vez de só copiar o link. */
FC.t = s => (window.FCI18N && FCI18N.t) ? FCI18N.t(s) : s;   // traduz textos montados em JavaScript (modo inglês)
FC.partilhar = function (o) {
  o = o || {};
  const url = o.url || location.href, texto = o.texto || '';
  const tudo = (texto ? texto + ' ' : '') + url;
  const enc = encodeURIComponent;
  if (!document.getElementById('fc-part-css')) {
    const css = document.createElement('style'); css.id = 'fc-part-css';
    css.textContent =
      '#fc-part-f{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:7000;display:flex;align-items:flex-end;justify-content:center}' +
      '#fc-part{width:min(520px,100%);background:var(--bg-card,var(--bg-secondary,#1c1e21));color:var(--text-main,var(--text-primary,#e4e6eb));border-radius:18px 18px 0 0;padding:16px 16px calc(18px + env(safe-area-inset-bottom));font-family:inherit;animation:fcPartSobe .2s ease}' +
      '@keyframes fcPartSobe{from{transform:translateY(40px);opacity:0}}' +
      '#fc-part .cab{display:flex;align-items:center;margin-bottom:14px}#fc-part .cab b{flex:1;font-size:17px}' +
      '#fc-part .cab button{border:none;background:none;color:inherit;font-size:22px;width:36px;height:36px;border-radius:50%;cursor:pointer}' +
      '#fc-part .gr{display:grid;grid-template-columns:repeat(3,1fr);gap:14px 8px}' +
      '#fc-part .gr a,#fc-part .gr button{display:flex;flex-direction:column;align-items:center;gap:6px;text-decoration:none;color:inherit;font-size:13px;font-weight:600;font-family:inherit;background:none;border:none;cursor:pointer;padding:0}' +
      '#fc-part .gr i{width:54px;height:54px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:25px;color:#fff}';
    document.head.appendChild(css);
  }
  const fechar = () => { const f = document.getElementById('fc-part-f'); if (f) f.remove(); };
  fechar();
  const f = document.createElement('div'); f.id = 'fc-part-f';
  const item = (href, ico, cor, nome) => '<a href="' + href + '" target="_blank" rel="noopener" data-p="1"><i class="' + ico + '" style="background:' + cor + '"></i>' + nome + '</a>';
  f.innerHTML = '<div id="fc-part" role="dialog" aria-label="Partilhar"><div class="cab"><b>Partilhar</b><button type="button" aria-label="Fechar">×</button></div><div class="gr">' +
    '<button type="button" data-chat="1"><i class="fas fa-comment-dots" style="background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#111"></i>No chat</button>' +
    item('https://wa.me/?text=' + enc(tudo), 'fab fa-whatsapp', '#25d366', 'WhatsApp') +
    item('https://www.facebook.com/sharer/sharer.php?u=' + enc(url), 'fab fa-facebook-f', '#1877f2', 'Facebook') +
    item('https://t.me/share/url?url=' + enc(url) + (texto ? '&text=' + enc(texto) : ''), 'fab fa-telegram', '#29a9eb', 'Telegram') +
    item('sms:?&body=' + enc(tudo), 'fas fa-comment-sms', '#64748b', 'SMS') +
    '<button type="button" data-copiar="1"><i class="fas fa-link" style="background:#475569"></i>Copiar link</button>' +
    (navigator.share ? '<button type="button" data-mais="1"><i class="fas fa-ellipsis" style="background:#334155"></i>Mais</button>' : '') +
    '</div></div>';
  f.addEventListener('click', async ev => {
    const t = ev.target.closest('a,button');
    if (ev.target === f || (t && t.closest('.cab'))) return fechar();
    if (!t) return;
    if (t.dataset.p) { setTimeout(fechar, 300); return; }
    if (t.dataset.chat) { fechar(); FC.enviarNoChat(o); return; }
    if (t.dataset.copiar) {
      try { await navigator.clipboard.writeText(url); }
      catch (e) { const i = document.createElement('textarea'); i.value = url; document.body.appendChild(i); i.select(); try { document.execCommand('copy'); } catch (x) {} i.remove(); }
      fechar(); FC.toast('Link copiado!'); return;
    }
    if (t.dataset.mais) { fechar(); try { await navigator.share({ title: o.titulo || 'Feira Comercial', text: texto, url }); } catch (e) {} }
  });
  document.body.appendChild(f);
};

/* Enviar no chat da Feira Comercial: escolher uma ou mais pessoas e enviar a foto, o vídeo
   ou o link diretamente, sem sair da página.
   o = { url, texto, media: { url, type: 'image'|'video' }, ref: { tipo, id, userName, text, thumb } } */
FC.enviarNoChat = async function (o) {
  o = o || {};
  const T = FC.t, esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const { data: { session } } = await supabaseClient.auth.getSession();
  const eu = session && session.user && session.user.id;
  if (!eu) { location.href = 'Portal.html'; return; }
  if (!document.getElementById('fc-chat-css')) {
    const css = document.createElement('style'); css.id = 'fc-chat-css';
    css.textContent =
      '#fc-nc .ls{max-height:min(46vh,360px);overflow-y:auto;margin:10px -4px;display:flex;flex-direction:column;gap:2px}' +
      '#fc-nc label{display:flex;align-items:center;gap:12px;padding:8px 6px;border-radius:12px;cursor:pointer}' +
      '#fc-nc label:hover{background:rgba(255,255,255,.06)}' +
      '#fc-nc label img{width:42px;height:42px;border-radius:50%;object-fit:cover;background:#475569;flex-shrink:0}' +
      '#fc-nc label span{flex:1;min-width:0;font-weight:600;font-size:14.5px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '#fc-nc label input{width:22px;height:22px;accent-color:#d9a52e;flex-shrink:0}' +
      '#fc-nc input[type=search],#fc-nc input.nota{width:100%;box-sizing:border-box;padding:11px 14px;border-radius:12px;border:1px solid rgba(148,163,184,.35);background:rgba(148,163,184,.1);color:inherit;font:inherit;font-size:15px;outline:none}' +
      '#fc-nc .pre{display:flex;align-items:center;gap:10px;font-size:13px;opacity:.85;margin-bottom:10px}' +
      '#fc-nc .pre img,#fc-nc .pre video{width:46px;height:46px;border-radius:8px;object-fit:cover;background:#000}' +
      '#fc-nc .env{width:100%;margin-top:10px;padding:13px;border:none;border-radius:12px;font:inherit;font-weight:700;font-size:15px;cursor:pointer;background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#111}' +
      '#fc-nc .env:disabled{opacity:.45;cursor:default}' +
      '#fc-nc .vz{padding:18px 6px;text-align:center;opacity:.7;font-size:14px}';
    document.head.appendChild(css);
  }
  const f = document.createElement('div'); f.id = 'fc-part-f';
  const m = o.media && FC.u(o.media.url) ? o.media : null;
  const pre = m ? (m.type === 'video' ? '<video src="' + FC.u(m.url) + '#t=0.1" muted preload="metadata"></video>' + T('Vídeo') : '<img src="' + FC.u(m.url) + '" alt="">' + T('Foto'))
                : '<i class="fas fa-link" style="font-size:18px"></i>' + esc((o.texto || '').slice(0, 60));
  f.innerHTML = '<div id="fc-part" class="fc-nc" role="dialog" aria-label="' + T('Enviar no chat') + '"><div id="fc-nc">' +
    '<div class="cab" style="display:flex;align-items:center;margin-bottom:10px"><b style="flex:1;font-size:17px">' + T('Enviar no chat') + '</b><button type="button" class="x" aria-label="Fechar" style="border:none;background:none;color:inherit;font-size:22px;width:36px;height:36px;cursor:pointer">×</button></div>' +
    '<div class="pre">' + pre + '</div>' +
    '<input type="search" placeholder="' + T('Procurar pessoa…') + '" autocomplete="off">' +
    '<div class="ls"><p class="vz">' + T('A carregar…') + '</p></div>' +
    '<input class="nota" maxlength="500" placeholder="' + T('Escreva algo (opcional)') + '">' +
    '<button type="button" class="env" disabled>' + T('Enviar') + '</button></div></div>';
  document.body.appendChild(f);
  const $ = q => f.querySelector(q), escolhidos = new Map();
  const fechar = () => f.remove();
  f.addEventListener('click', e => { if (e.target === f || e.target.closest('.x')) fechar(); });
  const avatar = p => FC.u(p.avatar_url) || ('https://ui-avatars.com/api/?name=' + encodeURIComponent(p.full_name || 'U') + '&background=random&color=fff&size=84');
  const desenhar = lista => {
    $('.ls').innerHTML = lista.length ? lista.map(p => '<label><img src="' + avatar(p) + '" alt=""><span>' + esc(p.full_name || T('Utilizador')) + '</span><input type="checkbox" value="' + esc(p.id) + '"' + (escolhidos.has(p.id) ? ' checked' : '') + '></label>').join('')
      : '<p class="vz">' + T('Ninguém encontrado.') + '</p>';
    lista.forEach(p => { if (!desenhar.cache[p.id]) desenhar.cache[p.id] = p; });
  };
  desenhar.cache = {};
  const atualizarBotao = () => { const n = escolhidos.size; $('.env').disabled = !n; $('.env').textContent = T('Enviar') + (n ? ' (' + n + ')' : ''); };
  $('.ls').addEventListener('change', e => {
    const c = e.target; if (c.type !== 'checkbox') return;
    if (c.checked) { if (escolhidos.size >= 10) { c.checked = false; FC.toast(T('Máximo 10 pessoas de cada vez.')); return; } escolhidos.set(c.value, desenhar.cache[c.value]); }
    else escolhidos.delete(c.value);
    atualizarBotao();
  });
  // sugestões: conversas recentes + quem segue
  let sugestoes = [];
  try {
    const [r1, r2] = await Promise.all([
      supabaseClient.from('messages').select('sender_id, receiver_id').or('sender_id.eq.' + eu + ',receiver_id.eq.' + eu).order('created_at', { ascending: false }).limit(300),
      supabaseClient.from('followers').select('following_id').eq('follower_id', eu).limit(60)]);
    const ids = [];
    (r1.data || []).forEach(x => { const o2 = x.sender_id === eu ? x.receiver_id : x.sender_id; if (o2 && !ids.includes(o2)) ids.push(o2); });
    (r2.data || []).forEach(x => { if (x.following_id && !ids.includes(x.following_id)) ids.push(x.following_id); });
    const sel = ids.filter(i => i !== eu).slice(0, 40);
    if (sel.length) {
      const { data } = await supabaseClient.from('perfis').select('id, full_name, avatar_url').in('id', sel);
      sugestoes = sel.map(i => (data || []).find(p => p.id === i)).filter(Boolean);
    }
  } catch (e) {}
  desenhar(sugestoes);
  if (!sugestoes.length) $('.ls').innerHTML = '<p class="vz">' + T('Escreva o nome da pessoa.') + '</p>';
  let tp = null;
  $('input[type=search]').addEventListener('input', e => {
    clearTimeout(tp);
    const q = e.target.value.replace(/[%,()]/g, ' ').trim();
    tp = setTimeout(async () => {
      if (q.length < 2) { desenhar(sugestoes); return; }
      const { data } = await supabaseClient.from('perfis').select('id, full_name, avatar_url').ilike('full_name', '%' + q + '%').neq('id', eu).limit(20);
      desenhar(data || []);
    }, 300);
  });
  $('.env').addEventListener('click', async () => {
    const b = $('.env'); b.disabled = true; b.textContent = T('A enviar…');
    const nota = $('.nota').value.trim();
    const conteudo = m ? nota : [nota, (o.texto || '') + ' ' + (o.url || '')].filter(x => x && x.trim()).join('\n').trim();
    const linhas = [...escolhidos.keys()].map(id => ({
      sender_id: eu, receiver_id: id, content: conteudo || '',
      file_url: m ? m.url : null, media_type: m ? (m.type === 'video' ? 'video' : 'image') : null,
      ref: o.ref || null }));
    const res = await Promise.all(linhas.map(l => supabaseClient.from('messages').insert(l).then(r => !r.error, () => false)));
    const ok = res.filter(Boolean).length, falhou = res.length - ok;
    fechar();
    if (ok && !falhou) FC.toast(ok === 1 ? T('Enviado ✓') : T('Enviado a') + ' ' + ok + ' ' + T('pessoas ✓'));
    else if (ok) FC.toast(T('Enviado a') + ' ' + ok + '. ' + falhou + ' ' + T('não aceitam mensagens.'));
    else FC.toast(T('Não foi possível enviar. Tente outra vez.'));
  });
};

/* Ver um vídeo da Feira Comercial por cima da página, com botão "Voltar" bem visível.
   O botão "voltar" do telemóvel também fecha o vídeo (em vez de sair da página). */
FC.verVideo = function (url) {
  if (!/^https:\/\/(www\.)?feira-comercial\.com\/media\/[\w-]+\.mp4$/i.test(url) && !/^\/?media\/[\w-]+\.mp4$/.test(url)) { location.href = url; return; }
  const ant = document.getElementById('fc-vv'); if (ant) ant.remove();
  const d = document.createElement('div'); d.id = 'fc-vv';
  d.innerHTML = '<style>#fc-vv{position:fixed;inset:0;z-index:8000;background:#000;display:flex;align-items:center;justify-content:center}' +
    '#fc-vv video{max-width:100%;max-height:100%;width:100%;height:100%;object-fit:contain;background:#000}' +
    '#fc-vv button{position:absolute;top:calc(14px + env(safe-area-inset-top));left:14px;z-index:2;display:flex;align-items:center;gap:8px;padding:11px 18px;border:none;border-radius:999px;' +
    'background:rgba(255,255,255,.92);color:#111;font:700 15px Inter,system-ui,sans-serif;cursor:pointer;box-shadow:0 6px 20px rgba(0,0,0,.4)}</style>' +
    '<button type="button"><i class="fas fa-arrow-left"></i> Voltar</button>' +
    '<video src="' + url.replace(/"/g, '') + '" controls autoplay playsinline></video>';
  let fechado = false;
  const fechar = (doHistorico) => {
    if (fechado) return; fechado = true;
    try { d.querySelector('video').pause(); } catch (e) {}
    d.remove(); window.removeEventListener('popstate', aoVoltar);
    if (doHistorico !== true) { try { history.back(); } catch (e) {} }
  };
  const aoVoltar = () => fechar(true);
  d.querySelector('button').onclick = () => fechar();
  d.querySelector('video').addEventListener('ended', () => fechar());
  document.body.appendChild(d);
  try { history.pushState({ fcVideo: 1 }, ''); } catch (e) {}
  window.addEventListener('popstate', aoVoltar);
};

/* Denunciar um comentário ofensivo: abre o Livro de Reclamações já preenchido
   (a equipa vê o comentário, quem o escreveu e o link da publicação/vídeo). */
FC.denunciarComentario = function (autor, texto, link, id, tipo) {
  // o número do comentário vai no link, para a Equipa o poder esconder diretamente
  if (id) link = (link || location.href) + ((link || location.href).indexOf('?') >= 0 ? '&' : '?') + (tipo === 'video' ? 'vcom=' : 'com=') + encodeURIComponent(id);
  const t = String(texto || '').replace(/\s+/g, ' ').slice(0, 90);
  const assunto = 'Denúncia de comentário de ' + String(autor || 'utilizador').slice(0, 40) + ': "' + t + (String(texto || '').length > 90 ? '…' : '') + '"';
  location.href = 'reclamacao.html?tipo=denuncia&assunto=' + encodeURIComponent(assunto.slice(0, 150)) + '&link=' + encodeURIComponent(link || location.href);
};
