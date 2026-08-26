import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/config.dart';

/// The one host this app claims.
///
/// Two files have to agree about it and neither reads the other: `config.dart`
/// decides the host every invite link is *minted* with, and the App Links
/// intent filter decides which hosts Android will *open* natively. If the
/// filter loses the host links are made with, every link opens in a browser
/// instead of the app — silently, on other people's phones, long after the
/// change that caused it.
void main() {
  group('legal pages', _legalPages);
  late final String manifest;

  setUpAll(() {
    manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
  });

  test('is opensplit.web.app', () {
    // Stated outright rather than derived, because this is the commitment
    // itself: the domain is part of the product's contract with links that
    // already exist, not a configuration detail.
    expect(linkHost, 'opensplit.web.app');
  });

  test('is the only host Android claims', () {
    final hosts = RegExp(
      r'android:host="([^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)).toList();

    // More than one is not a bug in itself — it is a promise to serve
    // assetlinks.json from each of them, matching the signing key, for as long
    // as any link naming them survives. One is the decision this project made.
    expect(
      hosts,
      [linkHost],
      reason:
          'the App Links filter must claim exactly linkHost, and nothing '
          'else — see the domain section in README.md',
    );
  });

  test('is verified rather than merely listed', () {
    // Without autoVerify Android never fetches assetlinks.json, and the filter
    // makes the app one option in a chooser rather than the handler.
    expect(manifest, contains('android:autoVerify="true"'));
  });
}

/// The pages the store listing points at, and the app links out to.
///
/// Three things have to agree and none of them reads the others: the URL
/// submitted to Play Console, the getter the Settings screen launches, and a
/// file that actually exists in `web/`. A rename breaks the middle one
/// silently — the link opens, the SPA's catch-all rewrite serves the app
/// shell, and a Play reviewer sees a loading spinner where a privacy policy
/// should be.
void _legalPages() {
  for (final (name, url) in [
    ('privacy', privacyPolicyUrl),
    ('terms', termsUrl),
    ('delete-account', deleteAccountUrl),
  ]) {
    test('$name is served from the link host', () {
      expect(url, 'https://$linkHost/$name');
    });

    test('$name is a real file, not a route', () {
      expect(
        File('web/$name/index.html').existsSync(),
        isTrue,
        reason:
            'web/$name/index.html must exist: flutter build web copies web/ '
            'verbatim, and Firebase Hosting serves a real file before it '
            'applies the single-page-app rewrite',
      );
    });
  }

  test(
    'none of them is still carrying a placeholder',
    () {
      // These pages ship with an address and a jurisdiction nobody has filled
      // in yet, marked with a red box on the page itself. Publishing one in that
      // state gives Play a policy that tells people to write to nobody.
      for (final name in ['privacy', 'terms', 'delete-account']) {
        final page = File('web/$name/index.html').readAsStringSync();
        expect(
          page,
          isNot(contains('[contact email]')),
          reason: 'web/$name/index.html still has an unfilled contact address',
        );
        expect(
          page,
          isNot(contains('[jurisdiction]')),
          reason: 'web/$name/index.html still has an unfilled jurisdiction',
        );
      }
    },
    skip:
        'Fill in the contact address and jurisdiction, then remove this '
        'skip — it is what stops the placeholders reaching Play.',
  );
}
