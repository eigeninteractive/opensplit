import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/entry_form.dart';
import 'package:opensplit/application/ledger_providers.dart'
    show GroupLedger, currenciesProvider, groupLedgerProvider;
import 'package:opensplit/application/local_providers.dart';
import 'package:opensplit/application/preferences_providers.dart';
import 'package:opensplit/application/session_providers.dart';
import 'package:opensplit/application/settlement_form.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind, SplitKind;
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// The two forms that record money, driven the way their screens drive them:
/// one intent at a time, then read back.
void main() {
  final now = DateTime.utc(2026, 8, 27);
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = await testDatabase(NativeDatabase.memory());
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'g1',
            name: 'Goa',
            defaultCurrency: 'INR',
            createdAt: now,
          ),
        );
    await db.batch((batch) {
      batch.insertAll(db.members, [
        MembersCompanion.insert(
          id: 'm-ravi',
          groupId: 'g1',
          profileId: const Value(testAccountId),
          displayName: 'Ravi',
          joinedAt: now,
        ),
        MembersCompanion.insert(
          id: 'm-priya',
          groupId: 'g1',
          displayName: 'Priya',
          upiVpa: const Value('priya@okaxis'),
          joinedAt: now,
        ),
        MembersCompanion.insert(
          id: 'm-arun',
          groupId: 'g1',
          displayName: 'Arun',
          upiVpa: const Value('arun@okicici'),
          joinedAt: now,
        ),
      ]);
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        currentAccountIdProvider.overrideWithValue(testAccountId),
        signedInProvider.overrideWithValue(true),
        deviceZoneProvider.overrideWith((ref) async => testZone),
      ],
    );
  });

  tearDown(() => db.close());

  /// The ledger, resolved, which every form reads when it acts.
  Future<GroupLedger> ledger() async {
    container.listen(groupLedgerProvider('g1'), (_, _) {});
    container.listen(currenciesProvider, (_, _) {});
    for (var i = 0; i < 100; i++) {
      final resolved = container.read(groupLedgerProvider('g1'));
      if (resolved != null) return resolved;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('the ledger never resolved');
  }

  group('settling up', () {
    Future<
      ({
        SettlementForm form,
        SettlementFormState Function() state,
        GroupLedger ledger,
      })
    >
    open({String? toId, int? amountMinor, String? entryId}) async {
      final provider = settlementFormProvider(
        'g1',
        toId: toId,
        amountMinor: amountMinor,
        entryId: entryId,
      );
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      return (
        form: container.read(provider.notifier),
        state: () => container.read(provider).requireValue,
        ledger: await ledger(),
      );
    }

    test('opens on the suggested payment, paid by this account', () async {
      final settle = await open(toId: 'm-priya', amountMinor: 125050);

      expect(settle.state().fromId, 'm-ravi');
      expect(settle.state().toId, 'm-priya');
      expect(settle.state().amount, '1250.50');
      expect(settle.state().handleIn(settle.ledger), 'priya@okaxis');
    });

    test('never pays a handle typed for somebody else', () async {
      final settle = await open(toId: 'm-priya');

      settle.form.setHandle('priya.new@okhdfc');
      expect(settle.state().handleIn(settle.ledger), 'priya.new@okhdfc');

      settle.form.choosePayee('m-arun');
      expect(settle.state().handleIn(settle.ledger), 'arun@okicici');

      // What was typed for Priya is still hers.
      settle.form.choosePayee('m-priya');
      expect(settle.state().handleIn(settle.ledger), 'priya.new@okhdfc');
    });

    test('choosing the payee as the payer leaves nobody being paid', () async {
      final settle = await open(toId: 'm-priya');

      settle.form.choosePayer('m-priya');

      expect(settle.state().fromId, 'm-priya');
      expect(settle.state().toId, isNull);
    });

    test('records what was typed, decimal comma and all', () async {
      final settle = await open(toId: 'm-priya');

      settle.form.setAmount('12,50');
      expect(await settle.form.record(), isTrue);

      final recorded = await db.select(db.entries).getSingle();
      expect(recorded.kind, EntryKind.settlement);
      expect(recorded.amountMinor, 1250);
    });

    test('says what is missing rather than recording nothing', () async {
      final settle = await open();

      settle.form.setAmount('100');
      expect(await settle.form.record(), isFalse);
      expect(settle.state().error, 'Choose who is paying whom.');

      // Any change is a new attempt, so the complaint goes.
      settle.form.choosePayee('m-priya');
      expect(settle.state().error, isNull);
    });

    test('editing preserves the payment and updates its whole amount', () async {
      final repository = DriftEntryRepository(db);
      final original = await repository.create(
        EntryDraft.settlement(
          groupId: 'g1',
          currency: 'INR',
          amountMinor: 120000,
          fromMemberId: 'm-priya',
          toMemberId: 'm-ravi',
          entryDate: now,
          occurredAt: now.add(const Duration(hours: 10)),
          timeZone: testZone,
          notes: 'Paid in cash',
          description: 'Older payment label',
        ),
        createdBy: 'm-priya',
      );
      final edit = await open(entryId: original.id);
      expect(edit.state().notes, 'Paid in cash');
      expect(await edit.form.record(), isTrue);
      var saved = (await repository.getEntry(original.id))!;
      expect(saved.row.kind, EntryKind.settlement);
      expect(saved.isSpend, isFalse);
      expect(saved.row.entryDate, original.row.entryDate);
      expect(saved.row.occurredAt, original.row.occurredAt);
      expect(saved.row.timeZone, testZone);
      expect(saved.row.notes, 'Paid in cash');
      expect(saved.row.description, 'Older payment label');
      expect(saved.row.createdAt, original.row.createdAt);
      expect(saved.row.createdBy, original.row.createdBy);

      // A real editor is closed after saving; reopen against the latest value.
      container.invalidate(settlementFormProvider('g1', entryId: original.id));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final reopened = await open(entryId: original.id);
      reopened.form
        ..setAmount('900')
        ..setNotes('Bank transfer');
      expect(await reopened.form.record(), isTrue);
      saved = (await repository.getEntry(original.id))!;
      expect(saved.row.kind, EntryKind.settlement);
      expect(saved.row.amountMinor, 90000);
      expect(saved.payers.single.amountMinor, 90000);
      expect(saved.shares.single.amountMinor, 90000);
      expect(saved.row.notes, 'Bank transfer');
    });

    test(
      'changing a payment date clears its time, and delete keeps history',
      () async {
        final repository = DriftEntryRepository(db);
        final original = await repository.create(
          EntryDraft.settlement(
            groupId: 'g1',
            currency: 'INR',
            amountMinor: 500,
            fromMemberId: 'm-priya',
            toMemberId: 'm-ravi',
            occurredAt: now,
            timeZone: testZone,
          ),
          createdBy: 'm-priya',
        );
        final edit = await open(entryId: original.id);
        edit.form.chooseDay(DateTime.utc(2026, 8, 20));
        expect(edit.state().includeTime, isFalse);
        expect(await edit.form.record(), isTrue);
        final saved = (await repository.getEntry(original.id))!;
        expect(saved.row.entryDate, DateTime.utc(2026, 8, 20));
        expect(saved.row.occurredAt, isNull);
        expect(saved.row.timeZone, isNull);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        container.invalidate(
          settlementFormProvider('g1', entryId: original.id),
        );
        final reopened = await open(entryId: original.id);
        expect(await reopened.form.delete(), isTrue);
        final deleted = (await repository.getEntry(original.id))!;
        expect(deleted.isDeleted, isTrue);
        expect(deleted.row.kind, EntryKind.settlement);
        expect(await db.select(db.groupEvents).get(), isNotEmpty);
      },
    );
  });

  group('an expense', () {
    Future<({EntryForm form, EntryFormState Function() state})> open({
      String? entryId,
    }) async {
      await ledger();
      final provider = entryFormProvider('g1', entryId: entryId);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      return (
        form: container.read(provider.notifier),
        state: () => container.read(provider).requireValue,
      );
    }

    Currency inr() => container.read(currenciesProvider).requireValue['INR']!;

    test('starts split between everyone, paid by this account', () async {
      final expense = await open();
      expense.form.setAmount('300');

      final check = expense.state().check(inr(), groupId: 'g1');
      final draft = (check as DraftReady).draft;
      expect(draft.payerAmounts, {'m-ravi': 30000});
      expect(draft.split, isA<EqualSplit>());
      expect(expense.state().preview(inr()), {
        'm-arun': 10000,
        'm-priya': 10000,
        'm-ravi': 10000,
      });
    });

    test('takes percentages typed with a decimal comma', () async {
      final expense = await open();
      expense.form
        ..setAmount('200')
        ..chooseSplitKind(SplitKind.percent)
        ..setInSplit('m-arun', included: false)
        ..setPercent('m-ravi', '50,5')
        ..setPercent('m-priya', '49,5');

      final draft =
          (expense.state().check(inr(), groupId: 'g1') as DraftReady).draft;
      expect(draft.split.resolve(20000), [
        (memberId: 'm-priya', amountMinor: 9900, weightMicros: 49500000),
        (memberId: 'm-ravi', amountMinor: 10100, weightMicros: 50500000),
      ]);
    });

    test('says what is missing before anything is written', () async {
      final expense = await open();
      expense.form
        ..setAmount('300')
        ..chooseSplitKind(SplitKind.exact)
        ..setExactAmount('m-ravi', '.');

      expect(await expense.form.save(), isFalse);
      expect(
        expense.state().error,
        'Enter a valid amount or clear this value.',
      );
      expect(await db.select(db.entries).get(), isEmpty);
    });

    for (final kind in [
      SplitKind.equal,
      SplitKind.exact,
      SplitKind.percent,
      SplitKind.shares,
    ]) {
      test(
        '$kind saves precisely the previewed values and reserved id',
        () async {
          final expense = await open();
          expense.form
            ..setAmount('0.05')
            ..chooseSplitKind(kind);
          final before = expense.state();
          final preview = before.preview(inr());
          final saving = expense.form.save();
          expect(expense.state().saving, isTrue);
          expense.form.setAmount('500');
          expect(expense.state().amount, '0.05');
          expect(await expense.form.save(), isFalse);
          expect(await saving, isTrue);
          final saved =
              (await container.read(entryRepositoryProvider).getEntries('g1'))
                  .single;
          expect(saved.id, before.newEntryId);
          expect({
            for (final share in saved.shares) share.memberId: share.amountMinor,
          }, preview);
          final editing = await open(entryId: saved.id);
          expect(editing.state().preview(inr()), preview);
          expect(await editing.form.save(), isTrue);
          expect(
            (await container.read(entryRepositoryProvider).getEntry(saved.id))!
                .shares,
            saved.shares,
          );
        },
      );
    }

    test(
      'clear and reset release overrides without disturbing another method',
      () async {
        final expense = await open();
        expense.form
          ..setAmount('300')
          ..chooseSplitKind(SplitKind.exact)
          ..setExactAmount('m-ravi', '120')
          ..setInSplit('m-ravi', included: false)
          ..setInSplit('m-ravi', included: true);
        expect(expense.state().preview(inr())!['m-ravi'], 12000);
        expense.form
          ..chooseSplitKind(SplitKind.percent)
          ..setPercent('m-ravi', '40')
          ..resetSplit();
        expect(expense.state().percents, isEmpty);
        expect(expense.state().exactAmounts['m-ravi'], '120');
        expense.form
          ..chooseSplitKind(SplitKind.exact)
          ..setExactAmount('m-ravi', '');
        expect(expense.state().exactAmounts, isEmpty);
        expense.form
          ..setSeveralPayers(true)
          ..setPaying('m-priya', paying: true)
          ..setPaidAmount('m-ravi', '120');
        expect(expense.state().paidAllocation(inr())!.values, {
          'm-ravi': 12000,
          'm-priya': 18000,
        });
        expense.form.resetPaid();
        expect(expense.state().paidAllocation(inr())!.values, {
          'm-ravi': 15000,
          'm-priya': 15000,
        });
      },
    );

    test('going back to one payer keeps the first of several', () async {
      final expense = await open();
      expense.form
        ..setSeveralPayers(true)
        ..setPaying('m-priya', paying: true)
        ..setSeveralPayers(false);

      expect(expense.state().payers, {'m-ravi'});
    });

    test(
      'is not saved over a version somebody else changed meanwhile',
      () async {
        final created = await open();
        created.form
          ..setAmount('300')
          ..setDescription('Dinner');
        expect(await created.form.save(), isTrue);
        final id = (await db.select(db.entries).getSingle()).id;

        final editing = await open(entryId: id);
        editing.form.setDescription('Dinner at Thalassa');

        // A sync lands underneath the open editor.
        await (db.update(db.entries)..where((t) => t.id.equals(id))).write(
          const EntriesCompanion(amountMinor: Value(40000)),
        );

        expect(await editing.form.save(), isFalse);
        expect(
          editing.state().error,
          contains('changed while you were editing'),
        );
        // And the editor kept what was typed.
        expect(editing.state().description, 'Dinner at Thalassa');
      },
    );
  });
}
