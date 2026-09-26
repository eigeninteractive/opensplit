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

    // Scoped to the app rather than the whole origin.
    expect(rules['/app/*'], contains('Cross-Origin-Opener-Policy'));
    expect(rules['/app/*'], contains('Cross-Origin-Embedder-Policy'));

    expect(rules['/*'], isNot(contains('Cross-Origin-Opener-Policy')));
    expect(rules['/*'], isNot(contains('Cross-Origin-Embedder-Policy')));
    expect(rules['/*'], contains('X-Content-Type-Options'));
  });

  test('the header rules reach the bundle Cloudflare is given', () {
    // Cloudflare parses _headers and never serves it, so losing it produces no
    // 404 and no error: the site simply comes back without cross-origin
    // isolation, and the client's database stops working in a way that reads as
    // a Flutter bug.
    expect(
      File('site/_headers').existsSync(),
      isTrue,
      reason: 'site/_headers is what tool/build_web.dart copies to build/web',
    );
    expect(
      File('tool/build_web.dart').readAsStringSync(),
      contains('_checkServingRules'),
      reason: 'the build must fail rather than ship a bundle missing it',
    );
  });

  test('the deep-link fallback cannot swallow the static site', () {
    final worker = File('server/src/app.ts').readAsStringSync();

    // The whole reason the client moved under /app/.
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
