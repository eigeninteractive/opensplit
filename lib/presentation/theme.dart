import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// The app's visual identity.
///
/// Material 3 with a single seed colour, and no custom component themes beyond
/// what earns its place. Light and dark are both first-class: an expense app is
/// opened at restaurant tables at night as often as anywhere else.
const _seed = Color(0xFF00695C);

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

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    extensions: [BalanceColors.of(scheme)],
    // No surfaceTintColor. Material 3 replaced the opacity-based tint overlay
    // with the tone-based surface roles, and Flutter's default is now null;
    // setting it would reinstate the model the spec moved away from. Depth
    // comes from surfaceContainer* instead.
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
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
