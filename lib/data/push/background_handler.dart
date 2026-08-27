import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/entry_notification.dart';
import '../../config.dart';
import '../local/database.dart';
import '../repositories/drift_activity_repository.dart';
import '../repositories/drift_currency_repository.dart';
import '../repositories/drift_entry_repository.dart';
import '../repositories/drift_group_repository.dart';
import '../sync/outbox_queue.dart';
import '../sync/supabase_ledger_api.dart';
import '../sync/sync_engine.dart';
import 'notification_channel.dart';

/// Handles a wake-up that arrives while the app is backgrounded or not running.
///
/// Android only. Everything below has to be rebuilt from nothing because this
/// runs in a background isolate with its own memory: no Riverpod container, no
/// open database, no Firebase, no Supabase client. The alternative — doing
/// nothing here, which is what a stub background handler amounts to — means the
/// only notifications anyone ever sees are the ones that arrive while they are
/// already looking at the app, which is the one case a notification is not for.
///
/// The message itself carries nothing but ids. The device pulls the delta and
/// then says what happened, using the same Dart the screens use, so a banner
/// and the app can never disagree about an amount. That is the whole reason
/// this is worth the cost of a second database connection.
///
/// On the web there is no equivalent: a service worker cannot run Dart, so
/// `web/firebase-messaging-sw.js` stays silent and web push only wakes the tab.
///
/// Failures are swallowed. A notification that cannot be built is not worth
/// crashing a background isolate over, and there is nobody to show an error to.
/// Whether this isolate has already stood the SDKs up.
///
/// An isolate is reused across messages, and both `Firebase.initializeApp` and
/// `Supabase.initialize` throw when called a second time. Without this the
/// first expense of a burst notifies and the rest fail silently, which is a
/// hard thing to notice and a harder one to reproduce.
bool _isolateReady = false;

@pragma('vm:entry-point')
Future<void> handleBackgroundEntryMessage(RemoteMessage message) async {
  final groupId = message.data['group_id'];
  final entryId = message.data['entry_id'];
  if (groupId is! String || entryId is! String) return;
  if (!hasPush || !hasBackend) return;

  // Platform channels are available in this isolate, but only once the binding
  // exists — and it does not, because nothing here went through main().
  WidgetsFlutterBinding.ensureInitialized();

  AppDatabase? db;
  try {
    if (!_isolateReady) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: fcmApiKey,
          appId: fcmAppId,
          messagingSenderId: fcmSenderId,
          projectId: fcmProjectId,
        ),
      );

      // A second Supabase client, reading the session the app persisted.
      // Without it every request is anonymous and row-level security refuses
      // the pull.
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );
      _isolateReady = true;
    }

    final client = Supabase.instance.client;
    final profileId = client.auth.currentUser?.id;
    if (profileId == null) return;

    // A second connection to the same file — the same file, because the ledger
    // is named after the account and this isolate resolved the same account
    // from the same stored session. SQLite is built for this: the database is
    // in WAL mode with a busy timeout, set in AppDatabase, and the app is by
    // definition idle while this runs.
    db = AppDatabase.forAccount(profileId);

    final outbox = OutboxQueue(db);
    final engine = SyncEngine(
      db: db,
      api: SupabaseLedgerApi(client),
      outbox: outbox,
    );

    // Sync first. The notification describes what is now on the device, not
    // what a server guessed the recipient's share would be.
    await engine.syncGroup(groupId);

    final text = await composeEntryNotification(
      entries: DriftEntryRepository(db, outbox: outbox),
      groups: DriftGroupRepository(db, outbox: outbox),
      currencies: DriftCurrencyRepository(db),
      activity: DriftActivityRepository(db),
      myProfileId: profileId,
      groupId: groupId,
      entryId: entryId,
    );
    if (text == null) return;

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
      payload: entryNotificationRoute(groupId, entryId),
    );
  } catch (_) {
    // Nothing to report to and nobody to report it to.
  } finally {
    await db?.close();
  }
}
