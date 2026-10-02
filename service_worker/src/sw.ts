/**
 * The app's one service worker, at /app/sw.js with scope /app/: it serves the
 * client offline and receives web push. Firebase's token registration names
 * this same script (lib/data/push/push_service.dart), so push never installs
 * a second worker that would replace this one.
 *
 * Built by build.ts, which fills in the precache manifest and the Firebase
 * configuration.
 */
import { type FirebaseOptions, initializeApp } from "firebase/app";
import { getMessaging, onBackgroundMessage } from "firebase/messaging/sw";
import { clientsClaim } from "workbox-core";
import { cleanupOutdatedCaches, createHandlerBoundToURL, type PrecacheEntry, precacheAndRoute } from "workbox-precaching";
import { NavigationRoute, registerRoute } from "workbox-routing";

import { SKIP_WAITING } from "./messages.ts";
import { groupOf, openGroup, showActivity } from "./push.ts";

declare const self: ServiceWorkerGlobalScope & { __WB_MANIFEST: (string | PrecacheEntry)[] };

/** The web app's public Firebase identifiers, or null when push is not configured. */
declare const __FIREBASE_CONFIG__: FirebaseOptions | null;

// The whole release, installed all-or-nothing: a partial shell is not an
// offline-capable one.
precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();

// Every navigation in scope is a client route, so each answers with the shell
// and go_router takes it from there. Deep links open offline too.
registerRoute(new NavigationRoute(createHandlerBoundToURL("/app/index.html")));

// No skipWaiting of its own accord: a tab in the middle of an edit keeps the
// release it loaded. The page offers a restart, and asks for this once the
// person takes it (lib/data/web/release_updates_web.dart).
self.addEventListener("message", (event) => {
  if (event.data?.type === SKIP_WAITING) void self.skipWaiting();
});
clientsClaim();

/**
 * The worker before this one was hand-written, and answered every reload with
 * a cached redirect, which the browser shows as ERR_FAILED. Waiting for its
 * tabs to close would leave that in place for as long as anyone keeps one open,
 * so it is replaced as soon as this one has installed. Its caches carry its
 * name, which is how it is recognised. Safe to delete once no browser is
 * likely to still have it.
 */
const LEGACY_CACHE_PREFIX = "opensplit-shell-";
const legacyCaches = async () => (await caches.keys()).filter((key) => key.startsWith(LEGACY_CACHE_PREFIX));

self.addEventListener("install", (event) => {
  event.waitUntil(legacyCaches().then((keys) => (keys.length > 0 ? self.skipWaiting() : undefined)));
});
self.addEventListener("activate", (event) => {
  event.waitUntil(legacyCaches().then((keys) => Promise.all(keys.map((key) => caches.delete(key)))));
});

if (__FIREBASE_CONFIG__) {
  // Only pushes that arrive with no visible tab reach here; Firebase forwards
  // the rest to the page, which syncs and redraws.
  onBackgroundMessage(getMessaging(initializeApp(__FIREBASE_CONFIG__)), (payload) => showActivity(self, payload.data));
}

self.addEventListener("notificationclick", (event) => {
  const groupId = groupOf(event.notification);
  if (!groupId) return;
  event.notification.close();
  event.waitUntil(openGroup(self, groupId));
});
