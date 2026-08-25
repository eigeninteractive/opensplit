import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';

/// Whether the app follows the platform, or a brightness the user picked.
///
/// [ThemeMode.system] is the default and stays the default: an expense app is
/// opened at a restaurant table at night and in an office at midday, and the
/// platform already knows which. Overriding that by default would be guessing
/// against information the device has and the app does not.
///
/// The choice is remembered, and "system" is remembered by *forgetting* — going
/// back to it removes the key rather than storing the word. That way a fresh
/// install and a deliberate return to system are the same state, and there is
/// no third value meaning "system, but chosen".
///
/// Lives in the presentation layer rather than beside the other preferences in
/// application/providers.dart, because [ThemeMode] is a Material type and that
/// file is deliberately free of Flutter's UI library.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final stored = ref.watch(sharedPreferencesProvider).getString(_key);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> set(ThemeMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == ThemeMode.system) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, mode.name);
    }
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
