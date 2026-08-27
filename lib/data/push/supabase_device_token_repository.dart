import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/device_token_repository.dart';

/// Supabase RPC implementation of the device-token boundary.
final class SupabaseDeviceTokenRepository implements DeviceTokenRepository {
  const SupabaseDeviceTokenRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> register({required String token, required String platform}) =>
      _client.rpc<void>(
        'register_device_token',
        params: {'p_token': token, 'p_platform': platform},
      );

  @override
  Future<void> unregister(String token) =>
      _client.rpc<void>('unregister_device_token', params: {'p_token': token});
}
