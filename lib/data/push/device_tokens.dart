import 'package:opensplit_api/opensplit_api.dart' as api;

import '../sync/api_client.dart';

/// Where the server wakes this account: FCM registration tokens. Throws
/// [ApiFailure], like every other call to the server.
final class DeviceTokens {
  const DeviceTokens(this._client);

  final api.OpensplitApi _client;

  Future<void> register({
    required String token,
    required api.Platform platform,
  }) => send(
    _client.getDevicesApi().registerDevice(
      device: api.Device(token: token, platform: platform),
    ),
  );

  Future<void> unregister(String token) =>
      send(_client.getDevicesApi().forgetDevice(token: token));
}
