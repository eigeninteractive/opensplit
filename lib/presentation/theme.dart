import 'package:flutter/material.dart';

/// The app's visual identity.
///
/// Material 3 with a single seed colour, and no custom component themes beyond
/// what earns its place. Light and dark are both first-class: an expense app is
/// opened at restaurant tables at night as often as anywhere else.
const _seed = Color(0xFF00695C);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
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
/// Money owed to you and money you owe read very differently at a glance, and
/// the sign alone is too easy to miss. Never the only signal though — the
/// wording says which way it goes too, for anyone who cannot separate the hues.
Color balanceColor(ColorScheme scheme, int balanceMinor) {
  if (balanceMinor == 0) return scheme.onSurfaceVariant;
  return balanceMinor > 0 ? const Color(0xFF2E7D32) : scheme.error;
}
