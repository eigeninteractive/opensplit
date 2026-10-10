import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/backend_providers.dart';
import 'application/preferences_providers.dart';
import 'config.dart';
import 'data/web/launch_signal.dart';
import 'data/auth/session_store.dart';
import 'presentation/app.dart';
import 'presentation/launch_hold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The splash stays up while the first screen reads what is saved, so a launch
  // is one wait that ends on real content.
  LaunchHold.begin(onShown: announceLaunchShown);

  // google_fonts falls back to downloading a face it cannot find in the bundle.
  GoogleFonts.config.allowRuntimeFetching = false;

  // The faces ship with their licence, and the app can show it.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Instrument Sans',
    ], await rootBundle.loadString('assets/google_fonts/LICENSE'));
  });

  // Real paths, not hash fragments.
  usePathUrlStrategy();

  final prefs = await SharedPreferences.getInstance();

  // The session is a cached account in the preferences above and, on Android,
  // a bearer token in secure storage. Both are read now so that
  // `BetterAuthService` can answer synchronously, then revalidates.
  final sessions = await SessionStore.load(prefs);

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
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionStoreProvider.overrideWithValue(sessions),
      ],
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
