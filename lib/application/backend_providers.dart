import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../data/auth/supabase_auth_service.dart';
import '../data/push/supabase_device_token_repository.dart';
import '../data/sync/supabase_invite_api.dart';
import '../data/sync/supabase_ledger_api.dart';
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
  return client == null ? null : SupabaseAuthService(client);
}

@Riverpod(keepAlive: true)
InviteApi? inviteApi(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseInviteApi(client);
}

@Riverpod(keepAlive: true)
RemoteLedgerApi? remoteLedgerApi(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseLedgerApi(client);
}

@Riverpod(keepAlive: true)
DeviceTokenRepository? deviceTokenRepository(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseDeviceTokenRepository(client);
}
