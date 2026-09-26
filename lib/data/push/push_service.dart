import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:opensplit_api/opensplit_api.dart' show EventKind, PushData;

import '../../config.dart';
import 'background_handler.dart';
import 'notification_channel.dart';
import 'push_data.dart';

/// Wakes the app when something changes, and lets the app say what changed.
class PushService {
  PushService({
    required this.onWake,
    required this.describe,
    required this.onTokenChanged,
    required this.onOpenGroup,
    required this.isEnabled,
  });

  /// Pull the delta for a group. Runs before anything is shown.
  final Future<void> Function(String groupId) onWake;

  /// Produce the notification text, after the delta has landed.
  final Future<({String title, String body})?> Function(
    String groupId,
    EventKind kind,
    String subjectId,
  )
  describe;

  /// Register a token with the server. Called on first registration and again
  /// every time FCM rotates it.
  final Future<void> Function(String token) onTokenChanged;

  /// Opens and refreshes the affected group after a notification tap.
  final void Function(String groupId) onOpenGroup;

  /// Whether the current account still wants notifications on this device.
  final bool Function() isEnabled;

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _initializing;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _messages;
  StreamSubscription<RemoteMessage>? _opened;

  /// Sets everything up, or does nothing at all if push is not configured.
  Future<void> initialize() {
    if (!hasPush || _ready) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: fcmApiKey,
        appId: fcmAppId,
        messagingSenderId: fcmSenderId,
        projectId: fcmProjectId,
      ),
    );

    if (!kIsWeb) {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(statusBarIcon),
        ),
        // Tapping a notification this app posted, while it is running.
        onDidReceiveNotificationResponse: (response) {
          final groupId = response.payload;
          if (groupId != null && groupId.isNotEmpty) onOpenGroup(groupId);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(activityChannel);
    }

    _messages ??= FirebaseMessaging.onMessage.listen((message) async {
      try {
        await _handle(message);
      } catch (error, stackTrace) {
        developer.log(
          'Could not process a push wake',
          name: 'opensplit.push',
          error: error,
          stackTrace: stackTrace,
          level: 900,
        );
      }
    });

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
    final launch = kIsWeb
        ? null
        : await _local.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        payload != null &&
        payload.isNotEmpty) {
      onOpenGroup(payload);
    }

    // FCM rotates a registration token on reinstall, on restore to a new
    // device, and whenever it decides one is stale — after 270 days of
    // inactivity it garbage-collects them outright.
    _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      if (!isEnabled()) return;
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
      // The app has one worker. Registering a second script with the default
      // /app/ scope would replace the offline worker as soon as push is enabled.
      serviceWorkerScriptPath: kIsWeb ? 'sw.js' : null,
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
    if (!isEnabled()) return;
    final push = readPushData(message.data);
    if (push == null) return;
    final PushData(:groupId, :subjectId, :kind) = push;

    // Sync first. The notification describes what is now on the device, not
    // what a server guessed the recipient's share would be.
    await onWake(groupId);

    // Web messages wake the tab. Local notifications are Android-only.
    if (kIsWeb || !isEnabled()) return;

    final text = await describe(groupId, kind, subjectId);
    if (text == null || !isEnabled()) return;

    await _local.show(
      // Keyed on the subject, so five edits to one expense replace each other
      // in the shade rather than stacking into five banners about one dinner.
      id: subjectId.hashCode,
      title: text.title,
      body: text.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          activityChannelId,
          activityChannelName,
          channelDescription: activityChannelDescription,
        ),
      ),
      payload: groupId,
    );
  }

  void _open(RemoteMessage message) {
    final push = readPushData(message.data);
    if (push != null) onOpenGroup(push.groupId);
  }
}
