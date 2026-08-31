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
///
/// The message from the server carries only ids. Everything the notification
/// says is produced here, from data that has just been pulled onto this device,
/// using the same formatter the screens use.
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
    describe: (groupId, entryId) => composeEntryNotification(
      entries: ref.read(entryRepositoryProvider),
      groups: ref.read(groupRepositoryProvider),
      profiles: ref.read(profileRepositoryProvider),
      currencies: ref.read(currencyRepositoryProvider),
      activity: ref.read(activityRepositoryProvider),
      myProfileId: ref.read(currentAccountIdProvider),
      groupId: groupId,
      entryId: entryId,
    ),
    onOpenGroup: (groupId) {
      // The background isolate writes through another Drift connection. Tell
      // this connection to re-run its live queries before the destination
      // reads them, then pull anything the background attempt did not finish.
      ref.read(appDatabaseProvider).refreshAfterExternalSync();
      ref.read(routerProvider).go(groupNotificationRoute(groupId));
      unawaited(ref.read(syncControllerProvider.notifier).syncGroup(groupId));
    },
  );
  ref.onDispose(service.dispose);
  return service;
}

/// Sends this device's token to the server.
///
/// Shared by first registration and by the rotation listener, so both write the
/// same row the same way.
Future<void> _registerDeviceToken(Ref ref, String token) async {
  final tokens = ref.read(deviceTokenRepositoryProvider);
  final account = ref.read(sessionControllerProvider);
  if (tokens == null ||
      account == null ||
      !ref.read(notificationPreferenceProvider)) {
    return;
  }

  // An RPC rather than an upsert, because a device changes hands. Signing in
  // as a different account, or reinstalling, gets the same registration back
  // from FCM while the stored row still names the previous owner — and RLS
  // evaluates an upsert's UPDATE half against that row and refuses it. The
  // symptom is a device that silently stops receiving anything.
  //
  // register_device_token always writes auth.uid(), so the takeover is the
  // only thing it can do.
  await tokens.register(
    token: token,
    platform: ref.read(pushServiceProvider).platform,
  );
}

/// Registers this device for push, if the user has already agreed to it.
///
/// Deliberately does NOT ask for permission. Asking is a separate, explicit
/// action taken from Settings or from the invite flow — see
/// [PushService.requestPermission]. This provider only wires up an
/// already-granted permission, so a launch never produces a system dialog.
///
/// Failure is not surfaced: push is a convenience on top of sync, and a device
/// that cannot register still receives everything the next time a screen opens.
@Riverpod(keepAlive: true)
Future<void> pushRegistration(Ref ref) async {
  final wanted = ref.watch(notificationPreferenceProvider);
  final account = ref.watch(sessionControllerProvider);
  final tokens = ref.watch(deviceTokenRepositoryProvider);
  if (!wanted || account == null || tokens == null) return;

  try {
    final push = ref.read(pushServiceProvider);
    // Sets up listeners only. Safe to run before any permission exists, and
    // necessary so that a permission granted in system settings starts working
    // on the next launch without another prompt.
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
///
/// Persisted separately from the OS permission because they answer different
/// questions: the OS knows whether the app *may* post a notification, this
/// knows whether the user ever *wanted* one. Keeping both means the Settings
/// switch can show the real state after someone revokes permission in system
/// settings, instead of silently claiming notifications are on.
@Riverpod(keepAlive: true)
class NotificationPreference extends _$NotificationPreference {
  static const _key = 'notifications_requested';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  /// Whether the user has ever been shown the prompt.
  ///
  /// Distinct from the stored value being false, which means they were asked
  /// and said no — a state that must not be re-prompted unbidden.
  bool get hasBeenAsked =>
      ref.read(sharedPreferencesProvider).containsKey(_key);

  /// Records a refusal made in the app, before the OS is ever involved.
  Future<void> markDeclined() => _remember(false);

  /// Turns notifications on, prompting the OS if needed.
  ///
  /// Returns whether they are actually on afterwards, which is not the same as
  /// what the user tapped: on Android 13+ a second refusal makes the system
  /// dialog stop appearing entirely, so this can return false having shown the
  /// user nothing at all. Callers say so rather than leaving a switch on.
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
