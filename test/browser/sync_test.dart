@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/wasm.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/open_database_web.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/data/sync/sync_gate_web.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/profile.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../data/fake_remote_ledger.dart';

void main() {
  test('storage selection accepts only safe OPFS implementations', () {
    expect(
      selectOpfsStorage(const [
        WasmStorageImplementation.opfsLocks,
        WasmStorageImplementation.opfsShared,
      ]),
      WasmStorageImplementation.opfsShared,
    );
    expect(
      selectOpfsStorage(const [
        WasmStorageImplementation.sharedIndexedDb,
        WasmStorageImplementation.opfsLocks,
      ]),
      WasmStorageImplementation.opfsLocks,
    );
    expect(
      () => selectOpfsStorage(const [
        WasmStorageImplementation.sharedIndexedDb,
        WasmStorageImplementation.unsafeIndexedDb,
        WasmStorageImplementation.inMemory,
      ]),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('Web Locks serialize tabs and aborted waiters do not run', () async {
    final name = 'sync-gate-${DateTime.now().microsecondsSinceEpoch}';
    final first = BrowserSyncGate(name: name);
    final second = BrowserSyncGate(name: name);
    final entered = Completer<void>();
    final release = Completer<void>();
    var secondEntered = false;

    final firstRun = first.synchronized(() async {
      entered.complete();
      await release.future;
      return 1;
    });
    await entered.future;
    final secondRun = second.synchronized(() async {
      secondEntered = true;
      return 2;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(secondEntered, isFalse);

    second.dispose();
    await expectLater(secondRun, throwsA(anything));
    expect(secondEntered, isFalse);
    release.complete();
    expect(await firstRun, 1);
    first.dispose();
  });

  test('OPFS sync imports groups and survives reopening', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // Flutter's test server adds isolation headers to HTML, but not workers.
    // A blob worker inherits the page's isolation and runs the shipped bytes.
    final response = await web.window
        .fetch(Uri.base.resolve('/browser/drift_worker.js').toString().toJS)
        .toDart;
    expect(response.status, 200);
    final workerSource = await response.text().toDart;
    final workerUrl = web.URL.createObjectURL(
      web.Blob(
        [workerSource].toJS,
        web.BlobPropertyBag(type: 'text/javascript'),
      ),
    );
    addTearDown(() => web.URL.revokeObjectURL(workerUrl));
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.base.resolve('/browser/sqlite3.wasm'),
      driftWorkerUri: Uri.parse(workerUrl),
    );
    final storage = selectOpfsStorage(probe.availableStorages);
    expect(storage.storageApi, WebStorageApi.opfs);
    final prefix = 'sync-test-${DateTime.now().microsecondsSinceEpoch}';
    final databases = <AppDatabase>[];
    final queues = <OutboxQueue>[];
    final engines = <SyncEngine>[];
    addTearDown(() async {
      for (final engine in engines) {
        engine.dispose();
      }
      for (final queue in queues) {
        await queue.dispose();
      }
      for (final db in databases) {
        await db.close();
      }
    });

    Future<AppDatabase> open(String device) async {
      final name = '$prefix-$device';
      final db = AppDatabase(await probe.open(storage, name));
      databases.add(db);
      return db;
    }

    final server = FakeRemoteLedger()..signedInProfileId = 'owner';
    server.seedProfile(const Profile(id: 'owner', displayName: 'Owner'));
    SyncEngine sync(AppDatabase db) {
      final queue = OutboxQueue(db);
      final engine = SyncEngine(db: db, api: server, outbox: queue);
      queues.add(queue);
      engines.add(engine);
      return engine;
    }

    Future<void> synchronize(SyncEngine engine) async {
      final report = await engine.syncEverything().timeout(
        const Duration(seconds: 10),
      );
      expect(report.isClean, isTrue, reason: '$report');
    }

    final phone = await open('phone');
    final browser = await open('browser');
    final phoneSync = sync(phone);
    final browserSync = sync(browser);
    final groups = DriftGroupRepository(phone, outbox: phoneSync.outbox);
    final entries = DriftEntryRepository(phone, outbox: phoneSync.outbox);
    final first = await groups.createGroup(
      name: 'First group',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Owner',
      creatorProfileId: 'owner',
    );
    EntryDraft draft(int amount) => EntryDraft(
      groupId: first.group.id,
      currency: 'INR',
      amountMinor: amount,
      description: 'Dinner',
      payerAmounts: {first.creator.id: amount},
      split: EqualSplit([first.creator.id]),
    );
    final entry = await entries.create(draft(100), createdBy: first.creator.id);
    await synchronize(phoneSync);
    await synchronize(browserSync);
    expect(await browser.select(browser.groups).get(), hasLength(1));
    expect(await browser.select(browser.members).get(), hasLength(1));
    expect(await browser.select(browser.entries).get(), hasLength(1));
    expect(await browser.select(browser.entrySnapshots).get(), hasLength(1));

    await groups.createGroup(
      name: 'Later group',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Owner',
      creatorProfileId: 'owner',
    );
    await entries.update(entry.id, draft(200), actorId: first.creator.id);
    await synchronize(phoneSync);
    await synchronize(browserSync);
    expect(await browser.select(browser.groups).get(), hasLength(2));
    expect(
      (await browser.select(browser.entries).get()).single.amountMinor,
      200,
    );

    browserSync.dispose();
    await browser.close();
    databases.remove(browser);
    final reopened = await open('browser');
    await synchronize(sync(reopened));
    expect(await reopened.select(reopened.groups).get(), hasLength(2));
    expect(await reopened.select(reopened.members).get(), hasLength(2));

    await entries.delete(entry.id, actorId: first.creator.id);
    await synchronize(phoneSync);
    await synchronize(engines.last);
    expect(
      (await reopened.select(reopened.entries).get()).single.deletedAt,
      isNotNull,
    );
  });
}
