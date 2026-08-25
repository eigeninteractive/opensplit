import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/presentation/theme.dart';

/// Relative luminance, per WCAG 2.1.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('balance colours', () {
    // The bug this guards: a single hardcoded light-mode green was used in both
    // themes, landing around 3.4:1 on a dark surface — below AA — on the one
    // number the whole app exists to show.
    for (final brightness in Brightness.values) {
      test('credit is readable in $brightness', () {
        final theme = buildTheme(brightness);
        final colors = theme.extension<BalanceColors>()!;
        expect(
          _contrast(colors.credit, theme.colorScheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'credit on surface must meet WCAG AA for text',
        );
      });

      test('debit is readable in $brightness', () {
        final theme = buildTheme(brightness);
        final colors = theme.extension<BalanceColors>()!;
        expect(
          _contrast(colors.debit, theme.colorScheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      });

      // Deliberately NOT asserted: that credit and debit differ in luminance.
      // Green and red are close to identical there, which is exactly why
      // roughly one man in twelve cannot tell them apart — and why every
      // balance in this app is worded ("you owe", "is owed", and the
      // semanticsLabel on the signed figures) rather than relying on hue.
      // A test demanding luminance separation would push the design towards
      // treating colour as sufficient, which it is not.
    }

    test('light and dark do not share a credit colour', () {
      expect(
        buildTheme(Brightness.light).extension<BalanceColors>()!.credit,
        isNot(buildTheme(Brightness.dark).extension<BalanceColors>()!.credit),
      );
    });

    test('a zero balance is neither credit nor debit', () {
      final scheme = buildTheme(Brightness.light).colorScheme;
      expect(balanceColor(scheme, 0), scheme.onSurfaceVariant);
    });

    test('the extension survives a wallpaper-derived scheme', () {
      // Material You replaces every other colour; credit still has to read as
      // credit.
      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFFB00020),
        brightness: Brightness.dark,
      );
      final theme = buildTheme(Brightness.dark, dynamicScheme);
      final colors = theme.extension<BalanceColors>()!;
      expect(
        _contrast(colors.credit, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('the web loading skeleton', () {
    test('uses the theme\'s own colours', _skeletonMatchesTheme);

    testWidgets('uses the theme\'s own type', (tester) async {
      late TextTheme resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          // Text geometry is applied by Theme.of, not by the ThemeData
          // constructor, so the real sizes only exist inside a MaterialApp.
          home: Builder(
            builder: (context) {
              resolved = Theme.of(context).textTheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final css = File('web/index.html').readAsStringSync();

      // The app bar title. A skeleton whose title is a different size or
      // weight than the real one visibly jumps at the swap, which is the whole
      // thing this skeleton exists to prevent.
      final title = resolved.titleLarge!;
      expect(css, contains('font-size: ${title.fontSize!.round()}px'));
      expect(css, contains('font-weight: ${title.fontWeight!.value}'));

      // The extended FAB's label.
      final label = resolved.labelLarge!;
      expect(css, contains('font-size: ${label.fontSize!.round()}px'));
      expect(css, contains('font-weight: ${label.fontWeight!.value}'));
    });

    test('agrees with the app on the boot-hint key', () {
      // The loader decides whether to draw group cards by reading a key the
      // Dart side writes. They are in different languages, in different files,
      // and nothing connects them but this string — so a rename on either side
      // silently returns the loader to guessing.
      final key = RegExp(
        r"localStorage\.getItem\('([^']+)'\)",
      ).firstMatch(File('web/index.html').readAsStringSync())?.group(1);

      expect(key, isNotNull, reason: 'the loader reads no boot hint at all');
      expect(
        File('lib/data/web/boot_hint_web.dart').readAsStringSync(),
        contains("'$key'"),
        reason: 'boot_hint_web.dart must write the key index.html reads',
      );
    });

    test('paints its launch background in the theme\'s surface', () {
      final surface = buildTheme(Brightness.light).colorScheme.surface;
      final manifest =
          jsonDecode(File('web/manifest.json').readAsStringSync())
              as Map<String, dynamic>;

      // What the browser paints before a single byte of the app has parsed.
      expect(manifest['background_color'], _hex(surface));
      expect(manifest['theme_color'], _hex(surface));
    });
  });

  // The same problem the web skeleton has, on the other platform: Android
  // paints the window before a line of Dart runs — and on 12 and up paints a
  // system splash screen over it — from colours it can only read out of
  // resources and generator configs.
  //
  // Most of these files are written by `dart run flutter_native_splash:create`
  // and `dart run flutter_launcher_icons`, which is exactly why they are worth
  // testing: regenerating them silently reverts anything corrected by hand, and
  // the result is a flash on a cold start that no test would otherwise catch.
  group('the Android launch window', () {
    String res(String path) =>
        File('android/app/src/main/res/$path').readAsStringSync();

    /// The body of one `<style name="...">` block.
    String styleBlock(String variant, String theme) {
      final styles = res('$variant/styles.xml');
      final at = styles.indexOf('name="$theme"');
      expect(at, isNot(-1), reason: 'no $theme in $variant/styles.xml');
      return styles.substring(at, styles.indexOf('</style>', at));
    }

    for (final brightness in Brightness.values) {
      final night = brightness == Brightness.dark;
      final variant = night ? 'values-night' : 'values';
      final surface = _hex(buildTheme(brightness).colorScheme.surface);

      test('declares the theme\'s surface in $brightness', () {
        final declared = RegExp(
          r'<color name="surface">(#[0-9a-fA-F]{6})</color>',
        ).firstMatch(res('$variant/colors.xml'));

        expect(declared, isNotNull, reason: 'no surface in $variant/colors.xml');
        expect(
          declared!.group(1)!.toLowerCase(),
          surface,
          reason: '$variant/colors.xml must hold ColorScheme.surface',
        );
      });

      // NormalTheme is the window behind the running Flutter UI, visible during
      // a rotation or a resize. flutter_native_splash writes v31 copies of both
      // themes and leaves ?android:colorBackground — the platform's white — in
      // this one, which shadows the corrected value on Android 12 and up. That
      // is the whole reason this loop covers the v31 variants too.
      for (final suffix in ['', '-v31']) {
        test('paints NormalTheme in the surface ($variant$suffix)', () {
          expect(
            styleBlock('$variant$suffix', 'NormalTheme'),
            contains('android:windowBackground">@color/surface'),
            reason:
                '$variant$suffix/NormalTheme must use @color/surface, not the '
                "platform's own window background",
          );
        });
      }

      test('splashes on the surface in $brightness', () {
        // Android 12+ draws the system splash from this attribute rather than
        // from windowBackground, and it cannot be opted out of.
        final declared = RegExp(
          r'windowSplashScreenBackground">(#[0-9a-fA-F]{6})<',
        ).firstMatch(res('$variant-v31/styles.xml'));

        expect(declared, isNotNull, reason: 'no splash colour for $brightness');
        expect(declared!.group(1)!.toLowerCase(), surface);
      });

      test('launches on the generated splash below Android 12', () {
        expect(
          styleBlock(variant, 'LaunchTheme'),
          contains('android:windowBackground">@drawable/launch_background'),
          reason:
              '$variant/LaunchTheme must use the drawable '
              'flutter_native_splash generates',
        );
      });
    }

    test('is what flutter_native_splash would regenerate', () {
      // The resources above are outputs. This is the input they come from, so
      // pinning only the outputs would let the next regeneration undo them.
      final config = File('flutter_native_splash.yaml').readAsStringSync();

      for (final (key, brightness) in [
        ('color', Brightness.light),
        ('color_dark', Brightness.dark),
      ]) {
        final declared = RegExp(
          '$key: "(#[0-9a-fA-F]{6})"',
        ).firstMatch(config);

        expect(declared, isNotNull, reason: 'no $key in the splash config');
        expect(
          declared!.group(1)!.toLowerCase(),
          _hex(buildTheme(brightness).colorScheme.surface),
          reason: 'flutter_native_splash $key must be the theme\'s surface',
        );
      }
    });

    test('gives the launcher icon the theme\'s container colour', () {
      // The adaptive icon's background layer, which flutter_launcher_icons
      // copies from its own config into colors.xml. Both are checked, because
      // they are two files that have to agree and neither reads the other.
      final light = buildTheme(Brightness.light).colorScheme;

      final declared = RegExp(
        r'<color name="ic_launcher_background">(#[0-9a-fA-F]{6})</color>',
      ).firstMatch(res('values/colors.xml'));
      expect(declared, isNotNull, reason: 'no ic_launcher_background declared');
      expect(declared!.group(1)!.toLowerCase(), _hex(light.primaryContainer));

      final configured = RegExp(
        r'adaptive_icon_background: "(#[0-9a-fA-F]{6})"',
      ).firstMatch(File('flutter_launcher_icons.yaml').readAsStringSync());
      expect(configured, isNotNull, reason: 'no adaptive_icon_background set');
      expect(configured!.group(1)!.toLowerCase(), _hex(light.primaryContainer));
    });
  });
}

/// The colours the loading skeleton in `web/index.html` claims to be using.
///
/// It has to paint before any Dart runs, so it cannot ask the theme what its
/// own colours are — it writes them out as literals. That is fine right up
/// until someone changes the seed, at which point the first thing anyone sees
/// is a skeleton in the old palette dissolving into an app in the new one, and
/// nothing anywhere fails.
///
/// So each literal is named after the role it stands for, and this reads them
/// back out and holds them against the running theme.
Map<String, String> _declaredColors(String css, int from) {
  final open = css.indexOf(':root {', from);
  expect(open, isNot(-1), reason: 'no :root block after offset $from');
  final body = css.substring(open, css.indexOf('}', open));

  return {
    for (final match in RegExp(
      r'--([a-z-]+):\s*(#[0-9a-fA-F]{6})',
    ).allMatches(body))
      match.group(1)!: match.group(2)!.toLowerCase(),
  };
}

String _hex(Color c) {
  String channel(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(c.r)}${channel(c.g)}${channel(c.b)}';
}

void _skeletonMatchesTheme() {
  final css = File('web/index.html').readAsStringSync();

  final darkBlock = css.indexOf('@media (prefers-color-scheme: dark)');
  expect(darkBlock, isNot(-1), reason: 'no dark palette in web/index.html');

  final declaredFor = {
    Brightness.light: _declaredColors(css, 0),
    Brightness.dark: _declaredColors(css, darkBlock),
  };

  for (final entry in declaredFor.entries) {
    final scheme = buildTheme(entry.key).colorScheme;
    final declared = entry.value;

    final expected = <String, Color>{
      'surface': scheme.surface,
      'placeholder': scheme.surfaceContainerHighest,
      'outline-variant': scheme.outlineVariant,
      'on-surface': scheme.onSurface,
      'secondary-container': scheme.secondaryContainer,
      'primary-container': scheme.primaryContainer,
      'on-primary-container': scheme.onPrimaryContainer,
    };

    expect(
      declared.keys.toSet(),
      expected.keys.toSet(),
      reason:
          'the ${entry.key} skeleton palette and this test disagree about '
          'which roles it uses',
    );

    for (final role in expected.entries) {
      expect(
        declared[role.key],
        _hex(role.value),
        reason:
            'web/index.html --${role.key} (${entry.key}) must be the theme\'s '
            'own value for that role',
      );
    }
  }
}
