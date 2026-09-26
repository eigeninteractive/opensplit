import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'entry_notification.dart';
import '../data/push/push_service.dart';
import 'backend_providers.dart';
import 'local_providers.dart';
import 'session_providers.dart';
import 'sync_providers.dart';
import 'preferences_providers.dart';
import 'router_provider.dart';

part 'push_providers.g.dart';

/// Push, wired to sync first and describe second.
@Riverpod(keepAlive: true)
PushService pushService(Ref ref) {
  final service = PushService(
    isEnabled: () =>
        ref.read(signedInProvider) && ref.read(notificationPreferenceProvider),
    onTokenChanged: (token) => _registerDeviceToken(ref, token),
    onWake: (groupId) =>
        ref.read(syncControllerProvider.notifier).syncGroup(groupId),
    // The same composer the background isolate calls, so a notification says
    // the same thing whether the app was open when it arrived or not.
    describe: (groupId, kind, subjectId) => composeEventNotification(
      entries: ref.read(entryRepositoryProvider),
      groups: ref.read(groupRepositoryProvider),
      profiles: ref.read(profileRepositoryProvider),
      currencies: ref.read(currencyRepositoryProvider),
      activity: ref.read(activityRepositoryProvider),
      myProfileId: ref.read(currentAccountIdProvider),
      groupId: groupId,
      kind: kind,
      subjectId: subjectId,
    ),
    onOpenGroup: (groupId) {
      // The background isolate writes through another Drift connection.
      ref.read(appDatabaseProvider).refreshAfterExternalSync();
      ref.read(routerProvider).go(groupNotificationRoute(groupId));
      unawaited(ref.read(syncControllerProvider.notifier).syncGroup(groupId));
    },
  );
  ref.onDispose(service.dispose);
  return service;
}

/// Sends this device's token to the server.
Future<void> _registerDeviceToken(Ref ref, String token) async {
  final tokens = ref.read(deviceTokenRepositoryProvider);
  final account = ref.read(sessionControllerProvider);
  if (tokens == null ||
      account == null ||
      !ref.read(notificationPreferenceProvider)) {
    return;
  }

  // Unconditional, because a device changes hands.
  await tokens.register(
    token: token,
    platform: ref.read(pushServiceProvider).platform,
  );
}

/// Registers this device for push, if the user has already agreed to it.
@Riverpod(keepAlive: true)
Future<void> pushRegistration(Ref ref) async {
  final wanted = ref.watch(notificationPreferenceProvider);
  final account = ref.watch(sessionControllerProvider);
  final tokens = ref.watch(deviceTokenRepositoryProvider);
  if (!wanted || account == null || tokens == null) return;

  try {
    final push = ref.read(pushServiceProvider);
    // Sets up listeners only.
    await push.initialize();
    if (!await push.hasPermission()) return;

    final token = await push.token();
    if (token == null) return;
    await _registerDeviceToken(ref, token);
  } catch (error) {
    // Push is not configured, or permission was refused. Neither is a problem
    // worth interrupting anyone about.
  }
}

/// Whether the user has asked to be told about group activity.
@Riverpod(keepAlive: true)
class NotificationPreference extends _$NotificationPreference {
  static const _key = 'notifications_requested';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  /// Whether the user has ever been shown the prompt.
  bool hasBeenAsked() => ref.read(sharedPreferencesProvider).containsKey(_key);

  /// Records a refusal made in the app, before the OS is ever involved.
  Future<void> markDeclined() => _remember(false);

  /// Turns notifications on, prompting the OS if needed.
  Future<bool> enable() async {
    final push = ref.read(pushServiceProvider);
    final granted = await push.requestPermission();
    await _remember(granted);
    if (!granted) return false;

    final token = await push.token();
    if (token == null) return false;
    await _registerDeviceToken(ref, token);
    return true;
  }

  /// Stops notifying this device, and removes its token from the server so the
  /// fan-out does not keep paying to wake a device that will ignore it.
  Future<void> disable() async {
    await _remember(false);
    final tokens = ref.read(deviceTokenRepositoryProvider);
    final token = await ref.read(pushServiceProvider).token();
    if (tokens == null || token == null) return;
    try {
      await tokens.unregister(token);
    } catch (_) {
      // The preference is what governs this device either way.
    }
  }

  Future<void> _remember(bool wanted) async {
    await ref.read(sharedPreferencesProvider).setBool(_key, wanted);
    state = wanted;
  }
}
