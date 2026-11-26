import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth/session_store.dart';

/// The local resources needed to resolve the first route.
typedef AppStartup = ({SharedPreferences preferences, SessionStore sessions});

/// Loads the cached session. Hosts that supply their own resources start ready.
final appStartupProvider = FutureProvider<AppStartup?>(
  (ref) => null,
  retry: (_, _) => null,
);

/// Reads the saved session from disk and secure storage during app startup.
Future<AppStartup> loadAppStartup() async {
  final preferences = await SharedPreferences.getInstance();
  final sessions = await SessionStore.load(preferences);
  return (preferences: preferences, sessions: sessions);
}
