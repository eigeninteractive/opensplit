import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

/// The link preview, which nobody on this side of the link ever sees.
///
/// Every failure here is silent by construction: a card at the wrong aspect is
/// cropped by the network showing it, a relative `og:image` is dropped
/// entirely, and either way the first thing anyone learns is that the link
/// unfurled badly in somebody else's feed.
void main() {
  late final String landing;

  setUpAll(() {
    landing = File('site/index.html').readAsStringSync();
  });

  String? meta(String property) => RegExp(
    '<meta (?:property|name)="$property" content="([^"]*)">',
  ).firstMatch(landing)?.group(1);

  test('the card is the size Open Graph asks for', () {
    final card = decodePng(File('site/store/og-card.png').readAsBytesSync());

    expect(card, isNotNull, reason: 'site/store/og-card.png is not a PNG');
    // 1200x630 rather than the Play feature graphic's 1024x500. Both are
    // wide, but only one is 1.91:1 — the other gets its edges taken off.
    expect(card!.width, 1200);
    expect(card.height, 630);
  });

  test('the declared dimensions match the file', () {
    final card = decodePng(File('site/store/og-card.png').readAsBytesSync())!;

    // Crawlers lay the card out from these before fetching it. Wrong numbers
    // reserve the wrong box and the preview reflows once the image lands.
    expect(meta('og:image:width'), '${card.width}');
    expect(meta('og:image:height'), '${card.height}');
  });

  test('the card is referenced absolutely', () {
    for (final property in ['og:image', 'twitter:image']) {
      final url = meta(property);
      expect(url, isNotNull, reason: '$property is missing');
      expect(
        url,
        startsWith('https://'),
        reason:
            '$property must be absolute — a relative one is not resolved by '
            'most crawlers, it is simply dropped',
      );
      expect(
        url,
        endsWith('/store/og-card.png'),
        reason: '$property points somewhere other than the generated card',
      );
    }
  });

  test('every page carries a description and a canonical', () {
    for (final page in [
      'site/index.html',
      'site/privacy/index.html',
      'site/terms/index.html',
      'site/delete-account/index.html',
    ]) {
      final html = File(page).readAsStringSync();
      expect(
        html,
        contains('<meta name="description"'),
        reason: '$page has no description for a result snippet to use',
      );
      expect(
        html,
        contains('rel="canonical"'),
        reason:
            '$page has no canonical, and every one of these is reachable '
            'with and without a trailing slash',
      );
    }
  });

  test('crawlers are kept out of the single-page app', () {
    // /app/** all resolves to one shell with a 200, so without this a crawler
    // can mint unbounded URLs that are the same document — each one competing
    // with the landing page under the same title.
    expect(
      File('site/robots.txt').readAsStringSync(),
      contains('Disallow: /app'),
    );
  });

  test('the sitemap lists exactly the pages that exist', () {
    final sitemap = File('site/sitemap.xml').readAsStringSync();
    final listed = RegExp(
      r'<loc>https://opensplit\.web\.app/([^<]*)</loc>',
    ).allMatches(sitemap).map((match) => match.group(1)!).toSet();

    expect(listed, {'', 'privacy', 'terms', 'delete-account'});
    for (final page in listed.where((page) => page.isNotEmpty)) {
      expect(
        File('site/$page/index.html').existsSync(),
        isTrue,
        reason: 'the sitemap advertises /$page, which is not a file',
      );
    }
  });
}
