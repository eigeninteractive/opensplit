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
import 'package:opensplit/data/sync/sync_gate_web.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

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

  test('an OPFS ledger and its unsent writes survive reopening', () async {
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
    addTearDown(() async {
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

    final phone = await open('phone');
    await phone
        .into(phone.currencies)
        .insert(
          CurrenciesCompanion.insert(code: 'INR', exponent: 2, name: 'Rupee'),
        );
    final outbox = OutboxQueue(phone);
    queues.add(outbox);
    final created = await DriftGroupRepository(phone, outbox: outbox)
        .createGroup(
          name: 'First group',
          defaultCurrency: 'INR',
          creatorDisplayName: 'Owner',
          creatorProfileId: 'owner',
        );
    await DriftEntryRepository(phone, outbox: outbox).create(
      EntryDraft(
        groupId: created.group.id,
        currency: 'INR',
        amountMinor: 100,
        description: 'Dinner',
        payerAmounts: {created.creator.id: 100},
        split: EqualSplit([created.creator.id]),
      ),
      createdBy: created.creator.id,
    );

    await outbox.dispose();
    queues.remove(outbox);
    await phone.close();
    databases.remove(phone);

    // What a reload finds: the ledger, its unsent writes and its feed line.
    final reopened = await open('phone');
    expect(await reopened.select(reopened.groups).get(), hasLength(1));
    expect(await reopened.select(reopened.entries).get(), hasLength(1));
    expect(await reopened.select(reopened.groupEvents).get(), hasLength(1));
    expect(await OutboxQueue(reopened).pendingCount(), 3);
  });
}
