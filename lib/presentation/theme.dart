import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's visual identity.
///
/// Material 3 with a single seed colour, and no custom component themes beyond
/// what earns its place. Light and dark are both first-class: an expense app is
/// opened at restaurant tables at night as often as anywhere else.
///
/// The seed is the brand, and it is the only colour anyone should ever type.
/// Everything else in the app is a role read off the [ColorScheme] this
/// generates — see docs/BRAND.md, which is the source this value comes from.
const _seed = Color(0xFF5B5891);

/// Source colour for "owed to you", before harmonisation.
///
/// Never used directly. It is a hue to derive a role from, in the same way
/// [_seed] is — the colour that actually reaches the screen is a tone from a
/// palette built out of this and harmonised against the running scheme.
const _creditSource = Color(0xFF2E7D32);

/// Colours for a balance figure, which [ColorScheme] has no role for.
///
/// "Owed to you" and "you owe" are semantic states rather than brand colours,
/// so they live in a theme extension instead of being written inline. They are
/// also derived rather than hardcoded: a fixed hex cannot be right in both
/// brightnesses, and it would sit unchanged while Material You replaced every
/// other colour on the screen.
///
/// [credit] follows the recipe Material 3 gives for a custom colour role, using
/// only public API to do it. `harmonizeWith` — dynamic_color's helper — shifts
/// the source hue toward the running scheme's primary so it belongs to the
/// palette rather than sitting on top of it. Seeding a scheme from the result
/// and taking its `primary` then yields the correct tone for the brightness:
/// that role is tone 40 in light and tone 80 in dark, which is what makes the
/// contrast against `surface` correct by construction rather than by luck.
///
/// Reaching for `Hct` and `TonalPalette` directly would compute the identical
/// colour while reimplementing what `fromSeed` already guarantees.
///
/// [debit] is `ColorScheme.error`. It is a real named role, already
/// brightness-correct, already harmonised with whatever scheme is running, and
/// visually the red people expect against money they owe. Deriving a second red
/// beside it would put two nearly identical reds in one palette for no gain.
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
///
/// [dynamicScheme] is the platform's own palette on Android 12+ and null
/// everywhere else, including the web. Harmonised against the seed so that a
/// wallpaper which happens to be red does not leave the app's own accents
/// clashing.
ThemeData buildTheme(Brightness brightness, [ColorScheme? dynamicScheme]) {
  final scheme =
      dynamicScheme?.harmonized() ??
      ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  final base = ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    extensions: [BalanceColors.of(scheme)],
    // No surfaceTintColor. Material 3 replaced the opacity-based tint overlay
    // with the tone-based surface roles, and Flutter's default is now null;
    // setting it would reinstate the model the spec moved away from. Depth
    // comes from surfaceContainer* instead.
    // Left-aligned everywhere, which is not the no-op it looks like: on iOS and
    // macOS an AppBar centres its title, and Flutter reports macOS as the
    // platform for any browser running on a Mac. Without this the same build
    // centres its title on a Mac and left-aligns it on Windows.
    appBarTheme: const AppBarThemeData(centerTitle: false),
    // Deliberately says nothing about elevation, colour or shape. Those are
    // what distinguishes Card, Card.filled and Card.outlined from each other,
    // and anything set here overrides all three at once — which is how this app
    // ended up hand-rolling an outlined card badly. Call sites pick the variant.
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      // Not a Material value. `margin: EdgeInsets.all(4)` is a literal in
      // Flutter's own gen_defaults card template — the elevation, colour and
      // shape beside it are interpolated from the Material token database, and
      // that database has no card margin at all. So this declines a Flutter
      // default rather than contradicting the spec, and it means the gap a list
      // writes between two cards is the gap on screen.
      margin: EdgeInsets.zero,
    ),
    // Outlined, not filled. Material 3 has exactly two text field variants: a
    // filled one whose container is tinted and whose only line is the underline
    // beneath it, and an outlined one with a transparent container inside a
    // full border. `filled: true` together with an OutlineInputBorder is
    // neither — a tinted box wearing the outlined variant's border. Outlined is
    // the one that belongs beside the outlined cards above.
    inputDecorationTheme: const InputDecorationThemeData(
      border: OutlineInputBorder(),
    ),
  );

  // Instrument Sans, resolved from the bundle rather than the network — see the
  // `fonts:`/`assets:` pair in pubspec.yaml and allowRuntimeFetching in
  // main.dart.
  //
  // Applied to Material 3's own type scale rather than replacing it: the sizes,
  // weights and tracking are the ones the spec sets, and only the face changes.
  //
  // Applied to `base.textTheme` rather than called bare, too. GoogleFonts's
  // no-argument form falls back to `ThemeData.light().textTheme`, which carries
  // light-mode ink — near-black — and that survives into the dark theme, where
  // it is very nearly the surface colour. Passing the base the scheme just
  // produced keeps each brightness its own.
  return base.copyWith(
    textTheme: GoogleFonts.instrumentSansTextTheme(base.textTheme),
  );
}

/// Colour for a balance figure.
///
/// Never the only signal. The wording says which way it goes, and
/// `BalanceAmount` puts an arrow beside it, for anyone who cannot separate the
/// hues — which is roughly one man in twelve.
Color balanceColor(ColorScheme scheme, int balanceMinor) {
  if (balanceMinor == 0) return scheme.onSurfaceVariant;
  final colors = BalanceColors.of(scheme);
  return balanceMinor > 0 ? colors.credit : colors.debit;
}
