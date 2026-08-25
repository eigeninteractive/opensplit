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
