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
import '../data/sync/remote_ledger_api.dart';
import '../domain/repositories/auth_service.dart';
import '../domain/repositories/device_token_repository.dart';
import 'preferences_providers.dart';

part 'backend_providers.g.dart';

/// Where this device's session lives between launches.
@Riverpod(keepAlive: true)
SessionStore sessionStore(Ref ref) =>
    SessionStore(ref.watch(sharedPreferencesProvider));

/// One HTTP client, shared by everything that talks to the backend.
///
/// Null for a deliberately local-only build, which is a real configuration:
/// every screen renders from the local database, so a build with no backend is
/// a working app that simply does not sync.
///
/// One rather than several, because the session is a property of the
/// connection. The web's cookie jar and Android's bearer interceptor both live
/// on this `Dio`; a second client would hold a second session and the two would
/// disagree the moment either changed.
@Riverpod(keepAlive: true)
api.OpensplitApi? apiClient(Ref ref) {
  if (apiBaseUrl.isEmpty) return null;

  final sessions = ref.watch(sessionStoreProvider);
  return buildApiClient(
    baseUrl: apiBaseUrl,
    // Read per request rather than captured, because the token behind it is
    // replaced on every sign-in, link and revalidation while this client is
    // built once and lives as long as the app.
    //
    // Always null on the web, where the session is a first-party HttpOnly
    // cookie the browser attaches and JavaScript cannot read.
    token: () async => sessions.read()?.token,
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
    // An asynchronous read here put a flash of the welcome screen in front of
    // everybody who was already signed in, on every launch.
    restored: sessions.read(),
    // The one place the two Google flows are chosen between. A platform that
    // can mint an ID token in-process gets that capability; the web is handed
    // null and sends the browser to Google instead, because Identity Services
    // answers into an iframe or a popup and neither survives the cross-origin
    // isolation `/app/**` needs for its database.
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
RemoteLedgerApi? remoteLedgerApi(Ref ref) {
  final client = ref.watch(apiClientProvider);
  return client == null ? null : CloudflareLedgerApi(client);
}

@Riverpod(keepAlive: true)
DeviceTokenRepository? deviceTokenRepository(Ref ref) {
  final client = ref.watch(apiClientProvider);
  return client == null ? null : CloudflareDeviceTokenRepository(client);
}
