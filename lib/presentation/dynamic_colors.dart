import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';

/// A light and dark scheme derived from something outside this app.
typedef WallpaperSchemes = ({ColorScheme light, ColorScheme dark});

/// The palette the platform derives from the user's wallpaper, or null.
///
/// Asked for once, directly, rather than through `DynamicColorBuilder`. The
/// builder answers the same question but keeps the answer to itself, which
/// left the app unable to say whether Material You was actually running — so
/// "the colours look like the brand" and "this device has no wallpaper palette"
/// were indistinguishable, and the only way to tell them apart was to read
/// dynamic_color's own debug print. As a provider it is a fact anything can
/// read, including the settings screen that reports it.
///
/// Null is the ordinary answer nearly everywhere: the platform channel is
/// optional, so it yields null on the web and on any platform without the
/// plugin, and Android itself yields null below Android 12. The desktop accent
/// colour is used as a fallback, which is what the builder does too.
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
///
/// On by default, because Material You is the platform's own behaviour and an
/// app that ignores it looks like a visitor. Off is a real preference though:
/// a wallpaper palette can be nearly monochrome, and somebody who chose this
/// app partly for how it looks should be able to keep that.
///
/// Remembered the same way [ThemeModeController] remembers brightness — the
/// default is stored by *removing* the key, so a fresh install and a deliberate
/// return to the default are the same state.
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
///
/// The single place the preference and the platform's answer are combined, so
/// no caller has to remember to check both.
final activeWallpaperSchemesProvider = Provider<WallpaperSchemes?>((ref) {
  if (!ref.watch(wallpaperColorsProvider)) return null;
  return ref.watch(wallpaperSchemesProvider).value;
});
