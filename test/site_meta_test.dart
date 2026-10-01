import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

/// What the static site says about itself to crawlers, link previews and
/// Play: the parts nobody on this side of the link ever sees.
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

  test('the Play feature graphic is the size and format Play takes', () {
    final file = File('site/store/feature-graphic.jpg');
    final graphic = decodeJpg(file.readAsBytesSync());

    // JPEG, because Play refuses a PNG with an alpha channel even when every
    // pixel of it is opaque, and a regenerated PNG is one save away from one.
    expect(graphic, isNotNull, reason: '${file.path} is not a JPEG');
    expect(graphic!.width, 1024);
    expect(graphic.height, 500);
  });

  test('the store screenshots are the size Play asks for', () {
    final shots = Directory('site/store')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('/screenshot-'))
        .toList();

    expect(shots, isNotEmpty);
    for (final shot in shots) {
      final image = decodePng(shot.readAsBytesSync());
      expect(image, isNotNull, reason: '${shot.path} is not a PNG');
      expect(
        (image!.width, image.height),
        (1080, 1920),
        reason: '${shot.path} is not a 9:16 phone screenshot',
      );
    }
  });

  test('every font the site asks for is one the build copies', () {
    // site.css names /fonts/<file>; tool/build_web.dart fills /fonts from
    // assets/google_fonts. A face renamed on one side only falls back to the
    // system font without an error anywhere.
    final css = File('site/site.css').readAsStringSync();
    final requested = RegExp(
      r'url\("/fonts/([^"]+)"\)',
    ).allMatches(css).map((match) => match.group(1)!);

    expect(requested, isNotEmpty);
    for (final name in requested) {
      expect(
        File('assets/google_fonts/$name').existsSync(),
        isTrue,
        reason: 'site.css asks for /fonts/$name, which is not bundled',
      );
    }
  });

  test('no page fetches anything from a third party', () {
    // The landing page says nothing is watching what you do. A font, script
    // or stylesheet from another origin would make that untrue on the page
    // making the claim.
    for (final page in Directory('site').listSync().whereType<File>().where(
      (file) => file.path.endsWith('.html'),
    )) {
      final html = page.readAsStringSync();
      // A canonical is an absolute URL by design and fetches nothing, so only
      // the tags a browser actually loads are looked at.
      final fetched = [
        for (final tag in RegExp(r'<link [^>]*>').allMatches(html))
          if (!tag.group(0)!.contains('rel="canonical"')) tag.group(0)!,
        for (final tag in RegExp(r'<(?:script|img) [^>]*>').allMatches(html))
          tag.group(0)!,
      ];
      for (final tag in fetched) {
        expect(
          tag,
          isNot(matches(RegExp(r'(?:href|src)="(?:https?:)?//'))),
          reason: '${page.path} loads a resource from another origin',
        );
      }
    }
  });

  test('the FAQ that search engines read is the one people read', () {
    // The questions are written twice, once as <details> and once as JSON-LD
    // for rich results. Malformed JSON is dropped by crawlers without a word,
    // and a question in only one of the two is an answer the other cannot see.
    final structured = [
      for (final match in RegExp(
        r'<script type="application/ld\+json">(.*?)</script>',
        dotAll: true,
      ).allMatches(landing))
        jsonDecode(match.group(1)!) as Map<String, dynamic>,
    ];
    final faq = structured.singleWhere((data) => data['@type'] == 'FAQPage');
    final questions = [
      for (final entry in faq['mainEntity'] as List)
        (entry as Map<String, dynamic>)['name'],
    ];

    expect(
      questions,
      RegExp(
        '<summary>([^<]*)</summary>',
      ).allMatches(landing).map((match) => match.group(1)).toList(),
    );
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
      'site/privacy.html',
      'site/terms.html',
      'site/delete-account.html',
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

  test('crawlers are kept out of the single-page app, and can read why', () {
    // /app/** all resolves to one shell with a 200, so without this a crawler
    // can mint unbounded URLs that are the same document — each one competing
    // with the landing page under the same title.
    final shell = File('web/index.html').readAsStringSync();
    expect(
      shell,
      contains('<meta name="robots" content="noindex">'),
      reason: 'the app shell must exclude itself from the index',
    );

    // And the exclusion has to be reachable.
    expect(
      File('site/robots.txt').readAsStringSync(),
      isNot(contains(RegExp(r'^Disallow: /app', multiLine: true))),
      reason: 'a blocked page cannot be told not to index itself',
    );
  });

  test('the app shell unfurls as the same product as the landing page', () {
    final shell = File('web/index.html').readAsStringSync();
    final landing = File('site/index.html').readAsStringSync();

    for (final property in ['og:image', 'og:title', 'og:description']) {
      final pattern = RegExp('property="$property" content="([^"]+)"');
      expect(
        pattern.firstMatch(shell)?.group(1),
        pattern.firstMatch(landing)?.group(1),
        reason: 'the two pages disagree about $property',
      );
    }
    expect(
      shell,
      contains('name="twitter:card" content="summary_large_image"'),
    );
  });

  test('the tab title does not rewrite itself once Flutter boots', () {
    // MaterialApp.onGenerateTitle sets document.title from this string, so a
    // shell that says anything else is a title the user watches change.
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync());
    final title = (arb as Map<String, dynamic>)['appTitle'] as String;

    expect(
      RegExp(
        r'<title>([^<]*)</title>',
      ).firstMatch(File('web/index.html').readAsStringSync())?.group(1),
      title,
      reason: 'web/index.html must open with the title Flutter will set',
    );
  });

  test('the sitemap lists exactly the pages that exist', () {
    final sitemap = File('site/sitemap.xml').readAsStringSync();
    final listed = RegExp(
      r'<loc>https://opensplit\.eigeninteractive\.com/([^<]*)</loc>',
    ).allMatches(sitemap).map((match) => match.group(1)!).toSet();

    expect(listed, {'', 'privacy', 'terms', 'delete-account'});
    for (final page in listed.where((page) => page.isNotEmpty)) {
      // A file and not a directory, because `<name>/index.html` is answered
      // with a redirect to `<name>/` — and a sitemap that advertises a URL
      // which redirects is a sitemap arguing with its own canonical tags.
      expect(
        File('site/$page.html').existsSync(),
        isTrue,
        reason: 'the sitemap advertises /$page, which is not a file',
      );
    }
  });
}
