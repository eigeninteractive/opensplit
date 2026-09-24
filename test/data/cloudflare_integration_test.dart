@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/data/sync/cloudflare_ledger_api.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/remote_ledger_api.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/group_event.dart';
import 'package:opensplit/domain/split/splitter.dart';

import '../harness.dart';

/// Exercises the real adapter against a local `wrangler dev`.
///
/// This is the only test that goes near the wire. `sync_test.dart` proves the
/// sync algorithm against a fake, and the Vitest suite proves the Durable
/// Object against `workerd` — but neither can catch a generated client calling
/// a path that moved, a field that does not survive the JSON round trip, a
/// refusal code mapped to the wrong [RejectionKind], or a payload key the
/// server spells one way and this app reads another.
///
/// That last one is not hypothetical: the event payload codec read
/// `amount_minor` and `entry_date` for a while after the server had started
/// sending `amountMinor` and `entryDate`, and every test passed, because both
/// halves of the codec agreed with each other.
///
/// Skips itself when nothing is listening, so `flutter test` stays green for
/// anyone who has not started the Worker. CI passes `REQUIRE_BACKEND=true`, so
/// it can never silently skip there.
///
///   cd server && npm run db:migrate:local && npm run dev
const _origin = 'http://127.0.0.1:8787';

/// A guest account, and a bearer token the Worker will accept for it.
///
/// Raw HTTP rather than a client, because the Dart half of Better Auth does not
/// exist yet — `backend_providers.dart` still passes `token: () async => null`,
/// and this is the seam where `BetterAuthService` will land. Until it does, the
/// ledger cannot be reached from Dart at all without these six lines, which is
/// itself worth knowing.
///
/// The token is read from `set-auth-token` rather than from the body. The body
/// carries a `token` field, and it is not the credential: it is the first half
/// of one, unsigned. Sending it gets a 401 that looks exactly like a session
/// problem.
Future<({String token, String profileId})> _signInAnonymously() async {
  final http = HttpClient();
  try {
    final request = await http.postUrl(
      Uri.parse('$_origin/api/auth/sign-in/anonymous'),
    );
    request.headers.contentType = ContentType.json;
    request.write('{}');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      fail('anonymous sign-in failed: ${response.statusCode} $body');
    }

    final token = response.headers.value('set-auth-token');
    if (token == null) fail('no set-auth-token header on $body');

    final user = (jsonDecode(body) as Map)['user'] as Map;
    return (token: token, profileId: user['id'] as String);
  } finally {
    http.close(force: true);
  }
}

