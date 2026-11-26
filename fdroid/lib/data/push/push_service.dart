import 'package:opensplit_api/opensplit_api.dart' show Platform, PushData;

/// This build has no push transport. Foreground ledger sync is independent.
class PushService {
  PushService({
    required Future<void> Function(String groupId) onWake,
    required Future<({String title, String body})?> Function(PushData push)
    describe,
    required Future<void> Function(String token) onTokenChanged,
    required void Function(String groupId) onOpenGroup,
    required bool Function() isEnabled,
  });

  Future<void> initialize() async {}

  Future<bool> hasPermission() async => false;

  Future<bool> requestPermission() async => false;

  Future<String?> token() async => null;

  Platform get platform => Platform.android;

  Future<void> dispose() async {}
}
