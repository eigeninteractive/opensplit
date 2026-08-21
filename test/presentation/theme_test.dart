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
}
