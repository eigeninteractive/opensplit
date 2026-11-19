import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:opensplit/presentation/theme.dart';

/// Preloads bundled fonts before native presentation tests schedule a frame.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (!kIsWeb) {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    buildTheme(Brightness.light);
    await GoogleFonts.pendingFonts();
  }
  await testMain();
}
