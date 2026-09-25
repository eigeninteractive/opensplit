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

  test('serving enables Wasm isolation, and only for the client', () {
    final rules = _headerRules();

    // Scoped to the app rather than the whole origin. Cross-origin isolation
    // is what lets sqlite3.wasm use SharedArrayBuffer, and it is also what
    // stops a page loading anything cross-origin that does not opt in — a
    // needless constraint on a marketing site somebody else designs, whose
    // pages embed Google Fonts.
    //
    // The pair is safe here only because no sign-in depends on a popup any
    // more: the web hands the whole page to Google and comes back. Reinstating
    // an in-page Google button without removing these would break sign-in
    // silently, in release builds only.
    expect(rules['/app/*'], contains('Cross-Origin-Opener-Policy'));
    expect(rules['/app/*'], contains('Cross-Origin-Embedder-Policy'));

    expect(rules['/*'], isNot(contains('Cross-Origin-Opener-Policy')));
    expect(rules['/*'], isNot(contains('Cross-Origin-Embedder-Policy')));
    expect(rules['/*'], contains('X-Content-Type-Options'));
  });

  test('the serving rules reach the bundle Cloudflare is given', () {
    // Both files are parsed by Cloudflare and never served, so losing one
    // produces no 404 and no error: the site simply comes back without
    // cross-origin isolation, and the client's database stops working in a way
    // that reads as a Flutter bug. They have to be at the root of the assets
    // directory, which is build/web, and they get there by being in site/.
    for (final name in ['_headers', '_redirects']) {
      expect(
        File('site/$name').existsSync(),
        isTrue,
        reason: 'site/$name is what tool/build_web.dart copies to build/web',
      );
    }
    expect(
      File('tool/build_web.dart').readAsStringSync(),
      contains('_checkServingRules'),
      reason: 'the build must fail rather than ship a bundle missing them',
    );
  });

  test('the client routes resolve at the host root too', () {
    // The /app/ split is ours, not the user's. Somebody who types or bookmarks
    // the route the app shows them should land on it rather than a 404, and an
    // invite path is the one where that matters most.
    final redirects = File('site/_redirects')
        .readAsLinesSync()
        .where((line) => line.startsWith('/'))
        .map((line) => line.split(RegExp(r'\s+')))
        .toList();

    for (final route in ['/g/*', '/join/*', '/welcome', '/archived']) {
      final rule = redirects.singleWhere(
        (parts) => parts.first == route,
        orElse: () => fail('$route no longer redirects anywhere'),
      );
      expect(rule[1], startsWith('/app'));
      expect(rule[2], '301', reason: 'the split is not a temporary state');
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

  test('the deep-link fallback cannot swallow the static site', () {
    final worker = File('server/src/app.ts').readAsStringSync();

    // The whole reason the client moved under /app/. A catch-all fallback
    // answers *everything* with the app shell — which is how the landing page,
    // the privacy policy and /favicon.ico all came back as 200 text/html, and
    // how an OAuth reviewer ended up looking at a sign-in screen.
    //
    // Asserted against the Worker rather than a config file because that is
    // where the rule now lives: none of the platform's own not_found_handling
    // settings answers the right document, so src/app.ts decides by hand.
    expect(
      worker,
      contains(
        "url.pathname === \"/app\" || url.pathname.startsWith(\"/app/\")",
      ),
      reason:
          'the fallback must be scoped to /app; widening it serves the app '
          'shell in place of the static pages at the host root',
    );

    // And the setting that would widen it behind the Worker's back.
    final config = File('server/wrangler.jsonc').readAsStringSync();
    expect(
      config,
      isNot(contains('"not_found_handling"')),
      reason:
          'single-page-application would answer /app/join/xyz with the '
          'landing page, and 404-page would answer it with /404.html',
    );
  });
}

/// The header names `_headers` sets, by the path pattern they are set on.
///
/// Parsed rather than asserted as text so the test says what the rules mean,
/// and so reordering or recommenting the file does not fail it.
Map<String, Set<String>> _headerRules() {
  final rules = <String, Set<String>>{};
  var pattern = '';
  for (final line in File('site/_headers').readAsLinesSync()) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(RegExp(r'\s'))) {
      pattern = line.trim();
      rules[pattern] = <String>{};
    } else {
      rules[pattern]!.add(line.split(':').first.trim());
    }
  }
  return rules;
}
