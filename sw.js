/* Feira Comercial — service worker
   1) Notificações push.
   2) Páginas e ficheiros do site guardados no telemóvel: ao passar de uma página para outra,
      a página abre logo do telemóvel e, ao mesmo tempo, vai buscar a versão nova para a
      próxima vez ("stale-while-revalidate"). Quando sai uma versão nova do site, o
      atualizacao.js limpa esta cache e recarrega — as atualizações continuam a chegar.
   Nunca guarda: dados (Supabase), version.json, /api, vídeos. */
const CACHE = 'fc-site-v1';
const LIBS = /^https:\/\/(cdn\.jsdelivr\.net|kit\.fontawesome\.com|ka-f\.fontawesome\.com|fonts\.googleapis\.com|fonts\.gstatic\.com|cdnjs\.cloudflare\.com)\//;
const ESTATICO = /\.(html|js|css|png|jpg|jpeg|webp|svg|ico|woff2?|webmanifest)$/i;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil((async () => {
  for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
  await self.clients.claim();
})()));

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const mesmo = url.origin === self.location.origin;
  if (mesmo) {
    if (url.pathname === '/version.json' || url.pathname.startsWith('/api/') || url.pathname.startsWith('/loja/') ||
        url.pathname.startsWith('/media/') || url.pathname.endsWith('.xml') || url.pathname.endsWith('.txt')) return;
    const pagina = req.mode === 'navigate';
    if (!pagina && !ESTATICO.test(url.pathname)) return;
    if (pagina && !(url.pathname === '/' || url.pathname.endsWith('.html'))) return;
    // as páginas guardam-se sem o "?…" (index.html?post=5 abre a mesma página)
    const chave = pagina ? new Request(url.origin + url.pathname) : req;
    e.respondWith(guardadoOuRede(e, chave, req));
    return;
  }
  if (LIBS.test(req.url)) e.respondWith(guardadoOuRede(e, req, req));
});

async function guardadoOuRede(e, chave, req) {
  const cache = await caches.open(CACHE);
  const guardado = await cache.match(chave);
  const rede = fetch(req).then(r => {
    // só respostas boas e sem redirecionamento (uma página redirecionada não pode servir de cópia)
    if (r && !r.redirected && (r.ok || r.type === 'opaque')) cache.put(chave, r.clone()).catch(() => {});
    return r;
  });
  if (guardado) { e.waitUntil(rede.catch(() => {})); return guardado; }
  return rede;
}

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (x) { d = { body: e.data ? e.data.text() : '' }; }
  e.waitUntil((async () => {
    try { if (d.count && self.navigator.setAppBadge) await self.navigator.setAppBadge(d.count); } catch (x) {}
    await self.registration.showNotification(d.title || 'Feira Comercial', {
      body: d.body || 'Tem uma mensagem nova.',
      icon: d.icon || '/images/icone-192.png',
      badge: '/images/badge-96.png',
      tag: d.tag || 'feira-comercial',
      renotify: true,
      vibrate: [120, 60, 120],
      data: { url: d.url || '/mensagen.html' }
    });
  })());
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const alvo = new URL((e.notification.data && e.notification.data.url) || '/mensagen.html', self.location.origin).href;
  e.waitUntil((async () => {
    const janelas = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const j of janelas) {
      if (new URL(j.url).origin === self.location.origin) {
        await j.focus();
        try { await j.navigate(alvo); } catch (x) {}
        return;
      }
    }
    await self.clients.openWindow(alvo);
  })());
});
