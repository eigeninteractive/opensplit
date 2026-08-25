'use strict';

// The offline shell.
//
// OpenSplit keeps every expense in SQLite on the device and renders every
// screen from it, so the app has nothing to ask a server for in order to work.
// On the web that promise is only as good as whether the *code* is there: with
// no service worker, a reload with no connection is a blank page, and the whole
// thing is a website that happens to store data locally.
//
// Two strategies, chosen by what the request is for.
//
//   Navigations are network-first. index.html is the one file that names all
//   the others, so a stale copy is how an app gets stuck on an old build
//   forever. Online it is always fresh; offline it comes from the cache.
//
//   Everything else same-origin is stale-while-revalidate: answer from the
//   cache immediately — which is what makes a warm start feel instant rather
//   than like a download — and refresh the entry in the background for next
//   time.
//
// Nothing cross-origin is touched. Supabase carries the user's data and their
// session; caching any of it would mean serving one person's ledger from
// another person's cache after a sign-in change.

const CACHE = 'opensplit-shell-v1';

// Fetched on install so that a first visit which never goes offline still has
// enough cached to start. Everything else arrives through the fetch handler as
// the app asks for it.
const CORE = [
  '.',
  'index.html',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      // Individually, so one 404 does not abort the whole install.
      .then((cache) => Promise.all(CORE.map((url) => cache.add(url).catch(() => {}))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Only GET is cacheable, and only our own origin is ours to cache.
  if (request.method !== 'GET') return;
  if (new URL(request.url).origin !== self.location.origin) return;

  // A range request served from a full cached body is a corrupt response; let
  // the network answer those.
  if (request.headers.has('range')) return;

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put('index.html', copy));
          return response;
        })
        .catch(() =>
          caches
            .match('index.html')
            .then((cached) => cached || Response.error()),
        ),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      const network = fetch(request)
        .then((response) => {
          if (response && response.ok && response.type === 'basic') {
            const copy = response.clone();
            caches.open(CACHE).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => cached);

      return cached || network;
    }),
  );
});
