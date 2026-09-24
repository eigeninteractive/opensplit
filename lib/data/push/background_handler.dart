import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../application/entry_notification.dart';
import '../../domain/models/group_event.dart';
import '../../config.dart';
import '../auth/session_store.dart';
import '../local/database.dart';
import '../repositories/drift_activity_repository.dart';
import '../repositories/drift_currency_repository.dart';
import '../repositories/drift_entry_repository.dart';
import '../repositories/drift_group_repository.dart';
import '../repositories/drift_profile_repository.dart';
import '../sync/api_client.dart';
import '../sync/cloudflare_ledger_api.dart';
import '../sync/outbox_queue.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_session.dart';
import 'notification_channel.dart';

/// Handles a wake-up that arrives while the app is backgrounded or not running.
///
/// Android only. Everything below has to be rebuilt from nothing because this
/// runs in a background isolate with its own memory: no Riverpod container, no
/// open database, no Firebase, no session. The alternative — doing
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
/// An isolate is reused across messages, and `Firebase.initializeApp` throws
/// when called a second time. Without this the first expense of a burst
/// notifies and the rest fail silently, which is a hard thing to notice and a
/// harder one to reproduce.
bool _firebaseReady = false;

@pragma('vm:entry-point')
Future<void> handleBackgroundEntryMessage(RemoteMessage message) async {
  final groupId = message.data['group_id'];
  final subjectId = message.data['subject_id'];
  final kind = GroupEventKind.parse(message.data['kind'] as String? ?? '');
  if (groupId is! String || subjectId is! String || kind == null) return;
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
    //
    // It never refreshes or rotates anything. The foreground owns the session,
    // and a second writer could otherwise restore one after a sign-out.
    final session = await readBackgroundSession();
    if (session == null) return;
    final profileId = session.account.id;

    // A second connection to the same file — the same file, because the ledger
    // is named after the account and this isolate resolved the same account
    // from the same stored session. SQLite is built for this: the database is
    // in WAL mode with a busy timeout, set in AppDatabase, and the app is by
    // definition idle while this runs.
    db = AppDatabase.forAccount(profileId, resumeSession: false);
    final syncing = await readSyncSession(db);
    if (!syncing.enabled) return;

    outbox = OutboxQueue(db);
    final engine = SyncEngine(
      db: db,
      // The background isolate builds its own client: it has no Riverpod
      // container, and the foreground's is not reachable from here. The token
      // is the one just read — this is Android, where there is no cookie jar an
      // isolate could borrow.
      api: CloudflareLedgerApi(
        buildApiClient(baseUrl: apiBaseUrl, token: () async => session.token),
      ),
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
