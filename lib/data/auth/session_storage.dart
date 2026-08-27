import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';

/// The session key shared by foreground auth and read-only background work.
String get sessionStorageKey =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

/// Opens a short-lived client without retaining or refreshing an old identity.
///
/// Only the foreground SDK owns token refresh and persistence. A second writer
/// can otherwise restore a session after sign-out or rotate its refresh token
/// underneath the foreground. Expired sessions defer work until app resume.
Future<SupabaseClient?> openBackgroundClient() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  if (preferences.getBool('notifications_requested') != true) return null;
  final stored = preferences.getString(sessionStorageKey);
  if (stored == null) return null;

  final client = SupabaseClient(
    supabaseUrl,
    supabasePublishableKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  try {
    await client.auth.setInitialSession(stored);
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) {
      await client.dispose();
      return null;
    }
    return client;
  } catch (_) {
    await client.dispose();
    rethrow;
  }
}
