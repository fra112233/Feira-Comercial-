/* Feira Comercial — service worker
   Só trata das notificações push (mensagens novas). Não guarda páginas em cache,
   por isso as atualizações do site continuam a chegar logo. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

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
