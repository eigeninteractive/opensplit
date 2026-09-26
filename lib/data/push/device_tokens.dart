import 'package:opensplit_api/opensplit_api.dart' as api;

/// Where the server wakes this account: FCM registration tokens.
final class DeviceTokens {
  const DeviceTokens(this._client);

  final api.OpensplitApi _client;

  Future<void> register({
    required String token,
    required api.Platform platform,
  }) => _client.getDevicesApi().registerDevice(
    device: api.Device(token: token, platform: platform),
  );

  Future<void> unregister(String token) =>
      _client.getDevicesApi().forgetDevice(token: token);
}
