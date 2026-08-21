import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import 'router.dart';
import 'theme.dart';

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

    return MaterialApp.router(
      title: 'OpenSplit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: _router,
    );
  }
}