Future<bool> _workerIsUp() async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      8787,
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
    available = await _workerIsUp();
    if (!available) {
      if (const bool.fromEnvironment('REQUIRE_BACKEND')) {
        fail('CI requires a local Worker on $_origin. Run `npm run dev`.');
      }
      // ignore: avoid_print
      print('Skipping: no Worker on $_origin. See the doc comment above.');
    }
  });

  group('CloudflareLedgerApi against a live Worker', () {
    late String profileId;
    late CloudflareLedgerApi api;
    late AppDatabase db;
    late OutboxQueue outbox;
    late DriftGroupRepository groups;
    late DriftEntryRepository entries;
    late SyncEngine sync;

    /// A second device for the same account, holding nothing.
    ///
    /// The same token, because that is the case worth proving: a person's other
    /// phone is the same session and has to find the group through discovery
    /// rather than through anything this device tells it.
    ({AppDatabase db, SyncEngine sync}) otherDevice({int? pageSize}) {
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      return (
        db: other,
        sync: SyncEngine(
          db: other,
          api: api,
          outbox: OutboxQueue(other),
          pageSize: pageSize ?? 100,
        ),
      );
    }

    setUp(() async {
      if (!available) return;

      final session = await _signInAnonymously();
      profileId = session.profileId;
      api = CloudflareLedgerApi(
        buildApiClient(baseUrl: _origin, token: () async => session.token),
      );

      db = AppDatabase(NativeDatabase.memory());
      // Reference data is phase 5's; until the Worker serves currencies, the
      // device is given them the way a first sweep would.
      await seedReferenceData(db);
      outbox = OutboxQueue(db);
      groups = DriftGroupRepository(db, outbox: outbox);
      entries = DriftEntryRepository(db, outbox: outbox);
      sync = SyncEngine(db: db, api: api, outbox: outbox);
    });

    tearDown(() async {
      if (!available) return;
      sync.dispose();
      await outbox.dispose();
      await db.close();
    });

    /// A group with Ravi and a placeholder for Priya, pushed and confirmed.
    Future<({String groupId, String ravi, String priya})> seeded() async {
      final created = await groups.createGroup(
        name: 'Goa ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: profileId,
      );
      final priya = await groups.addMember(
        created.group.id,
        displayName: 'Priya',
      );
      return (
        groupId: created.group.id,
        ravi: created.creator.id,
        priya: priya.id,
      );
    }

    test('a guest session is a session the ledger accepts', () async {
      if (!available) return;

      final me = await api.bootstrap();
      expect(me.profileId, profileId);
      expect(
        me.isAnonymous,
        isTrue,
        reason: 'what gates the destructive account actions',
      );
      expect(
        me.groupIds,
        isEmpty,
        reason: 'a brand-new account belongs to nothing',
      );
    });

    test('a full round trip, and a second device reads it back', () async {
      if (!available) return;

      final g = await seeded();
      await entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 240000,
          description: 'Dinner at Toit',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 240000},
        ),
        createdBy: g.ravi,
      );

      final report = await sync.syncGroup(g.groupId);
      expect(report.isClean, isTrue, reason: '$report');
      expect(
        report.pushed,
        4,
        reason:
            'the group, its creator, the added member and the expense. The '
            'activity line is not among them: the server writes it from the '
            'change it commits, and grants no client the right to',
      );

      // Discovery, which is the only way a second device learns this group
      // exists -- and, underneath, the only proof that the Durable Object
      // flushed its membership row into D1, since that index is what answers.
      final other = otherDevice();
      await seedReferenceData(other.db);
      expect(await other.sync.discoverGroups(), contains(g.groupId));
      await other.sync.syncGroup(g.groupId);

      final pulled = await DriftEntryRepository(other.db).getEntries(g.groupId);
      expect(pulled, hasLength(1));
      expect(pulled.single.description, 'Dinner at Toit');
      expect(pulled.single.isBalanced, isTrue);
      expect(pulled.single.shares, hasLength(2));
      expect(
        pulled.single.shares.first.weightMicros,
        1000000,
        reason: 'the weight survives the round trip as integer micros',
      );
      expect(foldBalances(pulled).map((b) => b.balanceMinor).toList()..sort(), [
        -120000,
        120000,
      ]);

      // The record, and the half only a live server can prove: nothing on this
      // device wrote it. The object took it in the same transaction as the
      // expense, resolved the actor from the session rather than from anything
      // sent, and handed it back.
      final feed = await DriftActivityRepository(
        other.db,
      ).watchGroup(g.groupId).first;

      final expense = feed.whereType<EntryChanged>().single;
      expect(expense.kind, EntryEventKind.created);
      expect(
        expense.isProvisional,
        isFalse,
        reason: 'this device wrote nothing; it only read',
      );
      expect(
        expense.actorId,
        g.ravi,
        reason: 'authorship is the member row, not the account',
      );

      expect(
        feed.whereType<MemberChanged>().map((event) => event.displayName),
        contains('Priya'),
        reason: 'a group that cannot see who arrived cannot remove them',
      );
    });

    test('an edit crosses the wire as a field-level diff', () async {
      if (!available) return;

      // Where a payload key spelled differently either side actually shows up.
      // The line is not sent: the object records what the expense looked like
      // after each change, and the reading device diffs two of those. So this
      // decodes two payloads the server wrote and subtracts them -- and a key
      // it cannot read is a feed that says somebody edited nothing, or throws.
      final g = await seeded();
      final entry = await entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 240000,
          description: 'Dinner at Toit',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 240000},
        ),
        createdBy: g.ravi,
      );
      await sync.syncGroup(g.groupId);

      await entries.update(
        entry.id,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 300000,
          description: 'Dinner at Toit',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 300000},
        ),
        actorId: g.ravi,
      );
      expect((await sync.syncGroup(g.groupId)).isClean, isTrue);

      final other = otherDevice();
      await seedReferenceData(other.db);
      await other.sync.syncGroup(g.groupId);

      final edited =
          (await DriftActivityRepository(other.db).watchGroup(g.groupId).first)
              .whereType<EntryChanged>()
              .where((event) => event.kind == EntryEventKind.edited);
      expect(edited, hasLength(1));

      final amount = edited.single.changes.singleWhere(
        (change) => change.field == 'amount_minor',
      );
      expect(amount.from, '240000');
      expect(amount.to, '300000');
      expect(
        edited.single.changes.map((change) => change.field),
        isNot(contains('description')),
        reason: 'the description did not move, so it is not in the diff',
      );
    });

    test('an expense that does not add up is refused outright', () async {
      if (!available) return;

      final g = await seeded();
      final entry = await entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([g.ravi]),
          payerAmounts: {g.ravi: 100000},
        ),
        createdBy: g.ravi,
      );
      await sync.syncGroup(g.groupId);

      // Corrupted the way a client bug would, then pushed. The device cannot
      // reach this state through its own repository, which is the point: the
      // object is the backstop for a client this server does not control.
      await expectLater(
        api.pushEntry(
          entry.copyWith(shares: [entry.shares.first.copyWith(amountMinor: 1)]),
        ),
        throwsA(
          isA<RemoteRejected>()
              .having((e) => e.kind, 'kind', RejectionKind.permanent)
              .having((e) => e.code, 'code', 'unbalanced'),
        ),
      );
    });

    test('a stale edit is refused only when it moves money', () async {
      if (!available) return;

      final g = await seeded();
      final entry = await entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          description: 'Dinner',
          split: EqualSplit([g.ravi]),
          payerAmounts: {g.ravi: 100000},
        ),
        createdBy: g.ravi,
      );
      await sync.syncGroup(g.groupId);

      final base = (await entries.getEntry(entry.id))!;
      expect(base.seq, isNotNull, reason: 'the push adopted a sequence number');

      Entry at(int amount) => base.copyWith(
        amountMinor: amount,
        payers: [base.payers.first.copyWith(amountMinor: amount)],
        shares: [base.shares.first.copyWith(amountMinor: amount)],
      );

      // Somebody else's edit lands first, moving the amount and the share.
      final theirs = await api.pushEntry(at(150000));
      expect(theirs.amountMinor, 150000);
      expect(theirs.seq, greaterThan(base.seq!));

      // And now the edit composed against the version they replaced. Only this
      // proves the adapter sends `seq` inside the entry and maps `stale_base`
      // to the one kind a person can resolve -- the Vitest suite proves the
      // object refuses, and the fake proves the outbox parks it, but neither
      // goes near the wire between them.
      await expectLater(
        api.pushEntry(at(200000)),
        throwsA(
          isA<RemoteRejected>()
              .having((e) => e.kind, 'kind', RejectionKind.stale)
              .having((e) => e.code, 'code', 'stale_base'),
        ),
      );

      // The same stale base, leaving the money exactly where the server has
      // it, is not refused: arbitrating a typo would cost two people a
      // decision for nothing.
      final prose = await api.pushEntry(
        at(150000).copyWith(description: 'Renamed', seq: base.seq),
      );
      expect(prose.description, 'Renamed');
      expect(prose.amountMinor, 150000);
    });

    test('deleting carries the exact version, and propagates', () async {
      if (!available) return;

      final g = await seeded();
      final entry = await entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 60000,
          description: 'Cancelled',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 60000},
        ),
        createdBy: g.ravi,
      );
      await sync.syncGroup(g.groupId);
      final stored = (await entries.getEntry(entry.id))!;

      // A deletion always moves money, so unlike a prose edit it must name the
      // version the device last saw, and a wrong one is a refusal rather than
      // a licence.
      await expectLater(
        api.deleteEntry(
          groupId: g.groupId,
          entryId: entry.id,
          baseSeq: stored.seq! - 1,
        ),
        throwsA(
          isA<RemoteRejected>().having(
            (e) => e.kind,
            'kind',
            RejectionKind.stale,
          ),
        ),
      );

      final deleted = await api.deleteEntry(
        groupId: g.groupId,
        entryId: entry.id,
        baseSeq: stored.seq!,
      );
      expect(deleted.isDeleted, isTrue);

      // A soft delete, which is why it can propagate at all: a hard one would
      // simply stop appearing in the page and live forever on every device
      // that had already synced it.
      final other = otherDevice();
      await seedReferenceData(other.db);
      await other.sync.syncGroup(g.groupId);

      final theirs = await DriftEntryRepository(
        other.db,
      ).getEntries(g.groupId, includeDeleted: true);
      expect(theirs.single.isDeleted, isTrue);
      expect(
        foldBalances(
          await DriftEntryRepository(other.db).getEntries(g.groupId),
        ),
        isEmpty,
        reason: 'a deleted expense owes nobody anything',
      );
    });

    test('the cursor pages, and then pulls nothing', () async {
      if (!available) return;

      final g = await seeded();
      for (var i = 0; i < 6; i++) {
        await entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 1000 * (i + 1),
            description: 'Expense $i',
            split: EqualSplit([g.ravi, g.priya]),
            payerAmounts: {g.ravi: 1000 * (i + 1)},
          ),
          createdBy: g.ravi,
        );
      }
      expect((await sync.syncGroup(g.groupId)).isClean, isTrue);

      // A page size below the change count forces the cursor to actually page
      // against the real object, which is where an off-by-one costs a row.
      final other = otherDevice(pageSize: 2);
      await seedReferenceData(other.db);

      final first = await other.sync.syncGroup(g.groupId);
      expect(first.isClean, isTrue, reason: '$first');
      expect(first.pulled, 6);

      final second = await other.sync.syncGroup(g.groupId);
      expect(second.isClean, isTrue, reason: '$second');
      expect(
        second.pulled,
        0,
        reason: 'a second pass with no changes must pull nothing',
      );
    });

    test('a member rename reaches the other device', () async {
      if (!available) return;

      final g = await seeded();
      await sync.syncGroup(g.groupId);

      await groups.renameMember(g.priya, 'Priya S');
      expect((await sync.syncGroup(g.groupId)).isClean, isTrue);

      final other = otherDevice();
      await seedReferenceData(other.db);
      await other.sync.syncGroup(g.groupId);

      final members = await DriftGroupRepository(
        other.db,
      ).watchMembers(g.groupId).first;
      expect(members.firstWhere((m) => m.id == g.priya).displayName, 'Priya S');

      // And the rename is on the record, carrying what it was before -- which
      // is the payload shape a member event uses and an expense does not.
      final renamed =
          (await DriftActivityRepository(other.db).watchGroup(g.groupId).first)
              .whereType<MemberChanged>()
              .where((event) => event.kind == GroupEventKind.memberRenamed);
      expect(renamed.single.displayName, 'Priya S');
      expect(renamed.single.previousName, 'Priya');
    });
  });
}
