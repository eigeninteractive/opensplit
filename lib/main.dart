import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'application/providers.dart';
import 'config.dart';
import 'data/auth/session_storage.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // google_fonts falls back to downloading a face it cannot find in the
  // bundle. Everything this app uses is bundled, so a miss is a packaging
  // mistake, and it should surface as one rather than as a silent request to
  // Google on a user's first launch — which is exactly what an app promising
  // to work offline and report nothing must not do.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Real paths, not hash fragments. A fragment is never sent to the server, so
  // a `#/g/123` URL cannot be an Android App Link — the whole "tap a shared
  // link and land in the group" flow depends on this one line.
  usePathUrlStrategy();

  final prefs = await SharedPreferences.getInstance();

  if (hasBackend) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SharedPreferencesLocalStorage(
            persistSessionKey: sessionStorageKey,
          ),
        ),
      );
    } catch (error, stackTrace) {
      // Startup must not depend on reaching a server. Every screen is rendered
      // from the local database, so a build that cannot initialise its backend
      // is still a working app — it simply will not sync.
      //
      // developer.log rather than a print: this carries the error and the trace
      // as structured fields, so DevTools shows it as one collapsible entry
      // with a real stack instead of a line of text, and level 900 (WARNING)
      // says what it is. A print would also have gone to release console output
      // on the web, where anyone can read it.
      developer.log(
        'Continuing without a backend',
        name: 'opensplit.startup',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // A build that cannot reach its backend says so, rather than looking correct
  // and quietly doing nothing. See [configurationProblem]: this only ever fires
  // on a release build that was made without its dart-defines, which is
  // indistinguishable from a working one until somebody tries to sign in.
  final problem = configurationProblem;
  if (problem != null) {
    developer.log(
      problem,
      name: 'opensplit.startup',
      level: 1000, // SEVERE
    );
    runApp(_Misconfigured(problem));
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
///
/// Deliberately plain: no theme, no router, no providers. Everything that would
/// make this look like the app is a thing that could fail for the same reason
/// the app cannot run.
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
