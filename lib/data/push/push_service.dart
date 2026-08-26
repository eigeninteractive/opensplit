import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../config.dart';
import 'background_handler.dart';
import 'notification_channel.dart';

/// Wakes the app when something changes, and lets the app say what changed.
///
/// The message from the server is data-only and carries nothing but ids. The
/// device pulls the delta, computes, and posts a LOCAL notification whose text
/// comes from the same Dart that renders the screen — so the banner and the app
/// can never disagree about an amount. A server-formatted notification would be
/// a second implementation of currency exponents, rounding and split
/// arithmetic, drifting silently from the first.
///
/// This also replaces holding a realtime subscription open. Peak concurrent
/// realtime peers is what a hosted backend bills for; a push costs nothing.
///
/// Nothing here asks for permission. [initialize] wires up messaging and
/// nothing more; [requestPermission] is separate and is only ever called from
/// an explicit user action. That split is deliberate — see the note on
/// [requestPermission].
class PushService {
  PushService({
    required this.onWake,
    required this.describe,
    required this.onTokenChanged,
    required this.onOpenRoute,
  });

  /// Pull the delta for a group. Runs before anything is shown.
  final Future<void> Function(String groupId) onWake;

  /// Produce the notification text, after the delta has landed.
  final Future<({String title, String body})?> Function(
    String groupId,
    String entryId,
  )
  describe;

  /// Register a token with the server. Called on first registration and again
  /// every time FCM rotates it.
  final Future<void> Function(String token) onTokenChanged;

  /// Navigate, because somebody tapped a notification.
  ///
  /// A notification about one expense that opens the app's front door has
  /// wasted the tap: whatever it said, the thing it said it about is now
  /// several screens away.
  final void Function(String route) onOpenRoute;

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _messages;
  StreamSubscription<RemoteMessage>? _opened;

  /// Sets everything up, or does nothing at all if push is not configured.
  ///
  /// Returning quietly matters: a build without FCM credentials is a perfectly
  /// good build of this app — sync still works, it simply waits for the next
  /// time a screen is opened.
  Future<void> initialize() async {
    if (!hasPush || _ready) return;

    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: fcmApiKey,
        appId: fcmAppId,
        messagingSenderId: fcmSenderId,
        projectId: fcmProjectId,
      ),
    );

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(statusBarIcon),
      ),
      // Tapping a notification this app posted, while it is running.
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null && route.isNotEmpty) onOpenRoute(route);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(activityChannel);

    _messages ??= FirebaseMessaging.onMessage.listen(_handle);

    // Not supported on the web, where a service worker handles background
    // delivery and cannot run Dart. See web/firebase-messaging-sw.js.
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(handleBackgroundEntryMessage);
    }

    // Tapping a notification the OS posted for a message, while the app was
    // backgrounded but alive.
    _opened ??= FirebaseMessaging.onMessageOpenedApp.listen(_open);

    // The same, but the app was not running at all and this launched it. Both
    // are needed: they cover different states and neither fires for the other.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _open(initial);

    // And the case that produced the notification in the first place: one this
    // app posted from the background isolate, tapped while the app was dead.
    final launch = await _local.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        payload != null &&
        payload.isNotEmpty) {
      onOpenRoute(payload);
    }

    // FCM rotates a registration token on reinstall, on restore to a new
    // device, and whenever it decides one is stale — after 270 days of
    // inactivity it garbage-collects them outright. Without this subscription
    // the server keeps the dead token, and the user simply stops receiving
    // anything with no error anywhere to explain it.
    _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      try {
        await onTokenChanged(token);
      } catch (_) {
        // Re-registration is retried on next launch. Push is a convenience.
      }
    });

    _ready = true;
  }

  /// Whether the OS has already granted permission to post notifications.
  Future<bool> hasPermission() async {
    if (!hasPush || !_ready) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Asks the OS for permission to post notifications.
  ///
  /// Only ever called from a deliberate user action, never on launch. Android
  /// 13+ shows the system dialog once or twice and then treats further asks as
  /// permanently denied, with system settings as the only way back. Spending
  /// that on a first-run user who has not yet created a group is spending it at
  /// the moment they have the least reason to say yes.
  Future<bool> requestPermission() async {
    if (!hasPush) return false;
    await initialize();
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// The token to register with the server, or null when push is off.
  Future<String?> token() async {
    if (!hasPush || !_ready) return null;
    return FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb && fcmVapidKey.isNotEmpty ? fcmVapidKey : null,
    );
  }

  String get platform => kIsWeb ? 'web' : 'android';

  Future<void> dispose() async {
    await _refresh?.cancel();
    await _messages?.cancel();
    await _opened?.cancel();
    _refresh = null;
    _messages = null;
    _opened = null;
  }

  /// A message that arrived while somebody was looking at the app.
  Future<void> _handle(RemoteMessage message) async {
    final groupId = message.data['group_id'];
    final entryId = message.data['entry_id'];
    if (groupId is! String || entryId is! String) return;

    // Sync first. The notification describes what is now on the device, not
    // what a server guessed the recipient's share would be.
    await onWake(groupId);

    final text = await describe(groupId, entryId);
    if (text == null) return;

    await _local.show(
      id: entryId.hashCode,
      title: text.title,
      body: text.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          activityChannelId,
          activityChannelName,
          channelDescription: activityChannelDescription,
        ),
      ),
      // Tapping it opens the entry it is about, not just the app.
      payload: '/g/$groupId/e/$entryId',
    );
  }

  void _open(RemoteMessage message) {
    final groupId = message.data['group_id'];
    final entryId = message.data['entry_id'];
    if (groupId is! String || entryId is! String) return;
    onOpenRoute('/g/$groupId/e/$entryId');
  }
}
