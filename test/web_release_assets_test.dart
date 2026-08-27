import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the source workers require release-time version and FCM injection', () {
    final shellWorker = File('web/sw.js').readAsStringSync();
    final messagingWorker = File(
      'web/firebase-messaging-sw.js',
    ).readAsStringSync();

    expect(shellWorker, contains('__OPEN_SPLIT_BUILD_ID__'));
    expect(shellWorker, contains('__OPEN_SPLIT_RESOURCES__'));
    expect(shellWorker, contains("importScripts('firebase-messaging-sw.js')"));
    expect(
      File('lib/data/push/push_service.dart').readAsStringSync(),
      contains("serviceWorkerScriptPath: kIsWeb ? 'sw.js' : null"),
    );
    expect(messagingWorker, contains('__WEB_FCM_API_KEY__'));
    expect(messagingWorker, contains('__WEB_FCM_APP_ID__'));
    expect(messagingWorker, contains('__FCM_SENDER_ID__'));
    expect(messagingWorker, contains('__FCM_PROJECT_ID__'));
  });

  test('the PWA can adapt to landscape and desktop windows', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(manifest, isNot(contains('orientation')));
    expect(manifest['display'], 'standalone');
  });

  test('hosting enables Wasm isolation and prevents stale workers', () {
    final hosting =
        (jsonDecode(File('firebase.json').readAsStringSync()) as Map)['hosting']
            as Map;
    final headers = hosting['headers'] as List;

    Map headerFor(String source) =>
        headers.cast<Map>().singleWhere((entry) => entry['source'] == source);

    // Scoped to the app rather than the whole origin. Cross-origin isolation
    // is what lets sqlite3.wasm use SharedArrayBuffer, and it is also what
    // stops a page loading anything cross-origin that does not opt in — a
    // needless constraint on a marketing site somebody else designs.
    final app = (headerFor('/app/**')['headers'] as List).cast<Map>();
    expect(app, contains(containsPair('key', 'Cross-Origin-Opener-Policy')));
    expect(app, contains(containsPair('key', 'Cross-Origin-Embedder-Policy')));

    for (final source in [
      '/sw.js',
      '/app/sw.js',
      '/app/firebase-messaging-sw.js',
    ]) {
      final workerHeaders = (headerFor(source)['headers'] as List).cast<Map>();
      expect(
        workerHeaders,
        contains(
          allOf(
            containsPair('key', 'Cache-Control'),
            containsPair('value', 'no-cache, max-age=0'),
          ),
        ),
      );
    }
  });

  test('the worker that used to own the root still has something to fetch', () {
    // Before the split, the offline worker was registered at scope `/`, and a
    // registration outlives the script that made it. Serving nothing here is
    // not neutral: the update fetch 404s, the update fails, and the old worker
    // keeps answering every navigation on the origin out of a cache of the
    // Flutter shell — the landing page and the legal pages included.
    final tombstone = File('site/sw.js');
    expect(
      tombstone.existsSync(),
      isTrue,
      reason:
          'deleting site/sw.js strands every browser that saw the old '
          'layout on a cached copy of it',
    );
    expect(tombstone.readAsStringSync(), contains('registration.unregister()'));
  });

  test('the single-page rewrite cannot swallow the static site', () {
    final hosting =
        (jsonDecode(File('firebase.json').readAsStringSync()) as Map)['hosting']
            as Map;
    final rewrites = (hosting['rewrites'] as List).cast<Map>();

    // The whole reason the app moved under /app/. A catch-all rewrite here
    // answers *everything* with the app shell — which is how the landing page,
    // the privacy policy and /favicon.ico all came back as 200 text/html, and
    // how an OAuth reviewer ended up looking at a sign-in screen.
    for (final rewrite in rewrites) {
      expect(
        rewrite['source'] as String,
        startsWith('/app'),
        reason:
            'a rewrite matching outside /app would serve the app shell in '
            'place of the static pages at the host root',
      );
    }
  });
}
