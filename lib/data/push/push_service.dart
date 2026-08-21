import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../config.dart';

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
class PushService {
  PushService({required this.onWake, required this.describe});

  /// Pull the delta for a group. Runs before anything is shown.
  final Future<void> Function(String groupId) onWake;

  /// Produce the notification text, after the delta has landed.
  final Future<({String title, String body})?> Function(
    String groupId,
    String entryId,
  )
  describe;

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationChannel(
    'opensplit_activity',
    'Group activity',
    description: 'New expenses and settlements in your groups.',
    importance: Importance.defaultImportance,
  );

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
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    await FirebaseMessaging.instance.requestPermission();
    FirebaseMessaging.onMessage.listen(_handle);
    FirebaseMessaging.onBackgroundMessage(_backgroundStub);

    _ready = true;
  }

  /// The token to register with the server, or null when push is off.
  Future<String?> token() async {
    if (!hasPush || !_ready) return null;
    return FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb && fcmVapidKey.isNotEmpty ? fcmVapidKey : null,
    );
  }

  String get platform => kIsWeb ? 'web' : 'android';

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
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
        ),
      ),
      // Tapping it should open the entry it is about, not just the app.
      payload: '/g/$groupId/e/$entryId',
    );
  }
}

/// Registered so Android does not drop messages that arrive while the app is
/// not running. The work happens when the app next opens: doing a full sync in
/// a background isolate would need a second database connection and its own
/// copy of every provider, for a notification nobody is looking at yet.
@pragma('vm:entry-point')
Future<void> _backgroundStub(RemoteMessage message) async {}
