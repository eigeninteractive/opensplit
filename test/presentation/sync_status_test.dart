import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/presentation/widgets/sync_status_notice.dart';

final _failure = SyncReport(
  pushed: 0,
  pulled: 0,
  failed: 0,
  error: StateError('private diagnostic, not UI copy'),
);

void main() {
  Future<_StatusController> mount(
    WidgetTester tester, {
    SyncStatus initial = const SyncStatus(),
    bool cached = false,
    double textScale = 1,
  }) async {
    final controller = _StatusController(initial);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncControllerProvider.overrideWith(() => controller)],
        child: MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: SingleChildScrollView(
                child: cached
                    ? const Column(
                        children: [
                          SyncStatusBanner(),
                          Text('Saved home group'),
                        ],
                      )
                    : const InitialSyncGate(child: Text('No groups yet')),
              ),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('empty cache is not called empty until discovery succeeds', (
    tester,
  ) async {
    final controller = await mount(tester);
    expect(find.text('No groups yet'), findsNothing);
    expect(find.text('Checking for your groups…'), findsOneWidget);

    controller.show(SyncStatus(lastReport: _failure));
    await tester.pump();
    expect(find.text('No groups yet'), findsNothing);
    expect(find.text('Could not refresh your groups'), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(controller.retries, 1);
    expect(find.text('Checking for your groups…'), findsOneWidget);
    expect(find.text('No groups yet'), findsNothing);

    controller.show(const SyncStatus(hasCompletedFullSync: true));
    await tester.pumpAndSettle();
    expect(find.text('No groups yet'), findsOneWidget);
  });

  testWidgets('local-only builds do not wait for a nonexistent backend', (
    tester,
  ) async {
    await mount(tester, initial: const SyncStatus(enabled: false));
    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed refresh leaves cached data visible', (tester) async {
    final controller = await mount(
      tester,
      cached: true,
      initial: SyncStatus(hasCompletedFullSync: true, lastReport: _failure),
    );
    expect(find.text('Saved home group'), findsOneWidget);
    expect(find.textContaining('Showing saved data'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(controller.retries, 1);
    expect(find.text('Saved home group'), findsOneWidget);
    expect(find.text('Retrying…'), findsOneWidget);
  });

  testWidgets('pending uploads are visible and notice wraps at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      cached: true,
      textScale: 2,
      initial: SyncStatus(
        hasCompletedFullSync: true,
        lastReport: SyncReport(
          pushed: 0,
          pulled: 0,
          failed: 0,
          nextPushAt: DateTime.utc(2026, 8, 28),
        ),
      ),
    );
    expect(find.text('Changes waiting to sync'), findsOneWidget);
    expect(find.textContaining('saved on this device'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _StatusController extends SyncController {
  _StatusController(this.initial);

  final SyncStatus initial;
  int retries = 0;

  @override
  SyncStatus build() => initial;

  void show(SyncStatus next) => state = next;

  @override
  Future<void> syncAll() async {
    retries++;
    state = SyncStatus(
      isSyncing: true,
      hasCompletedFullSync: state.hasCompletedFullSync,
      lastReport: state.lastReport,
    );
  }
}
