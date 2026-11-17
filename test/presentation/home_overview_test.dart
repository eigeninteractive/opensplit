import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/application/local_providers.dart';
import 'package:opensplit/application/preferences_providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/data/sync/group_signals.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  late AppDatabase db;

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  /// A group where Ana paid [amount] for herself and one other person.
  Future<void> makeGroup(String name, int amount) async {
    final groups = DriftGroupRepository(db);
    final created = await groups.createGroup(
      name: name,
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ana',
      creatorProfileId: testAccountId,
    );
    final ana = created.creator.id;
    final other = await groups.addMember(created.group.id, displayName: 'Bo');
    await DriftEntryRepository(db).create(
      EntryDraft(
        groupId: created.group.id,
        currency: 'INR',
        amountMinor: amount,
        description: 'Dinner',
        split: EqualSplit([ana, other.id]),
        payerAmounts: {ana: amount},
      ),
      createdBy: ana,
    );
  }

  Future<void> mount(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    await _settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('adds up what you are owed across groups', (tester) async {
    await makeGroup('Flat', 20000);
    await makeGroup('Trip', 30000);
    await mount(tester);

    expect(find.text('Across 2 groups'), findsOneWidget);
    expect(find.bySemanticsLabel('You are owed ₹250.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('says nothing overall when one group is the whole story', (
    tester,
  ) async {
    await makeGroup('Flat', 20000);
    await mount(tester);

    expect(find.textContaining('Across'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  group('how far the account has read a group', () {
    final earlier = DateTime.utc(2026, 9, 23, 10);
    final later = DateTime.utc(2026, 9, 23, 11);

    Future<(ProviderContainer, _FakeSignals, SharedPreferences)> arrange({
      bool online = true,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final signals = _FakeSignals(online: online);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentAccountIdProvider.overrideWithValue('me'),
          groupSignalsProvider.overrideWithValue(signals),
        ],
      );
      addTearDown(container.dispose);
      return (container, signals, prefs);
    }

    test('is unknown until first opened, then kept and sent', () async {
      final (container, signals, prefs) = await arrange();
      final seen = groupSeenAtProvider('g1');

      expect(container.read(seen), isNull);
      await container.read(seen.notifier).markSeen(earlier);

      expect(container.read(seen), earlier);
      expect(signals.sent, [('g1', earlier)]);
      expect(prefs.getInt('group_seen_at.me.g1'), isNotNull);
      expect(container.read(groupSeenAtProvider('g2')), isNull);
    });

    test('never moves back, and tells a server that is behind', () async {
      final (container, signals, _) = await arrange();
      final seen = groupSeenAtProvider('g1');
      await container.read(seen.notifier).markSeen(later);
      signals.sent.clear();

      await container.read(seen.notifier).markSeen(earlier);
      await container.read(seen.notifier).adopt(earlier);

      expect(container.read(seen), later);
      expect(signals.sent, [('g1', later)]);
    });

    test('takes what another device has read from the server', () async {
      final (container, signals, _) = await arrange();
      final seen = groupSeenAtProvider('g1');
      await container.read(seen.notifier).markSeen(earlier);
      signals.sent.clear();

      await container.read(seen.notifier).adopt(later);

      expect(container.read(seen), later);
      expect(signals.sent, isEmpty);
    });

    test('marked offline, it is kept and sent after the next sync', () async {
      final (container, signals, _) = await arrange(online: false);
      final seen = groupSeenAtProvider('g1');

      await container.read(seen.notifier).markSeen(earlier);
      expect(container.read(seen), earlier);
      expect(signals.sent, isEmpty);

      signals.online = true;
      await container.read(seen.notifier).adopt(null);
      expect(signals.sent, [('g1', earlier)]);
    });
  });
}

/// A server that remembers what it was told and answers with it.
class _FakeSignals implements GroupSignals {
  _FakeSignals({required this.online});

  bool online;
  final sent = <(String, DateTime)>[];

  @override
  Future<DateTime> markSeen(String groupId, DateTime seenAt) async {
    if (!online) {
      throw const ApiFailure(
        'offline',
        retry: api.Retry.transient,
        unreachable: true,
      );
    }
    sent.add((groupId, seenAt));
    return seenAt;
  }

  @override
  Future<api.Reminder> remind({
    required String groupId,
    required String memberId,
    required String currency,
  }) => throw UnimplementedError();
}
