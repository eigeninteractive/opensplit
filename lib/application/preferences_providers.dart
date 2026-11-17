import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/platform/app_update_service.dart';
import '../data/platform/review_prompt.dart';

part 'preferences_providers.g.dart';

/// Overridden in `main` once the platform store has loaded.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) =>
    throw UnimplementedError('sharedPreferencesProvider must be overridden');

/// Play's own update flow, and nothing anywhere else.
@Riverpod(keepAlive: true)
AppUpdateService appUpdateService(Ref ref) => const AppUpdateService();

/// Asking for a store review, rarely and unconditionally.
@Riverpod(keepAlive: true)
ReviewPrompt reviewPrompt(Ref ref) =>
    ReviewPrompt(ref.watch(sharedPreferencesProvider));

/// When this device last had a group open, which is what "new since you
/// last looked" is measured from. Null until its first visit.
///
/// Kept on the device rather than with the account: it records what this
/// screen has shown, not anything about the group.
@riverpod
class GroupSeenAt extends _$GroupSeenAt {
  String get _key => 'group_seen_at.$groupId';

  @override
  DateTime? build(String groupId) {
    final stored = ref.watch(sharedPreferencesProvider).getInt(_key);
    return stored == null ? null : DateTime.fromMillisecondsSinceEpoch(stored);
  }

  Future<void> markNow() async {
    final now = DateTime.now();
    state = now;
    await ref
        .read(sharedPreferencesProvider)
        .setInt(_key, now.millisecondsSinceEpoch);
  }
}
