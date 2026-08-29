import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/models/group.dart';
import 'package:opensplit/presentation/screens/group_detail_screen.dart';
import 'package:opensplit/presentation/screens/group_list_screen.dart';
import 'package:opensplit/presentation/widgets/pull_to_sync.dart';
import 'package:opensplit/presentation/widgets/sync_refresh_button.dart';
import 'package:opensplit/presentation/widgets/sync_status_notice.dart';

final _group = Group(
  id: 'home',
  name: 'Saved home group',
  defaultCurrency: 'INR',
  createdAt: DateTime.utc(2026, 8, 29),
);

final _ledger = GroupLedger(
  group: _group,
  members: const [],
  pastMembers: const [],
  entries: const [],
  balances: const [],
  transfers: const [],
  me: null,
  profiles: const {},
  brokenEntries: const [],
);

Future<void> _mount(
  WidgetTester tester,
  _TestSync sync,
  Widget screen, {
  Stream<List<Group>>? groups,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      syncControllerProvider.overrideWith(() => sync),
      groupsProvider(
        includeArchived: true,
      ).overrideWith((ref) => groups ?? Stream.value([_group])),
      groupProvider(_group.id).overrideWith((ref) => Stream.value(_group)),
      groupLedgerProvider(_group.id).overrideWith((ref) => _ledger),
      groupSyncProvider(_group.id).overrideWith((ref) async {}),
      currenciesProvider.overrideWith((ref) => Stream.value({})),
      failedWritesProvider.overrideWith((ref) => Stream.value([])),
      pendingConflictsProvider.overrideWith((ref) => Stream.value([])),
      accountProvider.overrideWith((ref) => Stream.value(null)),
      totalEntryCountProvider.overrideWith((ref) => Stream.value(0)),
    ],
    child: MaterialApp(home: screen),
  ),
);

