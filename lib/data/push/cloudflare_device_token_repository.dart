import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/repositories/device_token_repository.dart';

/// Where to wake this account, over the generated client.
final class CloudflareDeviceTokenRepository implements DeviceTokenRepository {
  const CloudflareDeviceTokenRepository(this._client);

  final api.OpensplitApi _client;

  @override
  Future<void> register({required String token, required String platform}) =>
      _client.getDevicesApi().registerDevice(
        device: api.Device(token: token, platform: _platform(platform)),
      );

  @override
  Future<void> unregister(String token) =>
      _client.getDevicesApi().forgetDevice(token: token);

  /// The platform, as the wire spells it.
  static api.Platform _platform(String platform) =>
      platform == 'android' ? api.Platform.android : api.Platform.web;
}
