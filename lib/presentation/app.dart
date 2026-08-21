import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';

class OpenSplitApp extends StatefulWidget {
  const OpenSplitApp({super.key});

  @override
  State<OpenSplitApp> createState() => _OpenSplitAppState();
}

class _OpenSplitAppState extends State<OpenSplitApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'OpenSplit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: _router,
    );
  }
}
