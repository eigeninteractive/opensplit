import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../data/auth/google_sign_in_gateway.dart';
import '../data/auth/supabase_auth_service.dart';
import '../data/push/supabase_device_token_repository.dart';
import '../config.dart';
import '../data/sync/api_client.dart';
import '../data/sync/cloudflare_ledger_api.dart';
import '../domain/repositories/auth_service.dart';
import '../domain/repositories/device_token_repository.dart';
import '../domain/repositories/invite_api.dart';
import '../data/sync/remote_ledger_api.dart';

part 'backend_providers.g.dart';

/// The configured backend client, or null for a deliberately local-only build.
@Riverpod(keepAlive: true)
sb.SupabaseClient? supabaseClient(Ref ref) {
  try {
    return sb.Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

@Riverpod(keepAlive: true)
AuthService? authService(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  // The one place the two Google flows are chosen between. A platform that can
  // mint an ID token in-process gets that capability; the web is handed null
  // and sends the browser to Google instead, because Identity Services answers
  // into an iframe or a popup and neither survives the cross-origin isolation
  // `/app/**` needs for its database.
  return SupabaseAuthService(
    client,
    googleTokens: kIsWeb ? null : GoogleSignInGateway(),
  );
}

/// Invites move to the Cloudflare backend with the rest of the link flows.
/// Until then there is no implementation, and a null provider is the honest
/// way to say so — it is already the shape every caller handles, because a
/// deliberately local-only build has always produced one.
@Riverpod(keepAlive: true)
InviteApi? inviteApi(Ref ref) => null;

@Riverpod(keepAlive: true)
RemoteLedgerApi? remoteLedgerApi(Ref ref) {
  if (apiBaseUrl.isEmpty) return null;

  return CloudflareLedgerApi(
    buildApiClient(
      baseUrl: apiBaseUrl,
      // Where the Better Auth client will hand over Android's bearer token.
      // It is not here yet, and returning null is the honest placeholder: an
      // unauthenticated request is refused with a 401 the sync reports, rather
      // than a Supabase token the Cloudflare backend has never heard of being
      // sent and failing in a way that looks like something else.
      //
      // The web needs nothing here either way: its session is a first-party
      // cookie the browser attaches and JavaScript cannot read.
      token: () async => null,
    ),
  );
}

@Riverpod(keepAlive: true)
DeviceTokenRepository? deviceTokenRepository(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseDeviceTokenRepository(client);
}
