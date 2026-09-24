import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/repositories/device_token_repository.dart';

/// Where to wake this account, over the generated client.
///
/// Registration is an upsert that transfers the token rather than refusing it,
/// which matters more than it looks: a phone that changes hands keeps its
/// Firebase registration token, so a claim that could not move would send the
/// previous owner's notifications to whoever holds the device now.
///
/// Unregistering only removes a token this account holds. That is enforced on
/// the server rather than assumed here — signing out on one phone must not be
/// able to silence somebody else's.
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
  ///
  /// The caller passes the string Firebase's own plumbing uses, and anything
  /// that is not Android is the web build — there is no third target, and iOS
  /// will be the point at which this stops being a two-way choice rather than
  /// something to guess at now.
  static api.DevicePlatformEnum _platform(String platform) =>
      platform == 'android'
      ? api.DevicePlatformEnum.android
      : api.DevicePlatformEnum.web;
}
