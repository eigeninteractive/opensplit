import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/presentation/theme.dart';

/// Loads bundled fonts before widget tests can schedule a layout frame.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  buildTheme(Brightness.light);
  await GoogleFonts.pendingFonts();
  await testMain();
}
