import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// The app's visual identity.
///
/// Material 3 with a single seed colour, and no custom component themes beyond
/// what earns its place. Light and dark are both first-class: an expense app is
/// opened at restaurant tables at night as often as anywhere else.
const _seed = Color(0xFF00695C);

/// Colours for a balance figure, which the [ColorScheme] has no slot for.
///
/// "Owed to you" and "you owe" are semantic states, not brand colours, so they
/// live in a theme extension rather than being written inline. That also makes
/// them survive a switch to Material You: a wallpaper-derived scheme changes
/// every other colour on the screen, and credit still has to read as credit.
///
/// Both values are defined per brightness. A single fixed green is the bug this
/// replaces — a light-mode green on a dark surface lands around 3.4:1, under
/// the 4.5:1 needed for text, on the one number the whole app exists to show.
@immutable
class BalanceColors extends ThemeExtension<BalanceColors> {
  const BalanceColors({required this.credit, required this.debit});

  /// Money owed to you.
  final Color credit;

  /// Money you owe.
  final Color debit;

  factory BalanceColors.of(ColorScheme scheme) => switch (scheme.brightness) {
    // Green 800 on a light surface: ~5.7:1.
    Brightness.light => BalanceColors(
      credit: const Color(0xFF2E7D32),
      debit: scheme.error,
    ),
    // Green 300 on a dark surface: ~8:1. The light-mode value here would be
    // unreadable.
    Brightness.dark => BalanceColors(
      credit: const Color(0xFF81C784),
      debit: scheme.error,
    ),
  };

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
/// [dynamic_] is the platform's own palette on Android 12+ and null everywhere
/// else, including the web. Harmonised against the seed so that a wallpaper
/// which happens to be red does not leave the app's own accents clashing.
ThemeData buildTheme(Brightness brightness, [ColorScheme? dynamic_]) {
  final scheme =
      dynamic_?.harmonized() ??
      ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    extensions: [BalanceColors.of(scheme)],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      centerTitle: false,
    ),
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

/// Colours for a balance figure.
///
/// Never the only signal — the wording says which way it goes too, for anyone
/// who cannot separate the hues.
Color balanceColor(ColorScheme scheme, int balanceMinor) {
  if (balanceMinor == 0) return scheme.onSurfaceVariant;
  final colors = BalanceColors.of(scheme);
  return balanceMinor > 0 ? colors.credit : colors.debit;
}
