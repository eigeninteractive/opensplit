import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/providers.dart';
import 'config.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // google_fonts falls back to downloading a face it cannot find in the bundle.
  GoogleFonts.config.allowRuntimeFetching = false;

  // The faces ship with their licence, and the app can show it.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Instrument Sans',
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/google_fonts/LICENSE'));
  });

  // Real paths, not hash fragments.
  usePathUrlStrategy();

  final prefs = await SharedPreferences.getInstance();

  // Nothing to initialise for the backend: the session is a stored token and a
  // cached account that `BetterAuthService` reads synchronously from the
  // preferences above and revalidates later.

  // A build that cannot reach its backend says so, rather than looking correct
  // and quietly doing nothing.
  final problem = configurationProblem;
  if (problem != null) {
    developer.log(
      problem,
      name: 'opensplit.startup',
      level: 1000, // SEVERE
    );
    // Scoped like the real launch below, though this screen reads nothing from
    // a provider.
    runApp(ProviderScope(child: _Misconfigured(problem)));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const OpenSplitApp(),
    ),
  );
}

/// Shown instead of the app when the build itself is wrong.
class _Misconfigured extends StatelessWidget {
  const _Misconfigured(this.problem);

  final String problem;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.build_outlined, size: 40),
              const SizedBox(height: 16),
              const Text(
                'This build is not configured',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(problem, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
