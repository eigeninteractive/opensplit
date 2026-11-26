import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/platform/app_update_service.dart';
import '../data/platform/review_prompt.dart';
import '../data/sync/api_client.dart';
import 'app_startup.dart';
import 'backend_providers.dart';
import 'local_providers.dart';

part 'preferences_providers.g.dart';

/// The platform preferences loaded during startup.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) =>
    ref.watch(appStartupProvider).requireValue?.preferences ??
    (throw StateError('Shared preferences must be supplied by the app host'));

/// Play's own update flow, and nothing anywhere else.
@Riverpod(keepAlive: true)
AppUpdateService appUpdateService(Ref ref) => const AppUpdateService();

/// Asking for a store review, rarely and unconditionally.
@Riverpod(keepAlive: true)
ReviewPrompt reviewPrompt(Ref ref) =>
    ReviewPrompt(ref.watch(sharedPreferencesProvider));

/// How far this account has read a group: the time of the newest activity
/// it has looked at, on any of its devices. Null until its first visit.
///
/// Kept here so the answer is there offline and before the first frame, and
/// with the server so the account's other devices agree. Whichever is later
/// wins, and it only ever moves forward.
@Riverpod(keepAlive: true)
class GroupSeenAt extends _$GroupSeenAt {
  late String _key;

  @override
  DateTime? build(String groupId) {
    // Per account, because a device changes hands.
    _key = 'group_seen_at.${ref.watch(currentAccountIdProvider)}.$groupId';
    final stored = ref.watch(sharedPreferencesProvider).getInt(_key);
    return stored == null ? null : DateTime.fromMillisecondsSinceEpoch(stored);
  }

  /// Records that activity up to [at] has been shown, here and for the
  /// account's other devices.
  Future<void> markSeen(DateTime at) async {
    if (state case final seen? when !at.isAfter(seen)) return;
    await _store(at);
    await _upload(at);
  }

  /// Settles this device's answer against the [server]'s after a sync.
  Future<void> adopt(DateTime? server) async {
    final local = state;
    if (server != null && (local == null || server.isAfter(local))) {
      await _store(server);
    } else if (local != null && (server == null || local.isAfter(server))) {
      // Marked while offline, or the upload was lost.
      await _upload(local);
    }
  }

  Future<void> _store(DateTime at) async {
    state = at;
    await ref
        .read(sharedPreferencesProvider)
        .setInt(_key, at.millisecondsSinceEpoch);
  }

  Future<void> _upload(DateTime at) async {
    try {
      final settled = await ref
          .read(groupSignalsProvider)
          ?.markSeen(groupId, at);
      // The server's answer stands: it never runs ahead of its own clock,
      // and another device may have read further.
      if (settled != null && ref.mounted) await _store(settled);
    } on ApiFailure {
      // The next sync compares the two again and retries.
    }
  }
}
