import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/push/notification_preferences.dart';
import '../data/push/push_service.dart';
import 'backend_providers.dart';
import 'entry_notification.dart';
import 'local_providers.dart';
import 'preferences_providers.dart';
import 'router_provider.dart';
import 'session_providers.dart';
import 'sync_providers.dart';

part 'push_providers.g.dart';

/// Push, wired to sync first and describe second.
@Riverpod(keepAlive: true)
PushService pushService(Ref ref) {
  final service = PushService(
    isEnabled: () =>
        ref.read(signedInProvider) &&
        ref.read(notificationPreferenceProvider) == true,
    onTokenChanged: (token) =>
        ref.read(notificationPreferenceProvider.notifier).register(token),
    onWake: (groupId) =>
        ref.read(syncControllerProvider.notifier).syncGroup(groupId),
    // The same composer the background isolate calls, so a notification says
    // the same thing whether the app was open when it arrived or not.
    describe: (push) => composeEventNotification(
      entries: ref.read(entryRepositoryProvider),
      groups: ref.read(groupRepositoryProvider),
      profiles: ref.read(profileRepositoryProvider),
      currencies: ref.read(currencyRepositoryProvider),
      activity: ref.read(activityRepositoryProvider),
      myProfileId: ref.read(currentAccountIdProvider),
      push: push,
    ),
    onOpenGroup: (groupId) {
      // The background isolate writes through another Drift connection.
      unawaited(ref.read(appDatabaseProvider).noticeWritesElsewhere());
      ref.read(routerProvider).go(groupNotificationRoute(groupId));
      unawaited(ref.read(syncControllerProvider.notifier).syncGroup(groupId));
    },
  );
  ref.onDispose(service.dispose);
  return service;
}

/// Registers this device for push, if the user has already agreed to it.
@Riverpod(keepAlive: true)
Future<void> pushRegistration(Ref ref) async {
  final wanted = ref.watch(notificationPreferenceProvider);
  final account = ref.watch(sessionControllerProvider);
  final tokens = ref.watch(deviceTokensProvider);
  if (wanted != true || account == null || tokens == null) return;

  try {
    final push = ref.read(pushServiceProvider);
    // Sets up listeners only.
    await push.initialize();
    if (!await push.hasPermission()) return;

    final token = await push.token();
    if (token == null || !ref.mounted) return;
    await ref.read(notificationPreferenceProvider.notifier).register(token);
  } catch (_) {
    // Push is not configured, or permission was refused. Neither is a problem
    // worth interrupting anyone about.
  }
}

/// Stores this device's choice and serializes changes to its push token.
@Riverpod(keepAlive: true)
class NotificationPreference extends _$NotificationPreference {
  Future<void> _pending = Future.value();

  /// Null until this device answers the in-app prompt.
  @override
  bool? build() =>
      ref.watch(sharedPreferencesProvider).getBool(notificationPreferenceKey);

  /// Records a refusal made in the app, before the OS is ever involved.
  Future<void> markDeclined() => _remember(false);

  /// Turns notifications on, prompting the OS if needed.
  Future<bool> enable() async {
    final push = ref.read(pushServiceProvider);
    final granted = await push.requestPermission();
    await _remember(granted);
    return granted;
  }

  /// Stops notifying this device, and removes its token from the server so the
  /// fan-out does not keep paying to wake a device that will ignore it.
  Future<void> disable() async {
    await _remember(false);
    await _inOrder(_unregister);
  }

  /// Removes the token while still signed in and holds off token refreshes
  /// until the session has ended. The next account keeps the device's choice.
  Future<void> releaseDeviceAndSignOut(Future<void> Function() signOut) =>
      _inOrder(() async {
        await _unregister();
        await signOut();
      });

  Future<void> _unregister() async {
    try {
      final push = ref.read(pushServiceProvider);
      final tokens = ref.read(deviceTokensProvider);
      // Asking for a token without permission prompts for it on the web.
      if (tokens == null || !await push.hasPermission()) return;
      final token = await push.token();
      if (token != null) await tokens.unregister(token);
    } catch (_) {
      // The preference is what governs this device either way.
    }
  }

  Future<void> _remember(bool wanted) async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(notificationPreferenceKey, wanted);
    state = wanted;
  }

  /// Registers a token if the same account still wants notifications.
  Future<void> register(String token) {
    final accountId = ref.read(currentAccountIdProvider);
    return _inOrder(() async {
      if (accountId == null ||
          state != true ||
          ref.read(currentAccountIdProvider) != accountId) {
        return;
      }
      final tokens = ref.read(deviceTokensProvider);
      await tokens?.register(
        token: token,
        platform: ref.read(pushServiceProvider).platform,
      );
    });
  }

  Future<void> _inOrder(Future<void> Function() change) {
    final result = _pending.then((_) => change());
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }
}
