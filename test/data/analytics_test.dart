import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_analytics_repository.dart';
import 'package:opensplit/data/repositories/drift_category_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/analytics/analytics_query.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;
  late DriftGroupRepository groups;
  late DriftEntryRepository entries;
  late DriftCategoryRepository categories;
  late DriftAnalyticsRepository analytics;

  late String groupId;
  late String ravi;
  late String priya;
  late String food;
  late String transport;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    groups = DriftGroupRepository(db);
    entries = DriftEntryRepository(db);
    categories = DriftCategoryRepository(db);
    analytics = DriftAnalyticsRepository(db);

    final created = await groups.createGroup(
      name: 'Goa Trip',
      defaultCurrency: 'INR',
      ownerDisplayName: 'Ravi',
    );
    groupId = created.group.id;
    ravi = created.owner.id;
    priya = (await groups.addMember(groupId, displayName: 'Priya')).id;

    final all = await categories.all();
    food = all.firstWhere((c) => c.name == 'Restaurants').id;
    transport = all.firstWhere((c) => c.name == 'Taxi & rideshare').id;

    Future<void> add({
      required String description,
      required int amount,
      required String category,
      required DateTime date,
      String currency = 'INR',
      Map<String, int>? shares,
    }) => entries.create(
      EntryDraft(
        groupId: groupId,
        currency: currency,
        amountMinor: amount,
        description: description,
        categoryId: category,
        entryDate: date,
        split: shares == null ? EqualSplit([ravi, priya]) : ExactSplit(shares),
        payerAmounts: {ravi: amount},
      ),
      createdBy: ravi,
    );

    await add(
      description: 'Dinner at Toit',
      amount: 240000,
      category: food,
      date: DateTime.utc(2026, 8, 3),
    );
    await add(
      description: 'Breakfast dosa',
      amount: 30000,
      category: food,
      date: DateTime.utc(2026, 8, 12),
    );
    await add(
      description: 'Auto to the beach',
      amount: 60000,
      category: transport,
      date: DateTime.utc(2026, 9, 2),
      shares: {ravi: 20000, priya: 40000},
    );
    await add(
      description: 'Ramen in Tokyo',
      amount: 3000,
      category: food,
      date: DateTime.utc(2026, 9, 5),
      currency: 'JPY',
    );

    // A settlement, which must never count as spending.
    await entries.create(
      EntryDraft.settlement(
        groupId: groupId,
        currency: 'INR',
        amountMinor: 50000,
        fromMemberId: priya,
        toMemberId: ravi,
      ),
      createdBy: priya,
    );
  });

  tearDown(() => db.close());

  AnalyticsFilter inr() => AnalyticsFilter(groupId: groupId, currency: 'INR');

  group('spend by category', () {
    test('groups and totals, excluding settlements', () async {
      final buckets = await analytics.spendByCategory(inr()).first;

      expect(buckets.map((b) => b.label), ['Restaurants', 'Taxi & rideshare']);
      expect(buckets.first.amountMinor, 270000);
      expect(buckets.first.entryCount, 2);
      expect(
        buckets.fold(0, (sum, b) => sum + b.amountMinor),
        330000,
        reason: 'the ₹500 settlement is a transfer, not spending',
      );
    });

    test('keeps currencies apart', () async {
      final all = await analytics
          .spendByCategory(AnalyticsFilter(groupId: groupId))
          .first;
      final currencies = all.map((b) => b.currency).toSet();
      expect(currencies, {'INR', 'JPY'});
    });
  });

  group('spend by member', () {
    test('counts what each person consumed, not what they paid', () async {
      final buckets = await analytics.spendByMember(inr()).first;
      final byName = {for (final b in buckets) b.label: b.amountMinor};

      // Ravi paid every bill, but only owed his own shares.
      expect(byName['Ravi'], 120000 + 15000 + 20000);
      expect(byName['Priya'], 120000 + 15000 + 40000);
    });
  });

  group('spend by month', () {
    test('is chronological, not largest-first', () async {
      final buckets = await analytics.spendByMonth(inr()).first;

      expect(buckets.map((b) => b.key), ['2026-08', '2026-09']);
      expect(buckets.first.amountMinor, 270000);
      expect(buckets.last.amountMinor, 60000);
    });
  });

  group('search', () {
    test('finds entries by word, offline and instantly', () async {
      final found = await analytics
          .search(AnalyticsFilter(groupId: groupId, query: 'toit'))
          .first;
      expect(found.map((e) => e.description), ['Dinner at Toit']);
    });

    test('matches on a prefix, so it works as you type', () async {
      final found = await analytics
          .search(AnalyticsFilter(groupId: groupId, query: 'brea'))
          .first;
      expect(found.single.description, 'Breakfast dosa');
    });

    test(
      'survives punctuation that FTS5 would otherwise read as syntax',
      () async {
        // A bare `*` or quote is an FTS5 operator; unescaped it throws a syntax
        // error at someone who was only typing a restaurant name.
        for (final query in ['"', '*', 'toit*', 'a AND', 'NEAR(']) {
          await expectLater(
            analytics
                .search(AnalyticsFilter(groupId: groupId, query: query))
                .first,
            completes,
            reason: 'query: $query',
          );
        }
      },
    );

    test('tracks edits, so the index cannot drift from the table', () async {
      final target =
          (await analytics
                  .search(AnalyticsFilter(groupId: groupId, query: 'toit'))
                  .first)
              .single;

      await entries.update(
        target.id,
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: target.amountMinor,
          description: 'Dinner at Koshys',
          split: EqualSplit([ravi, priya]),
          payerAmounts: {ravi: target.amountMinor},
        ),
      );

      expect(
        await analytics
            .search(AnalyticsFilter(groupId: groupId, query: 'toit'))
            .first,
        isEmpty,
      );
      expect(
        (await analytics
                .search(AnalyticsFilter(groupId: groupId, query: 'koshys'))
                .first)
            .single
            .id,
        target.id,
      );
    });
  });

  group('filters', () {
    test('narrow by date range', () async {
      final buckets = await analytics
          .spendByCategory(
            AnalyticsFilter(
              groupId: groupId,
              currency: 'INR',
              from: DateTime.utc(2026, 9),
            ),
          )
          .first;
      expect(buckets.map((b) => b.label), ['Taxi & rideshare']);
    });

    test('narrow by member', () async {
      final found = await analytics
          .search(AnalyticsFilter(groupId: groupId, memberId: priya))
          .first;
      expect(found, hasLength(4), reason: 'Priya has a share in every expense');
    });

    test('narrow by category', () async {
      final found = await analytics
          .search(AnalyticsFilter(groupId: groupId, categoryId: transport))
          .first;
      expect(found.single.description, 'Auto to the beach');
    });
  });

  // What this guards: every one of these used to be a one-shot query, so the
  // Insights screen answered as of the moment it was opened. An expense added
  // in the pane beside it — or arriving on a sync while it sat open — left
  // totals that quietly disagreed with the ledger they came from.
  group('is live, not a snapshot', () {
    test('a new expense reaches an open query', () async {
      final totals = analytics
          .spendByCategory(inr())
          .map((buckets) => buckets.fold(0, (sum, b) => sum + b.amountMinor));

      expect(
        totals,
        emitsInOrder([330000, 340000]),
        reason: 'the second emission is the one the old code never made',
      );

      // Give the first emission time to land before changing anything.
      await pumpEventQueue();
      await entries.create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 10000,
          description: 'Chai',
          categoryId: food,
          split: EqualSplit([ravi, priya]),
          payerAmounts: {ravi: 10000},
        ),
        createdBy: ravi,
      );
    });

    test('so does a search', () async {
      final descriptions = analytics
          .search(AnalyticsFilter(groupId: groupId, query: 'chai'))
          .map((found) => found.map((e) => e.description).toList());

      expect(
        descriptions,
        emitsInOrder([
          <String>[],
          ['Chai'],
        ]),
      );

      await pumpEventQueue();
      await entries.create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 10000,
          description: 'Chai',
          categoryId: food,
          split: EqualSplit([ravi, priya]),
          payerAmounts: {ravi: 10000},
        ),
        createdBy: ravi,
      );
    });
  });

  test('currenciesUsed lists what the group actually holds', () async {
    expect(await analytics.currenciesUsed(groupId).first, ['INR', 'JPY']);
  });
}
