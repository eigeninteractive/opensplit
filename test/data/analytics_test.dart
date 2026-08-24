import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_analytics_repository.dart';
import 'package:opensplit/data/repositories/drift_category_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/repositories/analytics_repository.dart';
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
      final buckets = await analytics.spendByCategory(inr());

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
      final all = await analytics.spendByCategory(
        AnalyticsFilter(groupId: groupId),
      );
      final currencies = all.map((b) => b.currency).toSet();
      expect(currencies, {'INR', 'JPY'});
    });
  });

  group('spend by member', () {
    test('counts what each person consumed, not what they paid', () async {
      final buckets = await analytics.spendByMember(inr());
      final byName = {for (final b in buckets) b.label: b.amountMinor};

      // Ravi paid every bill, but only owed his own shares.
      expect(byName['Ravi'], 120000 + 15000 + 20000);
      expect(byName['Priya'], 120000 + 15000 + 40000);
    });
  });

  group('spend by month', () {
    test('is chronological, not largest-first', () async {
      final buckets = await analytics.spendByMonth(inr());

      expect(buckets.map((b) => b.key), ['2026-08', '2026-09']);
      expect(buckets.first.amountMinor, 270000);
      expect(buckets.last.amountMinor, 60000);
    });
  });

  group('search', () {
    test('finds entries by word, offline and instantly', () async {
      final found = await analytics.search(
        AnalyticsFilter(groupId: groupId, query: 'toit'),
      );
      expect(found.map((e) => e.description), ['Dinner at Toit']);
    });

    test('matches on a prefix, so it works as you type', () async {
      final found = await analytics.search(
        AnalyticsFilter(groupId: groupId, query: 'brea'),
      );
      expect(found.single.description, 'Breakfast dosa');
    });

    test(
      'survives punctuation that FTS5 would otherwise read as syntax',
      () async {
        // A bare `*` or quote is an FTS5 operator; unescaped it throws a syntax
        // error at someone who was only typing a restaurant name.
        for (final query in ['"', '*', 'toit*', 'a AND', 'NEAR(']) {
          await expectLater(
            analytics.search(AnalyticsFilter(groupId: groupId, query: query)),
            completes,
            reason: 'query: $query',
          );
        }
      },
    );

    test('tracks edits, so the index cannot drift from the table', () async {
      final target = (await analytics.search(
        AnalyticsFilter(groupId: groupId, query: 'toit'),
      )).single;

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
        await analytics.search(
          AnalyticsFilter(groupId: groupId, query: 'toit'),
        ),
        isEmpty,
      );
      expect(
        (await analytics.search(
          AnalyticsFilter(groupId: groupId, query: 'koshys'),
        )).single.id,
        target.id,
      );
    });
  });

  group('filters', () {
    test('narrow by date range', () async {
      final buckets = await analytics.spendByCategory(
        AnalyticsFilter(
          groupId: groupId,
          currency: 'INR',
          from: DateTime.utc(2026, 9),
        ),
      );
      expect(buckets.map((b) => b.label), ['Taxi & rideshare']);
    });

    test('narrow by member', () async {
      final found = await analytics.search(
        AnalyticsFilter(groupId: groupId, memberId: priya),
      );
      expect(found, hasLength(4), reason: 'Priya has a share in every expense');
    });

    test('narrow by category', () async {
      final found = await analytics.search(
        AnalyticsFilter(groupId: groupId, categoryId: transport),
      );
      expect(found.single.description, 'Auto to the beach');
    });
  });

  test('currenciesUsed lists what the group actually holds', () async {
    expect(await analytics.currenciesUsed(groupId), ['INR', 'JPY']);
  });
}
