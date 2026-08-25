import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import 'router.dart';
import 'theme.dart';
import 'theme_mode.dart';

class OpenSplitApp extends ConsumerStatefulWidget {
  const OpenSplitApp({super.key});

  @override
  ConsumerState<OpenSplitApp> createState() => _OpenSplitAppState();
}

class _OpenSplitAppState extends ConsumerState<OpenSplitApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    // Establishes a session and registers for push, both silently and both
    // optional. Neither blocks a single frame: every screen renders from the
    // local database regardless of how these turn out.
    ref.watch(pushRegistrationProvider);

    // Material You on Android 12+; everywhere else the builder yields null and
    // the seeded scheme is used unchanged.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp.router(
        title: 'OpenSplit',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, lightDynamic),
        darkTheme: buildTheme(Brightness.dark, darkDynamic),
        // Both themes are always supplied, and this decides between them.
        // Defaults to following the platform — see [ThemeModeController].
        themeMode: ref.watch(themeModeProvider),
        routerConfig: _router,
      ),
    );
  }
}
