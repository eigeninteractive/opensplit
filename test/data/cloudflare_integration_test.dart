@Tags(['integration'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/auth/better_auth_service.dart';
import 'package:opensplit/data/auth/session_store.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/push/cloudflare_device_token_repository.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/repositories/drift_profile_repository.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/data/sync/invites.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/remote_ledger_api.dart';
import 'package:opensplit/data/sync/wire.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/group_event.dart';
import 'package:opensplit/domain/repositories/auth_service.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
///
/// `--dart-define=API_BASE_URL=...` points it somewhere else, which is worth
/// having for the ordinary reason: 8787 is wrangler's default, so anybody with
/// a second Worker project open already has it taken.
const _origin = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

/// Everything a signed-in device holds, wired the way the providers wire it.
///
/// One HTTP client behind all four, because the session is a property of the
/// connection: a second client would carry a second session and the two would
/// disagree the moment either changed. Building it here the same way
/// `backend_providers.dart` does is what makes this a test of the composition
/// rather than of four objects that happen to share a base URL.
class _Device {
  _Device._({
    required this.auth,
    required this.ledger,
    required this.invites,
    required this.devices,
    required this.account,
  });

  /// Signs in as a guest, and comes back holding a session.
  ///
  /// A real [BetterAuthService] rather than raw HTTP, so the token plumbing is
  /// under test too — and it is the part most easily got wrong. Better Auth
  /// puts the credential in the `set-auth-token` **header**; the `token` field
  /// in the response body is the unsigned first half of one, and sending that
  /// gets a 401 that looks exactly like a session problem.
  static Future<_Device> guest() async {
    SharedPreferences.setMockInitialValues({});
    final sessions = SessionStore(await SharedPreferences.getInstance());

    final client = buildApiClient(
      baseUrl: _origin,
      token: () async => sessions.read()?.token,
    );
    final auth = BetterAuthService(client: client, sessions: sessions);
    await auth.signInAnonymously();

    return _Device._(
      auth: auth,
      ledger: CloudflareLedgerApi(client),
      invites: Invites(client),
      devices: CloudflareDeviceTokenRepository(client),
      account: auth,
    );
  }

  final BetterAuthService auth;
  final CloudflareLedgerApi ledger;
  final Invites invites;
  final CloudflareDeviceTokenRepository devices;
  final AuthService account;

  String get profileId => auth.currentUser!.id;
}

Future<bool> _workerIsUp() async {
  final origin = Uri.parse(_origin);
  try {
    final socket = await Socket.connect(
      origin.host,
      origin.port,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Whether a Worker answered at [_origin], decided once in `setUpAll`.
///
/// Top level rather than a local, because the serving group below is a
/// separate function: the two halves of this file test the same running
/// Worker and have to agree about whether there is one.
late bool _available;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() async {
    _available = await _workerIsUp();
    if (!_available) {
      if (const bool.fromEnvironment('REQUIRE_BACKEND')) {
        fail('CI requires a local Worker on $_origin. Run `npm run dev`.');
      }
      // ignore: avoid_print
      print('Skipping: no Worker on $_origin. See the doc comment above.');
    }
  });

  group('CloudflareLedgerApi against a live Worker', () {
    late String profileId;
    late CloudflareLedgerApi remote;

    Future<api.Entry> push(Entry entry) =>
        remote.upsertEntry(entry.groupId, entry.toInput());
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
          remote: remote,
          outbox: OutboxQueue(other),
          pageSize: pageSize ?? 100,
        ),
      );
    }

    setUp(() async {
      if (!_available) return;

      final device = await _Device.guest();
      profileId = device.profileId;
      remote = device.ledger;

      db = AppDatabase(NativeDatabase.memory());
      // Reference data is phase 5's; until the Worker serves currencies, the
      // device is given them the way a first sweep would.
      await seedReferenceData(db);
      outbox = OutboxQueue(db);
      groups = DriftGroupRepository(db, outbox: outbox);
      entries = DriftEntryRepository(db, outbox: outbox);
      sync = SyncEngine(db: db, remote: remote, outbox: outbox);
    });

    tearDown(() async {
      if (!_available) return;
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
      if (!_available) return;

      final me = await remote.bootstrap();
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
      if (!_available) return;

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
      if (!_available) return;

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
      if (!_available) return;

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
        push(
          entry.copyWith(shares: [entry.shares.first.copyWith(amountMinor: 1)]),
        ),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.retry, 'retry', api.Retry.permanent)
              .having((e) => e.code?.value, 'code', 'unbalanced'),
        ),
      );
    });

    test('a stale edit is refused only when it moves money', () async {
      if (!_available) return;

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
      final theirs = await push(at(150000));
      expect(theirs.amountMinor, 150000);
      expect(theirs.seq, greaterThan(base.seq!));

      // And now the edit composed against the version they replaced. Only this
      // proves the adapter sends `seq` inside the entry and maps `stale_base`
      // to the one kind a person can resolve -- the Vitest suite proves the
      // object refuses, and the fake proves the outbox parks it, but neither
      // goes near the wire between them.
      await expectLater(
        push(at(200000)),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.retry, 'retry', api.Retry.stale)
              .having((e) => e.code?.value, 'code', 'stale_base'),
        ),
      );

      // The same stale base, leaving the money exactly where the server has
      // it, is not refused: arbitrating a typo would cost two people a
      // decision for nothing.
      final prose = await push(
        at(150000).copyWith(description: 'Renamed', seq: base.seq),
      );
      expect(prose.description, 'Renamed');
      expect(prose.amountMinor, 150000);
    });

    test('deleting carries the exact version, and propagates', () async {
      if (!_available) return;

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
        remote.deleteEntry(g.groupId, entry.id, baseSeq: stored.seq! - 1),
        throwsA(
          isA<ApiFailure>().having((e) => e.retry, 'retry', api.Retry.stale),
        ),
      );

      final deleted = await remote.deleteEntry(
        g.groupId,
        entry.id,
        baseSeq: stored.seq!,
      );
      expect(deleted.deletedAt, isNotNull);

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
      if (!_available) return;

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
      if (!_available) return;

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
              .where((event) => event.kind == EventKind.memberRenamed);
      expect(renamed.single.displayName, 'Priya S');
      expect(renamed.single.previousName, 'Priya');
    });
  });

  /// The two responses that are the same for everybody.
  ///
  /// No session anywhere in this group, deliberately: reference data and rates
  /// are public, and a test that signed in first would not notice if they
  /// stopped being.
  group('reference data and rates against a live Worker', () {
    late CloudflareLedgerApi public;

    setUp(() {
      if (!_available) return;
      public = CloudflareLedgerApi(
        buildApiClient(baseUrl: _origin, token: () async => null),
      );
    });

    test('the reference lists arrive whole, with no session', () async {
      if (!_available) return;

      final reference = await public.reference();

      // The exponent is the one field here that is not decoration: every
      // amount in this app is an integer of minor units, so a wrong exponent
      // is a factor-of-a-thousand error in a balance rather than a formatting
      // quirk.
      final jpy = reference.currencies.firstWhere((c) => c.code == 'JPY');
      expect(jpy.exponent, 0);
      final kwd = reference.currencies.firstWhere((c) => c.code == 'KWD');
      expect(kwd.exponent, 3);

      // Category ids are written onto entries, so one invented by a device
      // would point at a category the server has never heard of.
      expect(reference.categories, isNotEmpty);
      expect(
        reference.categories.every((c) => c.id.isNotEmpty && c.icon.isNotEmpty),
        isTrue,
      );
    });

    test('a device learns currencies before it can make a group', () async {
      if (!_available) return;

      // The ordering this exists for: `groups.default_currency` references
      // `currencies`, so a device that has not swept cannot create a group at
      // all. This is that sweep, through the engine, into an empty database.
      final device = AppDatabase(NativeDatabase.memory());
      addTearDown(device.close);

      final queue = OutboxQueue(device);
      addTearDown(queue.dispose);
      final engine = SyncEngine(db: device, remote: public, outbox: queue);
      addTearDown(engine.dispose);

      expect(await device.select(device.currencies).get(), isEmpty);
      await engine.pullReferenceData();

      final learned = await device.select(device.currencies).get();
      expect(learned.map((row) => row.code), contains('INR'));
      expect(await device.select(device.categories).get(), isNotEmpty);
    });

    test('rates arrive against USD, stamped with who published them', () async {
      if (!_available) return;

      // Needs the cron to have run against a live provider, which is not this
      // test's business to arrange: an empty page is a correct answer for a
      // Worker started a moment ago, and asserting on a number of rates would
      // make this fail for a reason that is not about the client.
      final rates = (await public.fxRates(since: '2020-01-01')).rates;
      if (rates.isEmpty) {
        markTestSkipped('no rates published; run the 0 4 * * * trigger first');
        return;
      }

      final usd = rates.where((rate) => rate.currency == 'USD');
      expect(
        usd.every((rate) => rate.rate == 1),
        isTrue,
        reason: 'the pivot is stored as exactly 1, so any pair is a division',
      );

      // The source is stamped onto any expense converted with this rate, so a
      // converted amount can always say where its number came from.
      expect(rates.every((rate) => rate.source_.isNotEmpty), isTrue);
      expect(rates.every((rate) => rate.rate > 0), isTrue);
      expect(
        rates.every(
          (rate) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rate.asOf),
        ),
        isTrue,
      );
    });

    test('a backfill is fire and forget, and does not refuse', () async {
      if (!_available) return;

      // The client cannot act on the answer either way — the rate arrives on a
      // later sync or it does not — so what matters is that asking never
      // throws into the editor that asked.
      await public.requestFxBackfill(
        api.FxBackfillRequest(asOf: '2026-08-14', currency: 'INR'),
      );
      // Twice, because six devices in one group sync the same backdated
      // expense within a second of each other.
      await public.requestFxBackfill(
        api.FxBackfillRequest(asOf: '2026-08-14', currency: 'INR'),
      );
    });

    test('a malformed date is refused rather than guessed at', () async {
      if (!_available) return;

      await expectLater(
        public.fxRates(since: 'last-tuesday'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.retry,
            'retry',
            api.Retry.permanent,
          ),
        ),
      );
    });
  });

  /// Everything an account is, over the wire.
  ///
  /// Deliberately not built on the ledger group above: nothing here needs a
  /// local database, and the things worth proving are between two accounts —
  /// a link minted by one and spent by the other, a profile one can see and a
  /// stranger cannot, a deletion that leaves somebody else's ledger alone.
  group('accounts, links and profiles against a live Worker', () {
    late _Device ravi;

    setUp(() async {
      if (!_available) return;
      ravi = await _Device.guest();
    });

    /// A group with Ravi in it and one placeholder waiting for a friend.
    Future<({String groupId, String priya})> seededGroup(_Device host) async {
      final groupId = 'g${DateTime.now().microsecondsSinceEpoch}';
      await host.ledger.createGroup(
        Group(
          id: groupId,
          name: 'Goa trip',
          defaultCurrency: 'INR',
          isDirect: false,
          simplifyDebts: true,
          createdBy: '$groupId-ravi',
          createdAt: DateTime.now().toUtc(),
        ).toCreate(
          Member(
            id: '$groupId-ravi',
            groupId: groupId,
            profileId: host.profileId,
            displayName: 'Ravi',
            joinedAt: DateTime.now().toUtc(),
          ),
        ),
      );

      final priya = await host.ledger.addMember(
        groupId,
        api.MemberCreate(id: '$groupId-priya', displayName: 'Priya'),
      );
      return (groupId: groupId, priya: priya.id);
    }

    test('an invite is previewable with no session, then spendable', () async {
      if (!_available) return;

      final g = await seededGroup(ravi);
      final invite = await ravi.invites.create(g.groupId, g.priya);

      // No session at all. This is the ordering the whole flow turns on:
      // somebody who already has an account sees what they were sent before
      // anything claims the slot on their behalf.
      final anonymous = Invites(
        buildApiClient(baseUrl: _origin, token: () async => null),
      );
      final preview = await anonymous.preview(invite.token);
      expect(preview, isNotNull);
      expect(preview!.groupName, 'Goa trip');
      expect(preview.memberName, 'Priya');
      expect(preview.inviterName, 'Ravi');
      expect(preview.isRedeemed || preview.isExpired, isFalse);

      final priya = await _Device.guest();
      final claimed = await priya.invites.join(invite.token);

      // The place was claimed, not duplicated. One column changed on a row
      // that already had balances and history, which is the entire payoff of
      // members being group-scoped rather than accounts.
      expect(claimed.member.id, g.priya);
      expect(claimed.groupId, g.groupId, reason: 'the token said which group');
      expect(claimed.member.profileId, priya.profileId);
      expect(claimed.member.displayName, 'Priya');

      // And the name travelled the other way: a guest has none of its own, so
      // it adopts the one a friend typed on the placeholder.
      final mine = (await priya.ledger.profilesByIds([
        priya.profileId,
      ])).profiles;
      expect(mine.single.displayName, 'Priya');
    });

    test('a spent link says so rather than saying nothing', () async {
      if (!_available) return;

      final g = await seededGroup(ravi);
      final invite = await ravi.invites.create(g.groupId, g.priya);
      await (await _Device.guest()).invites.join(invite.token);

      // Three different reasons a link does not work, and a screen that shows
      // "invalid link" for all of them tells nobody what to do next.
      final second = await _Device.guest();
      await expectLater(
        second.invites.join(invite.token),
        throwsA(isA<ApiFailure>()),
      );

      final preview = await second.invites.preview(invite.token);
      expect(preview!.isRedeemed, isTrue);
    });

    test('an open link offers the places already typed in', () async {
      if (!_available) return;

      final g = await seededGroup(ravi);
      final link = await ravi.invites.createGroupLink(g.groupId);
      expect(
        (await ravi.invites.currentGroupLink(g.groupId))?.token,
        link.token,
      );

      final arriving = await _Device.guest();
      final target = await arriving.invites.preview(link.token);
      expect(target?.isOpenLink, isTrue);

      final places = await arriving.invites.placeholders(link.token);
      expect(places.single.memberId, g.priya);
      expect(places.single.displayName, 'Priya');

      // Claiming one is what stops a group of six becoming a group of twelve
      // when a single link is pasted into a chat.
      final joined = await arriving.invites.join(link.token, memberId: g.priya);
      expect(joined.member.id, g.priya);
      expect(await arriving.invites.placeholders(link.token), isEmpty);
    });

    test('somebody nobody typed in arrives under their own name', () async {
      if (!_available) return;

      final g = await seededGroup(ravi);
      final link = await ravi.invites.createGroupLink(g.groupId);

      final stranger = await _Device.guest();
      final joined = await stranger.invites.join(
        link.token,
        displayName: 'Zara',
      );
      expect(joined.member.displayName, 'Zara');
      expect(
        joined.member.id,
        isNot(g.priya),
        reason: 'a new place, not a claim',
      );

      // And it is a name, not a sentinel. A guest declining every placeholder
      // has one nowhere — not on their account, not on a slot — so the server
      // refuses rather than inventing "Someone", and the join screen asks.
      final nameless = await _Device.guest();
      await expectLater(
        nameless.invites.join(link.token),
        throwsA(isA<ApiFailure>()),
      );

      // Whereas an account that already has a name needs no asking.
      final named = await _Device.guest();
      await named.ledger.updateProfile(
        api.ProfileUpdate(displayName: 'Meera', upiVpa: null),
      );
      expect(
        (await named.invites.join(link.token)).member.displayName,
        'Meera',
      );
    });

    test('revoking leaves the link able to explain itself', () async {
      if (!_available) return;

      final g = await seededGroup(ravi);
      final link = await ravi.invites.createGroupLink(g.groupId);
      await ravi.invites.revokeGroupLink(g.groupId);

      expect(await ravi.invites.currentGroupLink(g.groupId), isNull);

      // Turned off, not never valid. Somebody tapping a link a friend shared
      // last month deserves the first answer, and it is only reachable because
      // the index keeps the token while the group's object still holds it.
      final preview = await ravi.invites.preview(link.token);
      expect(preview?.isRevoked, isTrue);

      final arriving = await _Device.guest();
      await expectLater(
        arriving.invites.join(link.token),
        throwsA(isA<ApiFailure>()),
      );
    });

    test('a token that names nothing is not a link', () async {
      if (!_available) return;

      expect(await ravi.invites.preview('not-a-token-at-all'), isNull);
    });

    test('a profile is visible to a co-member and to nobody else', () async {
      if (!_available) return;

      final g = await seededGroup(ravi);
      await ravi.ledger.updateProfile(
        api.ProfileUpdate(displayName: 'Ravi', upiVpa: 'ravi@okhdfcbank'),
      );

      final stranger = await _Device.guest();
      expect(
        (await stranger.ledger.profilesByIds([ravi.profileId])).profiles,
        isEmpty,
        reason: 'a payment handle is not public',
      );

      final invite = await ravi.invites.create(g.groupId, g.priya);
      await stranger.invites.join(invite.token);

      // Sharing a group is the whole of the rule, and it is symmetric: a
      // settle-up needs Ravi's handle exactly as much as it needs Priya's.
      final seen = (await stranger.ledger.profilesByIds([
        ravi.profileId,
      ])).profiles;
      expect(seen.single.upiVpa, 'ravi@okhdfcbank');

      final feed = await stranger.ledger.profileChanges(limit: 50);
      expect(
        feed.profiles.map((row) => row.id),
        containsAll([ravi.profileId, stranger.profileId]),
      );
    });

    test('restoring a group and clearing a handle reach the server', () async {
      if (!_available) return;

      // Null is a value in both patches. A generated client drops a null
      // optional field, and the server reads an absent one as "leave it", so
      // these only work because the contract makes the fields required.
      final g = await seededGroup(ravi);
      await ravi.ledger.updateGroup(
        g.groupId,
        api.GroupPatch(archivedAt: DateTime.now().toUtc()),
      );
      final restored = await ravi.ledger.updateGroup(
        g.groupId,
        api.GroupPatch(archivedAt: null),
      );
      expect(restored.archivedAt, isNull);

      await ravi.ledger.updateMember(
        g.groupId,
        g.priya,
        api.MemberPatch(upiVpa: 'priya@okaxis', leftAt: null),
      );
      final cleared = await ravi.ledger.updateMember(
        g.groupId,
        g.priya,
        api.MemberPatch(upiVpa: null, leftAt: null),
      );
      expect(cleared.upiVpa, isNull);
    });

    test('a payment handle can be cleared, not only added', () async {
      if (!_available) return;

      await ravi.ledger.updateProfile(
        api.ProfileUpdate(displayName: 'Ravi', upiVpa: 'ravi@oksbi'),
      );

      // Bank accounts close. This is the case an optional field could not
      // express, because the generated client omits a null rather than sending
      // one — so the wire takes both fields every time.
      final cleared = await ravi.ledger.updateProfile(
        api.ProfileUpdate(displayName: 'Ravi K', upiVpa: null),
      );
      expect(cleared.upiVpa, isNull);
      expect(cleared.displayName, 'Ravi K');
      expect(cleared.updatedAt, isNotNull, reason: 'the feed cursors on it');
    });

    test('the profile feed pages on the pair, not the timestamp', () async {
      if (!_available) return;

      final g = await seededGroup(ravi);
      await ravi.ledger.updateProfile(
        api.ProfileUpdate(displayName: 'Ravi', upiVpa: null),
      );

      final invite = await ravi.invites.create(g.groupId, g.priya);
      await (await _Device.guest()).invites.join(invite.token);

      final collected = <String>{};
      var page = await ravi.ledger.profileChanges(limit: 1);
      collected.addAll(page.profiles.map((row) => row.id));

      var guard = 0;
      while (page.hasMore && guard++ < 10) {
        page = await ravi.ledger.profileChanges(
          since: page.cursor,
          sinceId: page.cursorId,
          limit: 1,
        );
        collected.addAll(page.profiles.map((row) => row.id));
      }

      expect(page.hasMore, isFalse);
      expect(collected.length, 2, reason: 'Ravi and whoever claimed the place');
    });

    test(
      'the sync engine pushes a profile and pulls a co-member back',
      () async {
        if (!_available) return;

        // The whole engine path, not the adapter: a local write goes through the
        // outbox, and a co-member's profile arrives through the cursored feed
        // and lands in the device's own table. Nothing above this proves the
        // cursor survives a real response, or that `applyProfiles` writes what
        // the feed actually sends.
        final g = await seededGroup(ravi);
        final invite = await ravi.invites.create(g.groupId, g.priya);
        final priya = await _Device.guest();
        await priya.invites.join(invite.token);

        final device = AppDatabase(NativeDatabase.memory());
        addTearDown(device.close);
        await seedReferenceData(device);

        final queue = OutboxQueue(device);
        addTearDown(queue.dispose);
        final engine = SyncEngine(
          db: device,
          remote: ravi.ledger,
          outbox: queue,
        );
        addTearDown(engine.dispose);

        final profiles = DriftProfileRepository(device, outbox: queue);
        await profiles.upsert(
          Profile(
            id: ravi.profileId,
            displayName: 'Ravi',
            upiVpa: 'ravi@okhdfcbank',
          ),
        );

        final report = await engine.syncEverything();
        expect(report.isClean, isTrue, reason: '${report.error}');

        // Mine, pushed and read back with the server's timestamp on it — which
        // is the value the feed cursors on, so a null here would mean the next
        // sweep started from the beginning forever.
        final mine = await profiles.byId(ravi.profileId);
        expect(mine?.upiVpa, 'ravi@okhdfcbank');
        expect(mine?.updatedAt, isNotNull);

        // And theirs, which this device never wrote. It arrived because they
        // share a group, which is the whole of the visibility rule.
        final theirs = await profiles.byId(priya.profileId);
        expect(theirs?.displayName, 'Priya');

        // A second sweep finds nothing, because the cursor was kept.
        expect((await engine.syncEverything()).pulled, 0);
      },
    );

    test('a device token registers, transfers and is forgotten', () async {
      if (!_available) return;

      final token = 'fcm-${DateTime.now().microsecondsSinceEpoch}';
      await ravi.devices.register(token: token, platform: 'android');
      // Re-registered on every launch, so it has to be idempotent.
      await ravi.devices.register(token: token, platform: 'android');

      // A phone that changes hands keeps its registration token, so the claim
      // transfers rather than being refused — otherwise the previous owner's
      // notifications would follow the new one.
      final next = await _Device.guest();
      await next.devices.register(token: token, platform: 'android');

      // Which also means signing out on one phone cannot silence another's.
      await ravi.devices.unregister(token);
      await next.devices.unregister(token);
    });

    test('deleting an account leaves a shared group intact', () async {
      if (!_available) return;

      final g = await seededGroup(ravi);
      final invite = await ravi.invites.create(g.groupId, g.priya);
      final priya = await _Device.guest();
      await priya.invites.join(invite.token);

      await priya.account.deleteAccount();

      // Money Priya paid is a fact about Ravi's group as much as hers, so the
      // member row keeps its name and loses its account — exactly the state of
      // somebody a friend added who never signed up.
      final page = await ravi.ledger.changes(g.groupId, since: 0, limit: 200);
      final row = page.members.firstWhere((member) => member.id == g.priya);
      expect(row.displayName, 'Priya');
      expect(row.profileId, isNull);

      // And the session went with it, rather than lingering until something
      // else happened to fail.
      expect(priya.auth.currentUser, isNull);
      await expectLater(priya.ledger.bootstrap(), throwsA(isA<ApiFailure>()));
    });

    test('a group nobody left could read is collected outright', () async {
      if (!_available) return;

      final solo = await _Device.guest();
      final g = await seededGroup(solo);

      await solo.account.deleteAccount();

      // Holding somebody's expense descriptions forever in a group with no
      // living reader is the opposite of what deleting an account asks for.
      // What is left is a tombstone, and it answers anybody: there is no
      // membership left to check, and refusing would leave every device that
      // still holds a copy holding it forever.
      final onlooker = await _Device.guest();
      final grave = await onlooker.ledger.changes(
        g.groupId,
        since: 0,
        limit: 200,
      );
      expect(grave.purgedAt, isNotNull);
      expect(grave.group, isNull);
      expect(grave.members, isEmpty);
    });
  });

  group('the origin serves the front end as well as the API', _serving);
}

