// ============================================================
// Nordic Media Engine — Service Worker
// App-shell caching + offline fallback + push-notifikationer
// ============================================================

const CACHE_VERSION = 'venstre-syddjurs-v1';
const APP_SHELL = ['./', './index.html', './index.html?org=venstre-syddjurs', './config.js', './manifest.json'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_VERSION).then((cache) => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  if (req.url.includes('supabase.co')) return; // data skal altid være friskt

  event.respondWith(
    fetch(req)
      .then((res) => { const clone = res.clone(); caches.open(CACHE_VERSION).then((c) => c.put(req, clone)); return res; })
      .catch(() => caches.match(req).then((cached) => cached || caches.match('./index.html')))
  );
});

// Selve afsendelsen af push-beskeder sker server-side (Supabase Edge Function
// med VAPID private key). Denne handler modtager og viser beskeden.
self.addEventListener('push', (event) => {
  let data = { title: 'Nyt indhold', body: 'Der er nyt at læse.' };
  try { data = event.data.json(); } catch (e) {}
  event.waitUntil(self.registration.showNotification(data.title, {
    body: data.body, icon: 'icon-192.png', badge: 'icon-192.png', data: { url: data.url || './index.html' }
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(self.clients.matchAll({ type: 'window' }).then((clients) => {
    const url = event.notification.data?.url || './index.html';
    for (const client of clients) { if (client.url.includes(url) && 'focus' in client) return client.focus(); }
    return self.clients.openWindow(url);
  }));
});
