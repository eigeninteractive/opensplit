import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

/// The icons `dart run tool/brand_icons.dart` produces.
void main() {
  group('the browser tab icon', () {
    test('is transparent, not a tile', () {
      // flutter_launcher_icons resizes assets/icon/icon.png for the favicon,
      // and that file is deliberately opaque — primaryContainer behind the
      // mark, because iOS and legacy Android icons cannot carry alpha.
      final favicon = decodePng(File('site/favicon.png').readAsBytesSync());
      expect(favicon, isNotNull, reason: 'site/favicon.png is not a PNG');

      expect(
        favicon!.numChannels,
        4,
        reason:
            'site/favicon.png has no alpha channel, so it carries a '
            'background — run `dart run tool/brand_icons.dart`',
      );

      final corner = favicon.getPixel(0, 0);
      expect(
        corner.a,
        0,
        reason:
            'site/favicon.png has an opaque corner, so the mark is sitting '
            'on a tile — run `dart run tool/brand_icons.dart`',
      );
    });
  });

  group('the notification icon', () {
    /// The name the app asks Android for, at runtime, by string.
    late final String declared;

    setUpAll(() {
      final match = RegExp(r"const String statusBarIcon = '@drawable/(\w+)'")
          .firstMatch(
            File('lib/data/push/notification_channel.dart').readAsStringSync(),
          );

      expect(
        match,
        isNotNull,
        reason:
            'notification_channel.dart must name a @drawable notification '
            'icon; a @mipmap launcher icon renders as a white blob',
      );
      declared = match!.group(1)!;
    });

    test('is named in one place, not once per isolate', () {
      // The app and the push background isolate each initialise the plugin, and
      // they run in separate memory with no shared setup.
      for (final path in [
        'lib/data/push/push_service.dart',
        'lib/data/push/background_handler.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('AndroidInitializationSettings(statusBarIcon)'),
          reason: '$path should use the shared statusBarIcon constant',
        );
        expect(
          source,
          isNot(contains("'@drawable/")),
          reason: '$path should not name a drawable directly',
        );
      }
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
      // The whole reason this test exists.
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
