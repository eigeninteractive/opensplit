'use strict';

// One registration owns /app/: Firebase must not replace the offline worker.
// Push initialization is optional; an unavailable SDK must not break offline.
try {
  importScripts('firebase-messaging-sw.js');
} catch (error) {
  console.warn('Push initialization unavailable.', error);
}

const CACHE_PREFIX = 'opensplit-shell-';
const CACHE = CACHE_PREFIX + '__OPEN_SPLIT_BUILD_ID__';
const RESOURCES = __OPEN_SPLIT_RESOURCES__;
const URLS = new Set(
  RESOURCES.map((path) => new URL(path, self.registration.scope).href),
);
const INDEX = new URL('index.html', self.registration.scope).href;

self.addEventListener('install', (event) => {
  // All-or-nothing: a partial shell is not an offline-capable release.
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      cache.addAll([...URLS].map((url) => new Request(url, { cache: 'reload' }))),
    ),
  );
  // Do not skipWaiting: an open editor must keep its entire current release.
  // The next release activates after all existing app tabs have closed.
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE)
          .map((key) => caches.delete(key)),
      ),
    ).then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || request.headers.has('range')) return;
  if (new URL(request.url).origin !== self.location.origin) return;

  const navigation = request.mode === 'navigate' &&
    request.url.startsWith(self.registration.scope);
  const key = navigation ? INDEX : request.url;
  // Never cache API responses, landing/legal pages, or another app's resources.
  if (!navigation && !URLS.has(key)) return;

  event.respondWith(
    caches.open(CACHE).then(async (cache) =>
      (await cache.match(key)) || fetch(request),
    ),
  );
});
