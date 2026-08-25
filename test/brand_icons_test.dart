import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

/// The icons `dart run tool/brand_icons.dart` produces.
///
/// They exist because flutter_launcher_icons builds every output from one
/// opaque master, which is right for a launcher icon and wrong for both of
/// these. That also means running the generator overwrites one of them, so
/// these tests are the thing standing between a routine `dart run
/// flutter_launcher_icons` and a silently wrong icon.
void main() {
  group('the browser tab icon', () {
    test('is transparent, not a tile', () {
      // flutter_launcher_icons resizes assets/icon/icon.png for the favicon,
      // and that file is deliberately opaque — primaryContainer behind the
      // mark, because iOS and legacy Android icons cannot carry alpha. Resized
      // into a tab it becomes a pale lilac square, brightest thing on the row
      // in a dark theme.
      final favicon = decodePng(File('web/favicon.png').readAsBytesSync());
      expect(favicon, isNotNull, reason: 'web/favicon.png is not a PNG');

      expect(
        favicon!.numChannels,
        4,
        reason:
            'web/favicon.png has no alpha channel, so it carries a '
            'background — run `dart run tool/brand_icons.dart`',
      );

      final corner = favicon.getPixel(0, 0);
      expect(
        corner.a,
        0,
        reason:
            'web/favicon.png has an opaque corner, so the mark is sitting '
            'on a tile — run `dart run tool/brand_icons.dart`',
      );
    });
  });

  group('the notification icon', () {
    /// The name push_service.dart asks Android for, at runtime, by string.
    late final String declared;

    setUpAll(() {
      final match = RegExp(
        r"AndroidInitializationSettings\('@drawable/(\w+)'\)",
      ).firstMatch(File('lib/data/push/push_service.dart').readAsStringSync());

      expect(
        match,
        isNotNull,
        reason:
            'push_service.dart must name a @drawable notification icon; a '
            '@mipmap launcher icon renders as a white blob',
      );
      declared = match!.group(1)!;
    });

    test('exists at every density Android resolves between', () {
      // A missing bucket is not a build error. Android falls back to another
      // density and scales, so the only symptom is a soft icon on some phones.
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final path = 'android/app/src/main/res/drawable-$density/$declared.png';
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path is missing — run `dart run tool/brand_icons.dart`',
        );
      }
    });

    test('survives resource shrinking', () {
      // The whole reason this test exists. Release builds run R8 with resource
      // shrinking on — the Flutter Gradle plugin enables both — and the icon is
      // referenced only as a string, so nothing in the compiled code points at
      // it. Before the keep rule the shrinker reported the old
      // @mipmap/ic_launcher as "not reachable", which in release means Android
      // looks the resource up, fails to find it, and posts nothing at all. No
      // error, no crash, and nothing reproducible on a debug build.
      final keep = File(
        'android/app/src/main/res/raw/keep.xml',
      ).readAsStringSync();

      expect(
        keep,
        contains('@drawable/$declared'),
        reason:
            'keep.xml must keep the drawable push_service.dart names, or '
            'the release build drops it and notifications stop appearing',
      );
    });

    test('is a silhouette, which is all Android draws', () {
      // Android reads the alpha channel and paints its own colour through it.
      // A fully opaque image is a filled rectangle in the status bar.
      final icon = decodePng(
        File(
          'android/app/src/main/res/drawable-xxxhdpi/$declared.png',
        ).readAsBytesSync(),
      );
      expect(icon, isNotNull);
      expect(icon!.numChannels, 4, reason: 'no alpha channel to draw through');
      expect(icon.getPixel(0, 0).a, 0, reason: 'the corner is not transparent');
    });
  });
}
