import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config.dart';
import '../data/auth/better_auth_service.dart';
import '../data/auth/google_sign_in_gateway.dart';
import '../data/auth/session_store.dart';
import '../data/push/cloudflare_device_token_repository.dart';
import '../data/sync/api_client.dart';
import '../data/sync/invites.dart';
import '../domain/repositories/auth_service.dart';
import '../domain/repositories/device_token_repository.dart';
import 'preferences_providers.dart';

part 'backend_providers.g.dart';

/// Where this device's session lives between launches.
@Riverpod(keepAlive: true)
SessionStore sessionStore(Ref ref) =>
    SessionStore(ref.watch(sharedPreferencesProvider));

/// The one client for the app's lifetime, since the session belongs to it.
/// [BetterAuthService] sets the bearer token (Android) whenever the session
/// changes. Null for a local-only build, which works and simply never syncs.
@Riverpod(keepAlive: true)
api.OpensplitApi? apiClient(Ref ref) {
  if (apiBaseUrl.isEmpty) return null;
  return buildApiClient(
    baseUrl: apiBaseUrl,
    token: ref.watch(sessionStoreProvider).read()?.token,
  );
}

@Riverpod(keepAlive: true)
AuthService? authService(Ref ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;

  final sessions = ref.watch(sessionStoreProvider);
  final service = BetterAuthService(
    client: client,
    sessions: sessions,
    // Synchronously, so `currentUser` has an answer before the first frame.
    restored: sessions.read(),
    // The one place the two Google flows are chosen between.
    googleTokens: kIsWeb ? null : GoogleSignInGateway(),
  );

  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
Invites? invites(Ref ref) {
  final client = ref.watch(apiClientProvider);
  return client == null ? null : Invites(client);
}

@Riverpod(keepAlive: true)
DeviceTokenRepository? deviceTokenRepository(Ref ref) {
  final client = ref.watch(apiClientProvider);
  return client == null ? null : CloudflareDeviceTokenRepository(client);
}