/// The serving layer, against the Worker that will serve it.
///
/// Two things decide this and only one is code: `site/_headers` is parsed by
/// Cloudflare and never served, and the deep-link fallback lives in
/// `server/src/app.ts`. Unit tests elsewhere check that the rules *say* the
/// right thing. Only a request can show they are applied — and the most
/// consequential of them is applied by the Worker and the asset router
/// together, which neither suite can see on its own.
void _serving() {
  late HttpClient http;

  setUp(() {
    if (!_available) return;
    http = HttpClient();
  });

  tearDown(() => _available ? http.close(force: true) : null);

  Future<HttpClientResponse> get(String path) async {
    final request = await http.getUrl(Uri.parse('$_origin$path'));
    request.followRedirects = false;
    return request.close();
  }

  test('a cold deep link arrives cross-origin isolated', () async {
    if (!_available) return;

    // The invite link, in other words: somebody taps it and the browser asks
    // for a path no asset matches. The Worker answers it with the client's own
    // document, and these two headers have to survive that — they are what
    // lets sqlite3.wasm use SharedArrayBuffer, so without them the local-first
    // database fails on exactly the arrival that matters most.
    final response = await get('/app/join/a-token-nobody-minted');
    await response.drain<void>();

    expect(response.statusCode, 200);
    expect(response.headers.value('content-type'), contains('text/html'));
    expect(response.headers.value('cross-origin-opener-policy'), 'same-origin');
    expect(
      response.headers.value('cross-origin-embedder-policy'),
      'credentialless',
    );
  });

  test('the static root is not isolated, and says so by omission', () async {
    if (!_available) return;

    // Scoped to the client deliberately. The landing page and the document
    // pages embed Google Fonts, and isolating them would break that for no
    // benefit — so this asserts the absence, which is the part a widened rule
    // would silently undo.
    final response = await get('/');
    await response.drain<void>();

    expect(response.statusCode, 200);
    expect(response.headers.value('cross-origin-embedder-policy'), isNull);
    expect(response.headers.value('x-content-type-options'), 'nosniff');
  });

  test('a document page answers at its own address', () async {
    if (!_available) return;

    for (final page in ['/privacy', '/terms', '/delete-account']) {
      final response = await get(page);
      await response.drain<void>();

      // 200 and not 307. These are the URLs in the Play Console listing and in
      // lib/config.dart, and a reviewer following a redirect chain to a
      // privacy policy is a reason for rejection.
      expect(response.statusCode, 200, reason: '$page did not serve directly');
      expect(response.headers.value('content-type'), contains('text/html'));
    }
  });

  test(
    'a missing page is a 404, not the app and not the landing page',
    () async {
      if (!_available) return;

      final response = await get('/no-such-page');
      final body = await response
          .transform(const SystemEncoding().decoder)
          .join();

      expect(response.statusCode, 404);
      expect(body, contains('That page is not here'));
    },
  );

  test('assetlinks.json is served the one way Android accepts', () async {
    if (!_available) return;

    // JSON, over one request, with no redirect. Get any of the three wrong and
    // App Links fail silently: every invite link opens a browser instead of
    // the app, on other people's phones, with nothing logged anywhere.
    final response = await get('/.well-known/assetlinks.json');
    await response.drain<void>();

    expect(response.statusCode, 200);
    expect(
      response.headers.value('content-type'),
      contains('application/json'),
    );
  });
}
