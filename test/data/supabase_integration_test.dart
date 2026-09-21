@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/auth/supabase_auth_service.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/remote_ledger_api.dart';
import 'package:opensplit/data/sync/supabase_invite_api.dart';
import 'package:opensplit/data/sync/supabase_ledger_api.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/group_event.dart';
import 'package:opensplit/domain/repositories/auth_service.dart';
import 'package:opensplit/domain/repositories/invite_api.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../harness.dart';

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

const _mailpitUrl = 'http://127.0.0.1:54324';

/// The eight-digit code GoTrue just mailed to [email], read out of Mailpit.
///
/// Reading the actual email rather than the database is the point: it proves
/// the template carries `{{ .Token }}`. The stock Supabase templates send a
/// magic link and no token at all, against which every code flow in the app
/// waits forever for something that was never sent — which is exactly the bug
/// this asserts is gone.
Future<String> _mailedCode(String email) async {
  final http = HttpClient();
  try {
    // GoTrue mails asynchronously; a fixed sleep would be a flake either way.
    for (var attempt = 0; attempt < 40; attempt++) {
      final request = await http.getUrl(
        Uri.parse(
          '$_mailpitUrl/api/v1/search',
        ).replace(queryParameters: {'query': 'to:$email', 'limit': '1'}),
      );
      final body = await (await request.close()).transform(utf8.decoder).join();
      final messages = (jsonDecode(body) as Map)['messages'] as List;
      if (messages.isNotEmpty) {
        final snippet = (messages.first as Map)['Snippet'] as String;
        final code = RegExp(r'\b(\d{8})\b').firstMatch(snippet);
        if (code != null) return code.group(1)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('no code was mailed to $email within four seconds');
  } finally {
    http.close(force: true);
  }
}

/// The PKCE code verifier has to live somewhere between asking for a code and
/// verifying it.
///
/// `Supabase.initialize` installs a real one; a bare [SupabaseClient] has none
/// and asserts as soon as a PKCE flow starts. In-memory and per-client is the
/// faithful shape: it is what makes each client below a separate device.
class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

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
      if (const bool.fromEnvironment('REQUIRE_SUPABASE')) {
        fail('CI requires a running local Supabase at $_apiUrl.');
      }
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

      await seedReferenceData(db);
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
        creatorDisplayName: 'Ravi',
        creatorProfileId: user.id,
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
          split: EqualSplit([created.creator.id, priya.id]),
          payerAmounts: {created.creator.id: 240000},
        ),
        createdBy: created.creator.id,
      );

      final report = await sync.syncGroup(created.group.id);
      expect(report.isClean, isTrue, reason: '$report');
      expect(
        report.pushed,
        4,
        reason:
            'the group, its owner, the added member and the entry. The '
            'activity row is not among them: the server writes it from the '
            'expense it commits, and grants no client the right to',
      );

      // Read it back through a second, empty device.
      final other = AppDatabase(NativeDatabase.memory());
      await seedReferenceData(other);
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

      // The feed reaches the second device too, and this is the half only a
      // live server can prove: nothing pushed this row. Postgres wrote it in
      // the same transaction as the expense, from the expense, resolved the
      // actor from the session rather than from anything sent, and handed it
      // back under the policy that scopes it to members of the group.
      final feed = await DriftActivityRepository(
        other,
      ).watchGroup(created.group.id).first;

      // More than the expense now: the group also records the person who was
      // added to it. Narrowed rather than counted, so this test stays about
      // the expense line and does not have to be revisited every time the
      // server learns to record something else.
      final expense = feed.whereType<EntryChanged>().single;
      expect(expense.kind, EntryEventKind.created);
      expect(
        expense.isProvisional,
        isFalse,
        reason: 'this device wrote nothing; it only read',
      );
      expect(
        expense.actorId,
        created.creator.id,
        reason: 'authorship is the member row, not the account',
      );

      // And the half that is new: a placeholder appearing is on the record,
      // written by a trigger nothing on this device asked for.
      expect(
        feed.whereType<MemberChanged>().map((e) => e.displayName),
        contains('Priya'),
        reason: 'a group that cannot see who arrived cannot remove them',
      );
    });

    test('the server rejects an entry that does not balance', () async {
      if (!available) return;

      final user = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Invariant ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: user.id,
      );
      final entry = await entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([created.creator.id]),
          payerAmounts: {created.creator.id: 100000},
        ),
        createdBy: created.creator.id,
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

    test('a stale edit that would move money is refused', () async {
      if (!available) return;

      final user = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Stale ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: user.id,
      );
      final entry = await entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([created.creator.id]),
          payerAmounts: {created.creator.id: 100000},
        ),
        createdBy: created.creator.id,
      );
      await sync.syncGroup(created.group.id);

      final base = (await api.pullEntries(
        groupId: created.group.id,
        limit: 10,
      )).rows.single.updatedAt;

      // Somebody else's edit lands, moving the amount and the share with it.
      final theirs = await api.upsertEntry(
        entry.copyWith(
          amountMinor: 150000,
          payers: [entry.payers.first.copyWith(amountMinor: 150000)],
          shares: [entry.shares.first.copyWith(amountMinor: 150000)],
        ),
        baseUpdatedAt: base,
      );
      expect(theirs.amountMinor, 150000);

      // And now the edit composed against the version they replaced. Only this
      // test proves the adapter actually sends p_base_updated_at and maps
      // 40001 to its own kind -- pgTAP proves the SQL, and the fake proves the
      // algorithm, but neither goes near the wire.
      await expectLater(
        api.upsertEntry(
          entry.copyWith(
            amountMinor: 200000,
            payers: [entry.payers.first.copyWith(amountMinor: 200000)],
            shares: [entry.shares.first.copyWith(amountMinor: 200000)],
          ),
          baseUpdatedAt: base,
        ),
        throwsA(
          isA<RemoteRejected>().having(
            (e) => e.kind,
            'kind',
            RejectionKind.stale,
          ),
        ),
      );

      // An edit against the same stale base that leaves the money exactly
      // where the server has it is not refused: arbitrating a typo would cost
      // two people a decision for nothing.
      final prose = await api.upsertEntry(
        entry.copyWith(
          description: 'Renamed',
          amountMinor: 150000,
          payers: [entry.payers.first.copyWith(amountMinor: 150000)],
          shares: [entry.shares.first.copyWith(amountMinor: 150000)],
        ),
        baseUpdatedAt: base,
      );
      expect(prose.description, 'Renamed');
      expect(prose.amountMinor, 150000);
    });

    test(
      'the delta cursor does not re-deliver what it already applied',
      () async {
        if (!available) return;

        final user = (await client.auth.signInAnonymously()).user!;
        final created = await groups.createGroup(
          name: 'Cursor ${DateTime.now().microsecondsSinceEpoch}',
          defaultCurrency: 'INR',
          creatorDisplayName: 'Ravi',
          creatorProfileId: user.id,
        );
        for (var i = 0; i < 6; i++) {
          await entries.create(
            EntryDraft(
              groupId: created.group.id,
              currency: 'INR',
              amountMinor: 1000 * (i + 1),
              description: 'Expense $i',
              split: EqualSplit([created.creator.id]),
              payerAmounts: {created.creator.id: 1000 * (i + 1)},
            ),
            createdBy: created.creator.id,
          );
        }
        await sync.syncGroup(created.group.id);

        final other = AppDatabase(NativeDatabase.memory());

        await seedReferenceData(other);
        addTearDown(other.close);
        // A page size below the row count forces the cursor to actually page.
        final paging = SyncEngine(
          db: other,
          api: api,
          outbox: OutboxQueue(other),
          pageSize: 2,
        );

        final firstPull = await paging.syncGroup(created.group.id);
        expect(firstPull.isClean, isTrue, reason: '$firstPull');
        expect(firstPull.pulled, 6);
        final secondPull = await paging.syncGroup(created.group.id);
        expect(secondPull.isClean, isTrue, reason: '$secondPull');
        expect(
          secondPull.pulled,
          0,
          reason: 'a second pass with no changes must pull nothing',
        );
      },
    );

    test('an invite link puts a stranger inside the group', () async {
      if (!available) return;

      // ---- Ravi's device -------------------------------------------------
      final ravi = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Invite ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: ravi.id,
      );
      // Priya is added as a placeholder: a full member of the group who has
      // never heard of the app.
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
          split: EqualSplit([created.creator.id, priya.id]),
          payerAmounts: {created.creator.id: 240000},
        ),
        createdBy: created.creator.id,
      );
      await sync.syncGroup(created.group.id);

      final invite = await SupabaseInviteApi(client).create(priya.id);
      expect(invite.memberId, priya.id);
      expect(
        invite.urlFor('opensplit.alturing.dev'),
        'https://opensplit.alturing.dev/app/join/${invite.token}',
        reason: 'the client is served under /app/; the host root is static',
      );

      // ---- Priya's device, which has never seen this group ---------------
      final hers = SupabaseClient(_apiUrl, _anonKey);
      addTearDown(hers.dispose);
      // No signup screen: a session is created silently.
      await hers.auth.signInAnonymously();

      final claimed = await SupabaseInviteApi(hers).redeem(invite.token);
      expect(claimed.id, priya.id, reason: 'she claims the existing place');
      expect(claimed.isPlaceholder, isFalse);

      final herDb = AppDatabase(NativeDatabase.memory());

      await seedReferenceData(herDb);
      addTearDown(herDb.close);
      await SyncEngine(
        db: herDb,
        api: SupabaseLedgerApi(hers),
        outbox: OutboxQueue(herDb),
      ).syncGroup(created.group.id);

      final herEntries = await DriftEntryRepository(
        herDb,
      ).getEntries(created.group.id);
      expect(herEntries, hasLength(1));

      // The debt she inherits is the one that already existed. Claiming set one
      // column; it did not rewrite a single financial row.
      final balances = foldBalances(herEntries);
      expect(
        balances.firstWhere((b) => b.memberId == priya.id).balanceMinor,
        -120000,
      );

      // ---- The token is spent ---------------------------------------------
      final third = SupabaseClient(_apiUrl, _anonKey);
      addTearDown(third.dispose);
      await third.auth.signInAnonymously();
      await expectLater(
        SupabaseInviteApi(third).redeem(invite.token),
        throwsA(isA<InviteRejected>()),
        reason: 'a single-use link cannot be spent twice',
      );
    });

    test('a stranger cannot read another group', () async {
      if (!available) return;

      final user = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Private ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: user.id,
      );
      await entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'INR',
          amountMinor: 50000,
          split: EqualSplit([created.creator.id]),
          payerAmounts: {created.creator.id: 50000},
        ),
        createdBy: created.creator.id,
      );
      await sync.syncGroup(created.group.id);

      // A completely separate anonymous session.
      final stranger = SupabaseClient(_apiUrl, _anonKey);
      addTearDown(stranger.dispose);
      await stranger.auth.signInAnonymously();
      final strangerApi = SupabaseLedgerApi(stranger);

      final group = await strangerApi.pullGroup(
        groupId: created.group.id,
        limit: 200,
      );
      expect(group.rows, isEmpty);
      final members = await strangerApi.pullMembers(
        groupId: created.group.id,
        limit: 200,
      );
      expect(members.rows, isEmpty);
      final delta = await strangerApi.pullEntries(
        groupId: created.group.id,
        limit: 200,
      );
      expect(delta.rows, isEmpty);
    });

    test('a second device finds the groups the account belongs to', () async {
      if (!available) return;

      // The gap that made a reinstall, a second device and "sign in on another
      // device" all show an empty app. Worth an integration test rather than
      // only a fake one, because it is a PostgREST filter and a policy —
      // members_read has to admit your own row — and neither is visible from
      // the Dart side.
      final user = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Discoverable ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: user.id,
      );
      await sync.syncGroup(created.group.id);

      expect(await api.pullMyGroupIds(), contains(created.group.id));

      final other = AppDatabase(NativeDatabase.memory());

      await seedReferenceData(other);
      addTearDown(other.close);
      final otherSync = SyncEngine(
        db: other,
        api: api,
        outbox: OutboxQueue(other),
      );
      final firstPull = await otherSync.syncEverything();
      expect(firstPull.isClean, isTrue, reason: '$firstPull');

      final addedLater = await groups.createGroup(
        name: 'Added later ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: user.id,
      );
      final upload = await sync.syncGroup(addedLater.group.id);
      expect(upload.isClean, isTrue, reason: '$upload');
      final refresh = await otherSync.syncEverything();
      expect(refresh.isClean, isTrue, reason: '$refresh');
      expect(
        (await other.select(other.groups).get()).map((group) => group.id),
        containsAll([created.group.id, addedLater.group.id]),
      );

      // Somebody else's session must not see it.
      final stranger = SupabaseClient(_apiUrl, _anonKey);
      addTearDown(stranger.dispose);
      await stranger.auth.signInAnonymously();
      expect(
        await SupabaseLedgerApi(stranger).pullMyGroupIds(),
        isNot(contains(created.group.id)),
      );
    });

    test('a group that has been left is not rediscovered', () async {
      if (!available) return;

      final user = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Leavable ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: user.id,
      );
      await sync.syncGroup(created.group.id);
      expect(await api.pullMyGroupIds(), contains(created.group.id));

      await groups.leaveGroup(
        groupId: created.group.id,
        memberId: created.creator.id,
      );
      await sync.syncGroup(created.group.id);

      expect(await api.pullMyGroupIds(), isNot(contains(created.group.id)));
    });

    test('a member cannot rewrite another member payment handle', () async {
      if (!available) return;

      // guard_member_update, through the adapter rather than through psql.
      // Redirecting somebody else's UPI handle is the one escalation here that
      // moves real money.
      final owner = (await client.auth.signInAnonymously()).user!;
      final created = await groups.createGroup(
        name: 'Guarded ${DateTime.now().microsecondsSinceEpoch}',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: owner.id,
      );
      final slot = await groups.addMember(
        created.group.id,
        displayName: 'Priya',
      );
      await sync.syncGroup(created.group.id);

      // Priya claims her place, so she is a real member with an account.
      final priya = SupabaseClient(_apiUrl, _anonKey);
      addTearDown(priya.dispose);
      await priya.auth.signInAnonymously();
      final invite = await SupabaseInviteApi(client).create(slot.id);
      await SupabaseInviteApi(priya).redeem(invite.token);

      // She may set her own handle.
      await expectLater(
        priya
            .from('members')
            .update({'upi_vpa': 'priya@oksbi'})
            .eq('id', slot.id),
        completes,
      );

      // She may not set the owner's.
      await expectLater(
        priya
            .from('members')
            .update({'upi_vpa': 'attacker@okaxis'})
            .eq('id', created.creator.id),
        throwsA(isA<PostgrestException>()),
      );

      // And she may not promote herself.
      await expectLater(
        priya.from('members').update({'role': 'owner'}).eq('id', slot.id),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  /// Linking versus signing in, against the real thing.
  ///
  /// Every branch below has one outcome the user can never undo, so none of it
  /// is safe to leave to a fake: whether the user id survives is the whole
  /// question, and only GoTrue can answer it.
  group('SupabaseAuthService against a live GoTrue', () {
    late SupabaseClient client;
    late SupabaseAuthService auth;

    setUp(() {
      if (!available) return;
      client = SupabaseClient(
        _apiUrl,
        _anonKey,
        authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryStore()),
      );
      auth = SupabaseAuthService(client);
    });

    tearDown(() async {
      if (!available) return;
      await client.auth.signOut();
      await client.dispose();
    });

    String freshAddress() =>
        'link-${DateTime.now().microsecondsSinceEpoch}@example.com';

    test(
      'an email address free to take is LINKED, keeping the user id',
      () async {
        if (!available) return;

        final before = await auth.signInAnonymously();
        final email = freshAddress();

        expect(await auth.sendEmailCode(email), EmailFlow.linkPending);

        final outcome = await auth.verifyEmailCode(
          email: email,
          code: await _mailedCode(email),
          flow: EmailFlow.linkPending,
        );

        expect(
          outcome,
          isA<SessionKept>(),
          reason: 'linking must not replace the session',
        );
        expect(
          outcome.account.id,
          before.id,
          reason:
              'the id is what every group, member and expense is filed '
              'under; a new one strands all of them',
        );
        expect(outcome.account.isAnonymous, isFalse);
        expect(outcome.account.email, email);
      },
    );

    test('an address somebody already has is a SIGN-IN, not a link', () async {
      if (!available) return;

      // Somebody already owns it.
      final email = freshAddress();
      await auth.signInAnonymously();
      await auth.sendEmailCode(email);
      final owner = await auth.verifyEmailCode(
        email: email,
        code: await _mailedCode(email),
        flow: EmailFlow.linkPending,
      );
      await client.auth.signOut();

      // A second device, anonymous, gives the same address.
      final stranger = await auth.signInAnonymously();
      expect(
        await auth.sendEmailCode(email),
        EmailFlow.signInPending,
        reason: 'there is nothing to link it to, so it can only be a sign-in',
      );

      final outcome = await auth.verifyEmailCode(
        email: email,
        code: await _mailedCode(email),
        flow: EmailFlow.signInPending,
      );

      expect(
        outcome,
        isA<SessionReplaced>().having(
          (replaced) => replaced.strandedUserId,
          'strandedUserId',
          stranger.id,
        ),
        reason:
            'the caller has to be told which account was left behind, or '
            'it cannot warn anyone in time',
      );
      expect(outcome.account.id, owner.account.id);
      expect(
        outcome.account.id,
        isNot(stranger.id),
        reason:
            'this is the anonymous account being left behind — the whole '
            'reason the screen stops and asks first',
      );
    });

    test('GoTrue refuses to invent the account the fallback declines', () async {
      if (!available) return;

      // Pins the server half of the contract sendEmailCode's fallback rests on.
      // That fallback is only reached for an address that provably belongs to
      // somebody, so it cannot be driven here through the public API — but if
      // it ever were reached for a free one, the default of shouldCreateUser
      // would mint a new user and silently abandon the session holding every
      // group on the device. Refusing is what makes that recoverable, and this
      // is the assertion that the refusal is real.
      await auth.signInAnonymously();
      final unowned = freshAddress();

      await expectLater(
        client.auth.signInWithOtp(email: unowned, shouldCreateUser: false),
        throwsA(
          isA<AuthException>().having((e) => e.code, 'code', 'otp_disabled'),
        ),
      );

      final minted = await client
          .from('profiles')
          .select('id')
          .eq('display_name', unowned)
          .maybeSingle();
      expect(minted, isNull);
    });
  });

  /// The invite flow, in the order it now happens.
  ///
  /// Redeeming used to come first, before anybody had been asked who they
  /// were, which is how somebody with an existing account ended up locked out
  /// of the group they had just been invited to. These are the assertions that
  /// the ordering cannot slip back.
  group('peek before redeem, against a live instance', () {
    late SupabaseClient host;
    late SupabaseClient guest;
    late SupabaseInviteApi hostInvites;
    late SupabaseInviteApi guestInvites;
    late AppDatabase hostDb;
    late DriftGroupRepository hostGroups;

    setUp(() async {
      if (!available) return;
      host = SupabaseClient(_apiUrl, _anonKey);
      guest = SupabaseClient(_apiUrl, _anonKey);
      hostInvites = SupabaseInviteApi(host);
      guestInvites = SupabaseInviteApi(guest);
      hostDb = AppDatabase(NativeDatabase.memory());
      await seedReferenceData(hostDb);
      hostGroups = DriftGroupRepository(hostDb, outbox: OutboxQueue(hostDb));
    });

    tearDown(() async {
      if (!available) return;
      await host.auth.signOut();
      await guest.auth.signOut();
      await host.dispose();
      await guest.dispose();
      await hostDb.close();
    });

    /// Makes a group with one unclaimed place and returns its invite token.
    Future<String> inviteAwaiting(String placeholderName) async {
      final me = (await host.auth.signInAnonymously()).user!;
      await host
          .from('profiles')
          .update({'display_name': 'Priya'})
          .eq('id', me.id);

      final created = await hostGroups.createGroup(
        name: 'Goa trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Priya',
        creatorProfileId: me.id,
      );
      final friend = await hostGroups.addMember(
        created.group.id,
        displayName: placeholderName,
      );
      await SyncEngine(
        db: hostDb,
        api: SupabaseLedgerApi(host),
        outbox: OutboxQueue(hostDb),
      ).syncGroup(created.group.id);

      return (await hostInvites.create(friend.id)).token;
    }

    test('a link describes itself before anybody has signed in', () async {
      if (!available) return;

      final token = await inviteAwaiting('Ravi');

      // No session on this client at all — the state somebody is in when they
      // tap a link, and the reason peek_invite is granted to anon.
      expect(guest.auth.currentUser, isNull);

      final preview = await guestInvites.peek(token);
      expect(preview, isNotNull);
      expect(preview!.groupName, 'Goa trip');
      expect(preview.memberName, 'Ravi');
      expect(preview.inviterName, 'Priya');
      expect(preview.isUsable, isTrue);
      expect(
        preview.isRedeemed,
        isFalse,
        reason: 'reading a link must not spend it — that is the entire point',
      );

      // And still unspent afterwards, so the arrival can pick an account and
      // come back.
      final second = await guestInvites.peek(token);
      expect(second!.isRedeemed, isFalse);
    });

    test('the account that claims it is the one that was chosen', () async {
      if (!available) return;

      final token = await inviteAwaiting('Ravi');

      // Ravi already has an account, and signs in as himself BEFORE claiming —
      // which the preview is what makes possible.
      final ravi = (await guest.auth.signInAnonymously()).user!;
      final member = await guestInvites.redeem(token);

      expect(
        member.profileId,
        ravi.id,
        reason:
            'the place belongs to whoever was signed in when they claimed '
            'it, and they were asked first',
      );

      final mine = await guest
          .from('members')
          .select('group_id')
          .eq('profile_id', ravi.id);
      expect(
        mine,
        hasLength(1),
        reason: 'and it is a group his account can actually see',
      );
    });

    test('a spent link says so rather than failing at the last step', () async {
      if (!available) return;

      final token = await inviteAwaiting('Ravi');
      await guest.auth.signInAnonymously();
      await guestInvites.redeem(token);

      final preview = await guestInvites.peek(token);
      expect(preview!.isRedeemed, isTrue);
      expect(preview.isUsable, isFalse);
    });

    test(
      'somebody already in the group is told, not offered a claim',
      () async {
        if (!available) return;

        // Priya, who owns the group, opens a link meant for Ravi.
        final token = await inviteAwaiting('Ravi');
        final preview = await hostInvites.peek(token);

        expect(
          preview!.isMember,
          isTrue,
          reason: 'redeem would refuse this, so the screen must not offer it',
        );
        expect(preview.isUsable, isFalse);
      },
    );
  });

  /// The open link: one URL, any number of arrivals.
  ///
  /// These assertions are the ones that decide whether the feature is
  /// acceptable rather than merely working: a stranger holding the token gets
  /// in, the names of the people already there are NOT readable until they have
  /// said who they are, and claiming a place somebody typed is the same
  /// single-column update a named invite makes.
  group('open group links, against a live instance', () {
    late SupabaseClient host;
    late SupabaseClient guest;
    late SupabaseInviteApi hostInvites;
    late SupabaseInviteApi guestInvites;
    late AppDatabase hostDb;
    late DriftGroupRepository hostGroups;
    late String groupId;

    setUp(() async {
      if (!available) return;
      host = SupabaseClient(_apiUrl, _anonKey);
      guest = SupabaseClient(_apiUrl, _anonKey);
      hostInvites = SupabaseInviteApi(host);
      guestInvites = SupabaseInviteApi(guest);
      hostDb = AppDatabase(NativeDatabase.memory());
      await seedReferenceData(hostDb);
      hostGroups = DriftGroupRepository(hostDb, outbox: OutboxQueue(hostDb));
    });

    tearDown(() async {
      if (!available) return;
      await host.auth.signOut();
      await guest.auth.signOut();
      await host.dispose();
      await guest.dispose();
      await hostDb.close();
    });

    /// A group with [placeholders] typed in, and a live open link for it.
    Future<String> linkedGroup(List<String> placeholders) async {
      final me = (await host.auth.signInAnonymously()).user!;
      await host
          .from('profiles')
          .update({'display_name': 'Priya'})
          .eq('id', me.id);

      final created = await hostGroups.createGroup(
        name: 'Goa trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Priya',
        creatorProfileId: me.id,
      );
      groupId = created.group.id;
      for (final name in placeholders) {
        await hostGroups.addMember(groupId, displayName: name);
      }
      await SyncEngine(
        db: hostDb,
        api: SupabaseLedgerApi(host),
        outbox: OutboxQueue(hostDb),
      ).syncGroup(groupId);

      return (await hostInvites.createGroupLink(groupId)).token;
    }

    test('describes itself to somebody with no session', () async {
      if (!available) return;

      final token = await linkedGroup(['Ravi']);
      expect(guest.auth.currentUser, isNull);

      final target = await guestInvites.peekLink(token);
      expect(target, isA<GroupLinkTarget>());

      final preview = (target! as GroupLinkTarget).preview;
      expect(preview.groupName, 'Goa trip');
      expect(preview.inviterName, 'Priya');
      expect(preview.memberCount, 2);
      expect(preview.isUsable, isTrue);
    });

    test('will not name the group members to a stranger', () async {
      if (!available) return;

      // The line between what the token implies and what it does not. Holding
      // it tells you the group exists and how big it is; it does not entitle
      // you to everybody's name before you have said who you are.
      final token = await linkedGroup(['Ravi', 'Meera']);
      expect(guest.auth.currentUser, isNull);

      await expectLater(
        guestInvites.placeholdersFor(token),
        throwsA(isA<Exception>()),
      );
    });

    test('offers the unclaimed places once there is a session', () async {
      if (!available) return;

      final token = await linkedGroup(['Ravi', 'Meera']);
      await guest.auth.signInAnonymously();

      final places = await guestInvites.placeholdersFor(token);
      expect(places.map((p) => p.displayName), containsAll(['Ravi', 'Meera']));
      expect(
        places.map((p) => p.displayName),
        isNot(contains('Priya')),
        reason: 'Priya has an account; her place is not going spare',
      );
    });

    test('claiming a place moves no money and adds no member', () async {
      if (!available) return;

      final token = await linkedGroup(['Ravi']);
      final before = await host
          .from('members')
          .select('id')
          .eq('group_id', groupId);

      await guest.auth.signInAnonymously();
      final places = await guestInvites.placeholdersFor(token);
      final ravi = places.firstWhere((p) => p.displayName == 'Ravi');

      final claimed = await guestInvites.joinWithLink(
        token,
        memberId: ravi.memberId,
      );

      expect(claimed.id, ravi.memberId, reason: 'the same row, not a new one');

      final after = await host
          .from('members')
          .select('id')
          .eq('group_id', groupId);
      expect(
        after,
        hasLength(before.length),
        reason: 'the whole point: no seventh member beside the placeholder',
      );
    });

    test('somebody not on the list arrives as a new member', () async {
      if (!available) return;

      final token = await linkedGroup(['Ravi']);
      await guest.auth.signInAnonymously();

      final joined = await guestInvites.joinWithLink(token);
      expect(joined.groupId, groupId);

      final members = await host
          .from('members')
          .select('id')
          .eq('group_id', groupId);
      expect(members, hasLength(3), reason: 'Priya, the Ravi slot, and them');
    });

    test('one account cannot hold two places', () async {
      if (!available) return;

      final token = await linkedGroup(['Ravi']);
      await guest.auth.signInAnonymously();
      await guestInvites.joinWithLink(token);

      await expectLater(
        guestInvites.joinWithLink(token),
        throwsA(isA<InviteRejected>()),
      );
    });

    test('the link keeps working for the next person', () async {
      if (!available) return;

      // The difference from a named invite, stated as a test: a group link is
      // not spent by being used.
      final token = await linkedGroup(['Ravi']);

      await guest.auth.signInAnonymously();
      await guestInvites.joinWithLink(token);

      final third = SupabaseClient(_apiUrl, _anonKey);
      addTearDown(third.dispose);
      await third.auth.signInAnonymously();
      final joined = await SupabaseInviteApi(third).joinWithLink(token);
      expect(joined.groupId, groupId);
    });

    test('revoking shuts the door without minting another', () async {
      if (!available) return;

      final token = await linkedGroup(['Ravi']);
      await hostInvites.revokeGroupLink(groupId);

      final target = await guestInvites.peekLink(token);
      final preview = (target! as GroupLinkTarget).preview;
      expect(preview.isRevoked, isTrue);
      expect(preview.isUsable, isFalse);

      await guest.auth.signInAnonymously();
      await expectLater(
        guestInvites.joinWithLink(token),
        throwsA(isA<InviteRejected>()),
      );

      expect(await hostInvites.currentGroupLink(groupId), isNull);
    });

    test('minting again replaces the link left in a chat', () async {
      if (!available) return;

      final old = await linkedGroup(['Ravi']);
      final fresh = await hostInvites.createGroupLink(groupId);
      expect(fresh.token, isNot(old));

      await guest.auth.signInAnonymously();
      await expectLater(
        guestInvites.joinWithLink(old),
        throwsA(isA<InviteRejected>()),
      );
    });

    test('the group is told the door was opened and closed', () async {
      if (!available) return;

      final token = await linkedGroup(['Ravi']);
      await guest.auth.signInAnonymously();
      await guestInvites.joinWithLink(token);
      await hostInvites.revokeGroupLink(groupId);

      final events = await host
          .from('group_events')
          .select('kind')
          .eq('group_id', groupId);
      final kinds = [for (final row in events) row['kind'] as String];

      expect(kinds, contains('link_created'));
      expect(kinds, contains('link_revoked'));
      expect(
        kinds,
        contains('member_joined'),
        reason: 'a group that cannot see who walked in cannot remove them',
      );
    });
  });
}
