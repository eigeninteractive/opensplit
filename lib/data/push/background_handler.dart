import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:opensplit_api/opensplit_api.dart' show PushData;

import '../../application/entry_notification.dart';
import '../../config.dart';
import '../auth/session_store.dart';
import '../local/database.dart';
import '../repositories/drift_activity_repository.dart';
import '../repositories/drift_currency_repository.dart';
import '../repositories/drift_entry_repository.dart';
import '../repositories/drift_group_repository.dart';
import '../repositories/drift_profile_repository.dart';
import '../sync/api_client.dart';
import '../sync/outbox_queue.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_session.dart';
import 'notification_channel.dart';
import 'push_data.dart';

/// Handles a wake-up that arrives while the app is backgrounded or not running.
bool _firebaseReady = false;

@pragma('vm:entry-point')
Future<void> handleBackgroundEntryMessage(RemoteMessage message) async {
  final push = readPushData(message.data);
  if (push == null) return;
  final PushData(:groupId, :subjectId, :kind) = push;
  if (!hasPush || !hasBackend) return;

  // Platform channels are available in this isolate, but only once the binding
  // exists — and it does not, because nothing here went through main().
  WidgetsFlutterBinding.ensureInitialized();

  AppDatabase? db;
  OutboxQueue? outbox;
  try {
    if (!_firebaseReady) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: fcmApiKey,
          appId: fcmAppId,
          messagingSenderId: fcmSenderId,
          projectId: fcmProjectId,
        ),
      );

      _firebaseReady = true;
    }

    // The stored session, read rather than resolved over the network: this
    // isolate may have woken with no connectivity at all, and asking the server
    // who it is before it can open a database would make a notification depend
    // on a round trip the sync below is about to make anyway.
    final session = await readBackgroundSession();
    if (session == null) return;
    final profileId = session.account.id;

    // A second connection to the same file — the same file, because the ledger
    // is named after the account and this isolate resolved the same account
    // from the same stored session.
    db = AppDatabase.forAccount(profileId, resumeSession: false);
    final syncing = await readSyncSession(db);
    if (!syncing.enabled) return;

    outbox = OutboxQueue(db);
    final engine = SyncEngine(
      db: db,
      // Its own client with the stored token: no Riverpod container here, and
      // no cookie jar on Android.
      client: buildApiClient(baseUrl: apiBaseUrl, token: session.token),
      outbox: outbox,
    );

    // Sync first. The notification describes what is now on the device, not
    // what a server guessed the recipient's share would be.
    final report = await engine.syncGroup(groupId);
    if (!report.isClean) return;

    final text = await composeEventNotification(
      entries: DriftEntryRepository(db, outbox: outbox),
      groups: DriftGroupRepository(db, outbox: outbox),
      profiles: DriftProfileRepository(db, outbox: outbox),
      currencies: DriftCurrencyRepository(db),
      activity: DriftActivityRepository(db),
      myProfileId: profileId,
      groupId: groupId,
      kind: kind,
      subjectId: subjectId,
    );
    if (text == null) return;
    final after = await readSyncSession(db);
    if (!after.enabled || after.epoch != syncing.epoch) return;

    final local = FlutterLocalNotificationsPlugin();
    await local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(statusBarIcon),
      ),
    );
    // Channels are per-app, not per-isolate, so this is usually a no-op — but
    // not when the app has never been opened since install and the foreground
    // path has therefore never run.
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(activityChannel);

    await local.show(
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
  } catch (_) {
    // Nothing to report to and nobody to report it to.
  } finally {
    await outbox?.dispose();
    await db?.close();
  }
}