void main() {
  testWidgets('refresh targets the account and disables clicks while syncing', (
    tester,
  ) async {
    final sync = _TestSync();
    await _mount(
      tester,
      sync,
      Scaffold(
        appBar: AppBar(actions: const [SyncRefreshButton.everything()]),
        body: const Text('Saved data'),
      ),
    );

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(sync.requests, [null]);
    expect(find.text('Saved data'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Syncing…'));
    expect(sync.requests, [null]);

    sync.finish();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    sync.show(const SyncStatus(isSyncing: true, hasCompletedFullSync: true));
    await tester.pump();
    expect(find.byTooltip('Syncing…'), findsOneWidget);
    expect(sync.requests, [null], reason: 'Automatic sync is also displayed.');
    sync.finish();
    await tester.pumpAndSettle();
  });

  testWidgets('group refresh targets its group and is reusable after failure', (
    tester,
  ) async {
    final sync = _TestSync();
    await _mount(
      tester,
      sync,
      const Scaffold(body: SyncRefreshButton.group('home')),
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(sync.requests, ['home']);
    sync.finish(error: StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Refresh'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(sync.requests, ['home', 'home']);
    sync.finish();
    await tester.pumpAndSettle();
  });

  testWidgets('refresh is hidden when synchronization is unavailable', (
    tester,
  ) async {
    await _mount(
      tester,
      _TestSync(initial: const SyncStatus(enabled: false)),
      const Scaffold(body: SyncRefreshButton.everything()),
    );
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('pull-to-refresh still targets the same coordinator', (
    tester,
  ) async {
    final sync = _TestSync();
    await _mount(
      tester,
      sync,
      Scaffold(
        body: PullToSync.everything(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [Text('Saved data')],
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sync.requests, [null]);
    expect(find.text('Saved data'), findsOneWidget);
    sync.finish();
    await tester.pumpAndSettle();
  });

  testWidgets('opening saved groups has a loading state, not a blank body', (
    tester,
  ) async {
    final groups = StreamController<List<Group>>();
    addTearDown(groups.close);
    await _mount(
      tester,
      _TestSync(),
      const GroupListScreen(),
      groups: groups.stream,
    );
    expect(find.text('Loading saved groups…'), findsOneWidget);
    expect(find.text('No groups yet'), findsNothing);
    groups.add([_group]);
    await tester.pumpAndSettle();
    expect(find.text(_group.name), findsOneWidget);
    expect(find.byType(SavedDataLoading), findsNothing);
  });

  testWidgets('the group list keeps its saved rows through refresh and error', (
    tester,
  ) async {
    final sync = _TestSync();
    var subscriptions = 0;
    final groups = StreamController<List<Group>>(
      onListen: () => subscriptions++,
    );
    addTearDown(groups.close);
    await _mount(tester, sync, const GroupListScreen(), groups: groups.stream);
    groups.add([_group]);
    await tester.pumpAndSettle();
    expect(find.text(_group.name), findsOneWidget);

    if (kIsWeb) {
      await tester.tap(find.byTooltip('Refresh'));
    } else {
      expect(find.byType(SyncRefreshButton), findsNothing);
      unawaited(sync.syncAll());
    }
    await tester.pump();
    expect(find.text(_group.name), findsOneWidget);
    expect(find.byType(SavedDataLoading), findsNothing);
    if (kIsWeb) expect(find.byTooltip('Syncing…'), findsOneWidget);

    sync.finish(error: StateError('connection unavailable'));
    await tester.pumpAndSettle();
    expect(find.text(_group.name), findsOneWidget);
    expect(find.textContaining('Showing saved data'), findsOneWidget);
    expect(
      subscriptions,
      1,
      reason: 'Refresh must not invalidate local queries.',
    );
    expect(sync.requests, [null]);
  });

  testWidgets('group refresh keeps the ledger visible on a wide screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _TestSync();
    await _mount(tester, sync, GroupDetailScreen(groupId: _group.id));
    await tester.pumpAndSettle();
    if (kIsWeb) {
      await tester.tap(find.byTooltip('Refresh'));
    } else {
      expect(find.byType(SyncRefreshButton), findsNothing);
      unawaited(sync.syncGroup(_group.id));
    }
    await tester.pump();
    expect(find.text(_group.name), findsOneWidget);
    expect(find.text('All settled up'), findsOneWidget);
    expect(find.text('Nothing yet'), findsOneWidget);
    expect(sync.requests, [_group.id]);
    sync.finish();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow web group actions leave room for refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _TestSync(), GroupDetailScreen(groupId: _group.id));
    await tester.pumpAndSettle();
    if (kIsWeb) {
      expect(find.byTooltip('Refresh'), findsOneWidget);
      await tester.tap(find.byTooltip('Group actions'));
      await tester.pumpAndSettle();
      for (final label in [
        'People',
        'Insights',
        'Activity',
        'Settle up',
        'Group settings',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    } else {
      expect(find.byTooltip('Group actions'), findsNothing);
      expect(find.byTooltip('People'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

class _TestSync extends SyncController {
  _TestSync({this.initial = const SyncStatus(hasCompletedFullSync: true)});

  final SyncStatus initial;
  final requests = <String?>[];
  Completer<void>? _pending;

  @override
  SyncStatus build() => initial;

  void show(SyncStatus next) => state = next;

  Future<void> _start(String? groupId) {
    requests.add(groupId);
    state = const SyncStatus(isSyncing: true, hasCompletedFullSync: true);
    _pending = Completer<void>();
    return _pending!.future;
  }

  void finish({Object? error}) {
    state = SyncStatus(
      hasCompletedFullSync: true,
      lastReport: SyncReport(pushed: 0, pulled: 0, failed: 0, error: error),
    );
    _pending?.complete();
    _pending = null;
  }

  @override
  Future<void> syncAll() => _start(null);

  @override
  Future<void> syncGroup(String groupId) => _start(groupId);
}
