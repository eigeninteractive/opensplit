import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';

/// A light and dark scheme derived from something outside this app.
typedef WallpaperSchemes = ({ColorScheme light, ColorScheme dark});

/// The palette the platform derives from the user's wallpaper, or null.
final wallpaperSchemesProvider = FutureProvider<WallpaperSchemes?>((ref) async {
  try {
    final palette = await DynamicColorPlugin.getCorePalette();
    if (palette != null) {
      return (
        light: palette.toColorScheme(),
        dark: palette.toColorScheme(brightness: Brightness.dark),
      );
    }

    final accent = await DynamicColorPlugin.getAccentColor();
    if (accent != null) {
      return (
        light: ColorScheme.fromSeed(seedColor: accent),
        dark: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
      );
    }
  } on PlatformException {
    // A platform that has the plugin but refused to answer. Indistinguishable
    // from not having one, as far as this app is concerned.
  }
  return null;
});

/// Whether to use the wallpaper palette when the platform offers one.
class WallpaperColorsController extends Notifier<bool> {
  static const _key = 'wallpaper_colors';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? true;

  Future<void> set({required bool enabled}) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (enabled) {
      await prefs.remove(_key);
    } else {
      await prefs.setBool(_key, false);
    }
    state = enabled;
  }
}

final wallpaperColorsProvider =
    NotifierProvider<WallpaperColorsController, bool>(
      WallpaperColorsController.new,
    );

/// The schemes the app should actually theme itself with, or null for the
/// brand's own.
final activeWallpaperSchemesProvider = Provider<WallpaperSchemes?>((ref) {
  if (!ref.watch(wallpaperColorsProvider)) return null;
  return ref.watch(wallpaperSchemesProvider).value;
});
