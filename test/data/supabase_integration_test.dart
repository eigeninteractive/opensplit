@Tags(['integration'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/supabase_ledger_api.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Exercises the real adapter against a local `supabase start` instance.
///
/// This is the only test that can catch a wrong RPC signature, a PostgREST
/// filter that does not mean what it looks like, a field that fails to survive
/// the JSON round trip, or an RLS policy that forbids something the app has to
/// do. The fake server in sync_test.dart proves the sync algorithm; only this
/// proves the adapter.
///
/// Skips itself when nothing is listening, so `flutter test` stays green for
/// anyone who has not started the stack.
const _apiUrl = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.'
    'CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

Future<bool> _serverIsUp() async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      54321,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late bool available;

  setUpAll(() async {
    available = await _serverIsUp();
    if (!available) {
      // ignore: avoid_print
      print('Skipping: no local Supabase on $_apiUrl. Run `supabase start`.');
    }
  });

  group('SupabaseLedgerApi against a live instance', () {
    late SupabaseClient client;
    late SupabaseLedgerApi api;
    late AppDatabase db;
    late OutboxQueue outbox;
    late DriftGroupRepository groups;
    late DriftEntryRepository entries;
    late SyncEngine sync;

    setUp(() async {
      if (!available) return;

      client = SupabaseClient(_apiUrl, _anonKey);
      api = SupabaseLedgerApi(client);

      db = AppDatabase(NativeDatabase.memory());
      outbox = OutboxQueue(db);
      groups = DriftGroupRepository(db, outbox: outbox);
      entries = DriftEntryRepository(db, outbox: outbox);
      sync = SyncEngine(db: db, api: api, outbox: outbox);
    });

    tearDown(() async {
      if (!available) return;
      await client.auth.signOut();
      await client.dispose();
      await db.close();
    });

    test('anonymous sign-in gives a real user with a profile', () async {
      if (!available) return;

      final response = await client.auth.signInAnonymously();
      final user = response.user;

      expect(user, isNotNull);
      expect(
        user!.isAnonymous,
        isTrue,
        reason: 'the JWT claim is what RLS uses to gate destructive actions',
      );

      // The handle_new_user trigger mirrors auth.users into profiles.
      final profile = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      expect(profile, isNotNull);
    });

    test('a full round trip: push a group, members and an expense', () async {
      if (!available) return;

      final user = (await client.auth.signInAnonymously()).user!;

      final created = await groups.createGroup(
        name: 'Integration ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        ownerDisplayName: 'Ravi',
        ownerProfileId: user.id,
      );
      final priya = await groups.addMember(
        created.group.id,
        displayName: 'Priya',
      );

      await entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'INR',
          amountMinor: 240000,
          description: 'Dinner at Toit',
          split: EqualSplit([created.owner.id, priya.id]),
          payerAmounts: {created.owner.id: 240000},
        ),
        createdBy: created.owner.id,
      );

      final report = await sync.syncGroup(created.group.id);
      expect(report.isClean, isTrue, reason: '$report');
      expect(
        report.pushed,
        4,
        reason: 'the group, its owner, the added member, and the entry',
      );

      // Read it back through a second, empty device.
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      final otherSync = SyncEngine(
        db: other,
        api: api,
        outbox: OutboxQueue(other),
      );

      await otherSync.syncGroup(created.group.id);

      final pulled = await DriftEntryRepository(
        other,
      ).getEntries(created.group.id);
      expect(pulled, hasLength(1));
      expect(pulled.single.description, 'Dinner at Toit');
      expect(pulled.single.isBalanced, isTrue);
      expect(pulled.single.shares, hasLength(2));
      expect(
        pulled.single.shares.first.weightMicros,
        1000000,
        reason: 'numeric(24,6) survives the round trip into integer micros',
      );
      expect(foldBalances(pulled).map((b) => b.balanceMinor).toList()..sort(), [
        -120000,
        120000,
      ]);
    });

    test('the server rejects an entry that does not balance', () async {
      if (!available) return;

      final user = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Invariant ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        ownerDisplayName: 'Ravi',
        ownerProfileId: user.id,
      );
      final entry = await entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([created.owner.id]),
          payerAmounts: {created.owner.id: 100000},
        ),
        createdBy: created.owner.id,
      );
      await sync.syncGroup(created.group.id);

      // Corrupt it the way a client bug would, then push again.
      final broken = entry.copyWith(
        shares: [entry.shares.first.copyWith(amountMinor: 1)],
      );

      await expectLater(
        api.upsertEntry(broken),
        throwsA(
          isA<Object>().having(
            (e) => '$e',
            'message',
            contains('does not balance'),
          ),
        ),
        reason: 'the deferred trigger is the backstop for every client bug',
      );
    });

    test(
      'the delta cursor does not re-deliver what it already applied',
      () async {
        if (!available) return;

        final user = (await client.auth.signInAnonymously()).user!;
        final created = await groups.createGroup(
          name: 'Cursor ${DateTime.now().microsecondsSinceEpoch}',
          defaultCurrency: 'INR',
          ownerDisplayName: 'Ravi',
          ownerProfileId: user.id,
        );
        for (var i = 0; i < 6; i++) {
          await entries.create(
            EntryDraft(
              groupId: created.group.id,
              currency: 'INR',
              amountMinor: 1000 * (i + 1),
              description: 'Expense $i',
              split: EqualSplit([created.owner.id]),
              payerAmounts: {created.owner.id: 1000 * (i + 1)},
            ),
            createdBy: created.owner.id,
          );
        }
        await sync.syncGroup(created.group.id);

        final other = AppDatabase(NativeDatabase.memory());
        addTearDown(other.close);
        // A page size below the row count forces the cursor to actually page.
        final paging = SyncEngine(
          db: other,
          api: api,
          outbox: OutboxQueue(other),
          pageSize: 2,
        );

        expect((await paging.syncGroup(created.group.id)).pulled, 6);
        expect(
          (await paging.syncGroup(created.group.id)).pulled,
          0,
          reason: 'a second pass with no changes must pull nothing',
        );
      },
    );

    test('a stranger cannot read another group', () async {
      if (!available) return;

      final user = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Private ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        ownerDisplayName: 'Ravi',
        ownerProfileId: user.id,
      );
      await entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'INR',
          amountMinor: 50000,
          split: EqualSplit([created.owner.id]),
          payerAmounts: {created.owner.id: 50000},
        ),
        createdBy: created.owner.id,
      );
      await sync.syncGroup(created.group.id);

      // A completely separate anonymous session.
      final stranger = SupabaseClient(_apiUrl, _anonKey);
      addTearDown(stranger.dispose);
      await stranger.auth.signInAnonymously();
      final strangerApi = SupabaseLedgerApi(stranger);

      expect(await strangerApi.pullGroup(created.group.id), isNull);
      expect(await strangerApi.pullMembers(created.group.id), isEmpty);
      final delta = await strangerApi.pullEntries(groupId: created.group.id);
      expect(delta.entries, isEmpty);
    });
  });
}
