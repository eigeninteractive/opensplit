import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import 'dynamic_colors.dart';
import 'theme.dart';
import 'theme_mode.dart';

class OpenSplitApp extends ConsumerWidget {
  const OpenSplitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Establishes a session and registers for push, both silently and both
    // optional. Neither blocks a single frame: every screen renders from the
    // local database regardless of how these turn out.
    ref.watch(pushRegistrationProvider);

    // Material You on Android 12+, when the user has not turned it off.
    // Everywhere else this is null and the seeded scheme is used unchanged.
    final wallpaper = ref.watch(activeWallpaperSchemesProvider);

    return MaterialApp.router(
      title: 'OpenSplit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, wallpaper?.light),
      darkTheme: buildTheme(Brightness.dark, wallpaper?.dark),
      // Both themes are always supplied, and this decides between them.
      // Defaults to following the platform — see [ThemeModeController].
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
