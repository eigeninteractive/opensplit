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

  // google_fonts falls back to downloading a face it cannot find in the
  // bundle. Everything this app uses is bundled, so a miss is a packaging
  // mistake, and it should surface as one rather than as a silent request to
  // Google on a user's first launch — which is exactly what an app promising
  // to work offline and report nothing must not do.
  GoogleFonts.config.allowRuntimeFetching = false;

  // The faces ship with their licence, and the app can show it.
  //
  // Flutter's licence page is built from [LicenseRegistry], which is populated
  // from the LICENSE file of every *package* in the build. These four faces are
  // not a package — they are .ttf files in `assets/`, and package:google_fonts
  // registers nothing of its own -- so the one screen that offers "the packages
  // this app is built on, and their terms" was missing the only third-party
  // work the app actually redistributes. The OFL asks for the notice and the
  // licence to accompany every copy; this is the copy a user can read.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Instrument Sans',
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/google_fonts/LICENSE'));
  });

  // Real paths, not hash fragments. A fragment is never sent to the server, so
  // a `#/g/123` URL cannot be an Android App Link — the whole "tap a shared
  // link and land in the group" flow depends on this one line.
  usePathUrlStrategy();

  final prefs = await SharedPreferences.getInstance();

  // Nothing to initialise for the backend, and that is the shape of it now.
  //
  // There used to be a network-capable SDK to stand up here, inside a
  // try/catch, because launching must not depend on reaching a server. The
  // session is now a stored token and a cached account that
  // `BetterAuthService` reads synchronously from the preferences already
  // loaded above, and revalidates against the Worker afterwards. A device with
  // no connectivity launches exactly as it did before and simply does not
  // sync.

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
    // Scoped like the real launch below, though this screen reads nothing from
    // a provider. It costs an empty container and buys an invariant with no
    // exceptions in it: every runApp in this app is inside a ProviderScope,
    // which is a cheaper thing to hold in your head than one that is true
    // apart from the error path.
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
