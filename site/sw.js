// A tombstone for the service worker that used to live here.
//
// Before the site was split into a static root and a client under /app, the
// offline worker was registered at scope `/` — and a registration outlives the
// script that made it. That worker is still installed in every browser that
// visited the old layout, it still claims every navigation on the origin, and
// it still answers them out of its own cache: the landing page, /privacy and
// /terms all come back as the Flutter shell it cached months ago.
//
// It cannot fix itself. A worker only updates when the browser re-fetches the
// script at its registered URL, and with nothing served here that fetch was a
// 404 — which fails the update and leaves the old worker exactly where it was.
// So something has to be served here, and this is the smallest thing that ends
// it: install, take over, unregister, and send every page it was holding back
// to the network.
//
// It is not the app's worker. That one is /app/sw.js, registered against
// <base href="/app/"> and scoped to /app/ — a separate registration this file
// never touches. Deleting this file would re-open the 404 and strand anybody
// who has not been back since, so it stays until that is no longer possible.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // Caches are left alone deliberately. Storage is per-origin, so deleting
      // by name here would take the current release's shell with it; the app's
      // own worker already drops every cache but its own when it activates.
      await self.registration.unregister();
      const clients = await self.clients.matchAll({ type: 'window' });
      for (const client of clients) {
        client.navigate(client.url);
      }
    })(),
  );
});
