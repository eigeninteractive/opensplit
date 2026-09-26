import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/config.dart';
import 'package:opensplit/data/sync/invites.dart';

/// The one host this app claims.
void main() {
  group('legal pages', _legalPages);
  late final String manifest;

  setUpAll(() {
    manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
  });

  test('is opensplit.eigeninteractive.com', () {
    // Stated outright rather than derived, because this is the commitment
    // itself: the domain is part of the product's contract with links that
    // already exist, not a configuration detail.
    expect(linkHost, 'opensplit.eigeninteractive.com');
  });

  test('is the only host Android claims', () {
    final hosts = RegExp(
      r'android:host="([^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)).toList();

    // More than one is not a bug in itself — it is a promise to serve
    // assetlinks.json from each of them, matching the signing key, for as long
    // as any link naming them survives.
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

  test('authorizes every Play and direct-install signing certificate', () {
    final statements =
        jsonDecode(File('site/.well-known/assetlinks.json').readAsStringSync())
            as List<dynamic>;
    final statement = statements.single as Map<String, dynamic>;
    final target = statement['target'] as Map<String, dynamic>;
    final fingerprints = (target['sha256_cert_fingerprints'] as List<dynamic>)
        .cast<String>()
        .toSet();

    expect(fingerprints, {
      '1D:38:70:BC:61:03:AD:AF:78:4D:1B:41:33:0B:12:83:AF:40:79:F7:'
          '30:2B:17:26:C7:CE:C7:E1:27:1D:C3:96',
      '5A:A5:05:44:DE:AF:3A:77:BC:90:D6:BD:8C:D3:B4:68:AE:24:15:55:'
          '5C:54:55:C6:87:F0:7B:C7:0A:A9:C5:07',
      'A8:B5:00:09:DC:F4:62:FA:8E:7A:FA:33:87:EA:10:5D:66:BC:DF:84:'
          'A2:AE:FB:DD:5F:82:A7:99:08:40:B1:81',
      '10:CC:C9:6C:62:9A:87:E5:19:6F:B5:71:8D:7B:84:CC:DC:E6:DD:C4:'
          'B6:A1:EA:EC:71:8A:C8:AC:82:27:61:32',
    });
  });

  test('claims the path invite links are actually minted under', () {
    // The host is no longer all app: the root is static marketing pages and the
    // client is served from /app/.
    final prefixes = RegExp(
      r'android:pathPrefix="([^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)!).toList();

    final invite = joinUrl(linkHost, 'tok');

    expect(prefixes, hasLength(1), reason: 'one prefix, matching one split');
    expect(
      Uri.parse(invite).path,
      startsWith(prefixes.single),
      reason:
          'invite links are minted at \$invite, which the App Links filter '
          'does not claim — Android would hand them to a browser',
    );
  });

  test('does not claim the pages that must open in a browser', () {
    final prefix = RegExp(
      r'android:pathPrefix="([^"]+)"',
    ).firstMatch(manifest)!.group(1)!;

    // The other half of the same decision.
    for (final url in [privacyPolicyUrl, termsUrl, deleteAccountUrl]) {
      expect(
        Uri.parse(url).path,
        isNot(startsWith(prefix)),
        reason: '\$url would be swallowed by the App Links filter',
      );
    }
  });
}

/// The pages the store listing points at, and the app links out to.
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
        File('site/$name.html').existsSync(),
        isTrue,
        reason:
            'site/$name.html must exist: tool/build_web.dart copies site/ to '
            'the host root, where the /app deep-link fallback cannot reach it',
      );
    });

    test('$name answers at its own address, without a redirect', () {
      // A page kept as `<name>/index.html` is answered with a 307 to `<name>/`
      // by Cloudflare's asset router, and this URL is the one in the Play
      // Console listing and in the canonical tag.
      expect(
        Directory('site/$name').existsSync(),
        isFalse,
        reason: 'site/$name/ would make $url redirect rather than serve',
      );
    });
  }

  test('none of them is carrying a placeholder', () {
    // They shipped with an address and a jurisdiction nobody had filled in, and
    // a page in that state reads perfectly well — it simply tells people to
    // write to nobody, which is not something a reviewer or a user would notice
    // on our behalf.
    for (final name in ['privacy', 'terms', 'delete-account']) {
      final page = File('site/$name.html').readAsStringSync();
      expect(
        page,
        isNot(contains('[contact email]')),
        reason: 'site/$name.html still has an unfilled contact address',
      );
      expect(
        page,
        isNot(contains('[jurisdiction]')),
        reason: 'site/$name.html still has an unfilled jurisdiction',
      );
      expect(
        page,
        contains('hello@eigeninteractive.com'),
        reason:
            'site/$name.html has no contact address, which Play requires a '
            'privacy policy to carry',
      );
    }
  });
}
