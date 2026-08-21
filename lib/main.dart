import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'application/providers.dart';
import 'config.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      );
    } catch (error) {
      // Startup must not depend on reaching a server. Every screen is rendered
      // from the local database, so a build that cannot initialise its backend
      // is still a working app — it simply will not sync.
      debugPrint('OpenSplit: continuing without a backend ($error)');
    }
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const OpenSplitApp(),
    ),
  );
}
