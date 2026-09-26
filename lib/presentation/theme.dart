import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's visual identity.
const _seed = Color(0xFF5B5891);

/// Source colour for "owed to you", before harmonisation.
const _creditSource = Color(0xFF2E7D32);

/// Colours for a balance figure, which [ColorScheme] has no role for.
@immutable
class BalanceColors extends ThemeExtension<BalanceColors> {
  const BalanceColors({required this.credit, required this.debit});

  /// Money owed to you.
  final Color credit;

  /// Money you owe.
  final Color debit;

  factory BalanceColors.of(ColorScheme scheme) {
    final credit = ColorScheme.fromSeed(
      seedColor: _creditSource.harmonizeWith(scheme.primary),
      brightness: scheme.brightness,
    );

    return BalanceColors(credit: credit.primary, debit: scheme.error);
  }

  @override
  BalanceColors copyWith({Color? credit, Color? debit}) =>
      BalanceColors(credit: credit ?? this.credit, debit: debit ?? this.debit);

  @override
  BalanceColors lerp(ThemeExtension<BalanceColors>? other, double t) {
    if (other is! BalanceColors) return this;
    return BalanceColors(
      credit: Color.lerp(credit, other.credit, t)!,
      debit: Color.lerp(debit, other.debit, t)!,
    );
  }
}

/// Builds the theme, optionally from a wallpaper-derived scheme.
ThemeData buildTheme(Brightness brightness, [ColorScheme? dynamicScheme]) {
  final scheme =
      dynamicScheme?.harmonized() ??
      ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  final base = ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    extensions: [BalanceColors.of(scheme)],
    // No surfaceTintColor.
    appBarTheme: const AppBarThemeData(centerTitle: false),
    // Deliberately says nothing about elevation, colour or shape.
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      // Not a Material value.
      margin: EdgeInsets.zero,
    ),
    // Outlined, not filled.
    inputDecorationTheme: const InputDecorationThemeData(
      border: OutlineInputBorder(),
    ),
  );

  // Instrument Sans, resolved from the bundle rather than the network — see the
  // `fonts:`/`assets:` pair in pubspec.yaml and allowRuntimeFetching in
  // main.dart.
  return base.copyWith(
    textTheme: GoogleFonts.instrumentSansTextTheme(base.textTheme),
  );
}

/// [style], with money set in the app's tabular face.
TextStyle moneyStyle(TextStyle style) => GoogleFonts.jetBrainsMono(
  textStyle: style,
  fontWeight: FontWeight.w500,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// Colour for a balance figure.
Color balanceColor(ColorScheme scheme, int balanceMinor) {
  if (balanceMinor == 0) return scheme.onSurfaceVariant;
  final colors = BalanceColors.of(scheme);
  return balanceMinor > 0 ? colors.credit : colors.debit;
}
