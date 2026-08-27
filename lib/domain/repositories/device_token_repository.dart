/// Persists this installation's push token for the current account.
abstract interface class DeviceTokenRepository {
  /// Registers or transfers [token] to the authenticated account.
  Future<void> register({required String token, required String platform});

  /// Removes [token] only when it belongs to the authenticated account.
  Future<void> unregister(String token);
}
