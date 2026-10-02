import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the one service worker is built, never copied from web/', () {
    // Flutter copies web/ into the bundle verbatim, so a worker there would
    // ship unbuilt wherever the Workbox step did not run after it.
    expect(File('web/sw.js').existsSync(), isFalse);
    expect(File('service_worker/src/sw.ts').existsSync(), isTrue);
    expect(
      File('tool/build_web.dart').readAsStringSync(),
      contains('_buildServiceWorker'),
    );
    // Push registers the same script, so it never installs a second worker
    // that would replace the offline one at the /app/ scope.
    expect(
      File('lib/data/push/push_service.dart').readAsStringSync(),
      contains("serviceWorkerScriptPath: kIsWeb ? 'sw.js' : null"),
    );
    expect(
      File('web/flutter_bootstrap.js').readAsStringSync(),
      contains("navigator.serviceWorker.register('sw.js')"),
    );
  });

  test('the worker bundles the Firebase SDK the page loads', () {
    // The page's SDK comes from FlutterFire, which loads the version
    // firebase_core_web names from Google's CDN; the worker's is bundled from
    // npm. Nothing else ties the two, so a `pub upgrade` would leave them apart.
    final packages =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final coreWeb = (packages['packages'] as List).cast<Map>().firstWhere(
      (package) => package['name'] == 'firebase_core_web',
    );
    final source = File.fromUri(
      Uri.parse(
        '${coreWeb['rootUri']}/lib/src/firebase_sdk_version.dart',
      ).normalizePath(),
    ).readAsStringSync();
    final page = RegExp(
      r"supportedFirebaseJsSdkVersion = '([^']+)'",
    ).firstMatch(source)?.group(1);

    final manifest =
        jsonDecode(File('service_worker/package.json').readAsStringSync())
            as Map<String, dynamic>;
    final worker = (manifest['devDependencies'] as Map)['firebase'];

    expect(page, isNotNull, reason: 'firebase_core_web moved its version');
    expect(
      worker,
      page,
      reason:
          'pin firebase in service_worker/package.json to $page: '
          'pnpm --dir service_worker add -D firebase@$page',
    );
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

  test('no page can be framed by another site', () {
    final rules = _headerRules();
    final text = File('site/_headers').readAsStringSync();

    expect(rules['/*'], contains('Content-Security-Policy'));
    expect(rules['/*'], contains('X-Frame-Options'));
    expect(text, contains("Content-Security-Policy: frame-ancestors 'none'"));
    expect(text, contains('X-Frame-Options: DENY'));
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
