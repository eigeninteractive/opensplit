import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
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

  group('the web splash', () {
    test('uses the theme\'s own colours', _splashMatchesTheme);

    test('paints its launch background in the theme\'s surface', () {
      final surface = buildTheme(Brightness.light).colorScheme.surface;
      final manifest =
          jsonDecode(File('web/manifest.json').readAsStringSync())
              as Map<String, dynamic>;

      // What the browser paints before a single byte of the app has parsed.
      for (final key in ['background_color', 'theme_color']) {
        expect(
          (manifest[key] as String).toLowerCase(),
          _hex(surface),
          reason: 'web/manifest.json $key must be ColorScheme.surface',
        );
      }

      // The generator's own copy of the same two values, so that regenerating
      // cannot quietly put the brand's primary back into the browser chrome.
      final config = File('flutter_launcher_icons.yaml').readAsStringSync();
      for (final key in ['background_color', 'theme_color']) {
        final declared = RegExp('$key: "(#[0-9a-fA-F]{6})"').firstMatch(config);
        expect(declared, isNotNull, reason: 'no web $key in the icon config');
        expect(declared!.group(1)!.toLowerCase(), _hex(surface));
      }
    });
  });

  // The same problem the web splash has, on the other platform: Android
  // paints the window before a line of Dart runs — and on 12 and up paints a
  // system splash screen over it — from colours it can only read out of
  // resources and generator configs.
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

        expect(
          declared,
          isNotNull,
          reason: 'no surface in $variant/colors.xml',
        );
        expect(
          declared!.group(1)!.toLowerCase(),
          surface,
          reason: '$variant/colors.xml must hold ColorScheme.surface',
        );
      });

      // NormalTheme is the window behind the running Flutter UI, visible during
      // a rotation or a resize.
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
        final declared = RegExp('$key: "(#[0-9a-fA-F]{6})"').firstMatch(config);

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
      // copies from its own config into colors.xml.
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

/// The colours the splash in `web/index.html` claims to be using.
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

void _splashMatchesTheme() {
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
      'primary': scheme.primary,
    };

    expect(
      declared.keys.toSet(),
      expected.keys.toSet(),
      reason:
          'the ${entry.key} splash palette and this test disagree about '
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
