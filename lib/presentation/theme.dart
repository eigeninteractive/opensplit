import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:opensplit_api/opensplit_api.dart' show AvatarColor;

import '../domain/avatar.dart';

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

/// A colour scheme for each hue an avatar can take.
///
/// Material has one scheme per app; an avatar's hue is a second source colour,
/// so each gets its own scheme from [ColorScheme.fromSeed], harmonised with the
/// app's primary the way the credit colour is. A widget then takes ordinary
/// roles from it: an avatar its `primaryContainer` pair, a cover more.
@immutable
class AvatarPalette extends ThemeExtension<AvatarPalette> {
  const AvatarPalette(this._schemes);

  factory AvatarPalette.from(ColorScheme scheme) => AvatarPalette({
    for (final hue in avatarHues)
      hue: ColorScheme.fromSeed(
        seedColor: _hueSources[hue]!.harmonizeWith(scheme.primary),
        brightness: scheme.brightness,
      ),
  });

  final Map<AvatarColor, ColorScheme> _schemes;

  /// The scheme for [hue].
  ColorScheme operator [](AvatarColor hue) =>
      _schemes[hue] ?? _schemes.values.first;

  /// The theme's palette, or one derived from its colours for a theme that
  /// was not built by [buildTheme].
  static AvatarPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AvatarPalette>() ??
        AvatarPalette.from(theme.colorScheme);
  }

  @override
  AvatarPalette copyWith() => this;

  @override
  AvatarPalette lerp(ThemeExtension<AvatarPalette>? other, double t) {
    if (other is! AvatarPalette) return this;
    return AvatarPalette({
      for (final hue in avatarHues)
        hue: ColorScheme.lerp(this[hue], other[hue], t),
    });
  }
}

/// Source colours for the avatar hues, before harmonisation.
const _hueSources = {
  AvatarColor.purple: Color(0xFF7E57C2),
  AvatarColor.blue: Color(0xFF1E88E5),
  AvatarColor.teal: Color(0xFF00897B),
  AvatarColor.green: Color(0xFF43A047),
  AvatarColor.olive: Color(0xFF9E9D24),
  AvatarColor.amber: Color(0xFFFFB300),
  AvatarColor.orange: Color(0xFFF4511E),
  AvatarColor.pink: Color(0xFFD81B60),
};

/// Builds the theme, optionally from a wallpaper-derived scheme.
ThemeData buildTheme(Brightness brightness, [ColorScheme? dynamicScheme]) {
  final scheme =
      dynamicScheme?.harmonized() ??
      ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  final base = ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    extensions: [BalanceColors.of(scheme), AvatarPalette.from(scheme)],
    // No surfaceTintColor.
    appBarTheme: const AppBarThemeData(centerTitle: false),
    // Deliberately says nothing about elevation, colour or shape.
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      // Not a Material value.
      margin: EdgeInsets.zero,
    ),
    // Icon buttons are the one component material_ui already ships in its
    // Material 3 Expressive form, which is where the rest of the app is
    // headed: opted in here, once, for every icon button.
    iconButtonTheme: const IconButtonThemeData(
      variant: StyleVariant.material3Expressive,
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

/// [style], with figures of equal width, so amounts line up in a column and
/// do not shift as they change.
TextStyle moneyStyle(TextStyle style) =>
    style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// Colour for a balance figure.
Color balanceColor(ColorScheme scheme, int balanceMinor) {
  if (balanceMinor == 0) return scheme.onSurfaceVariant;
  final colors = BalanceColors.of(scheme);
  return balanceMinor > 0 ? colors.credit : colors.debit;
}
