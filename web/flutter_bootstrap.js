// Replaces Flutter's default bootstrap for one reason: to stop it registering
// flutter_service_worker.js.
//
// Flutter deprecated its generated service worker, and what it now emits is an
// 800-byte tombstone that unregisters itself on activate. Leaving it in place
// means the app has no offline story at all — every asset comes off the network
// on every cold start, so a reload on a train is a blank page even though all
// the user's data is already in SQLite on the device.
//
// This registers sw.js instead, which is written by hand and lives beside it.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();

if ('serviceWorker' in navigator) {
  // After load, so fetching the worker never competes with the engine for the
  // connections that decide how fast the first frame arrives.
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').catch(function (error) {
      console.warn('OpenSplit: offline support unavailable', error);
    });
  });
}
