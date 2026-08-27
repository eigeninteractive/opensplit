import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/domain/repositories/auth_service.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What signing in looks like, frame by frame.
///
/// The handover from the welcome screen to the app is not a navigation and must
/// not look like one. It used to be two of them: the screen called `context.go`
/// itself while the router's guard independently redirected off `/welcome`, and
/// on top of that the destinations arrived with the platform's page transition
/// — Cupertino's horizontal slide on the web. The result was a welcome screen
/// that stayed on screen sliding leftwards for the better part of a second
/// after the group list had already rendered underneath it.
///
/// pumpAndSettle cannot see any of that. It is precisely the frames in between
/// that were wrong, so this counts them.
void main() {
  testWidgets('the welcome screen is gone the frame after a guest signs in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final auth = _BecomesGuest();
    addTearDown(() => tester.runAsync(db.close));
    addTearDown(auth.events.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authServiceProvider.overrideWithValue(auth),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const OpenSplitApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue as guest'), findsOneWidget);

    await tester.tap(find.text('Continue as guest'));

    // Deliberately one frame at a time, and deliberately counting rather than
    // asserting on the end state: the bug was never visible once things came
    // to rest.
    var framesShowingWelcome = 0;
    for (var frame = 0; frame < 45; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.text('Continue as guest').evaluate().isNotEmpty) {
        framesShowingWelcome++;
      }
    }

    expect(
      framesShowingWelcome,
      isZero,
      reason:
          'the welcome screen was still painted for $framesShowingWelcome '
          'frames after the session began',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the guard alone carries a new session to where it was headed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final auth = _BecomesGuest();
    addTearDown(() => tester.runAsync(db.close));
    addTearDown(auth.events.close);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authServiceProvider.overrideWithValue(auth),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    final router = container.read(routerProvider);
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/welcome');

    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();

    // This is what the welcome screen used to duplicate. It is the reason the
    // screen may safely do nothing at all when a session appears, so if it ever
    // stops being true, deleting that `context.go` was the wrong call.
    expect(router.state.uri.path, '/settings');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

/// Signed out until somebody asks to be a guest.
///
/// The auth event arrives a turn after the call returns, the way Supabase's
/// does — the session is real before the stream says so, and nothing may depend
/// on the order of those two.
class _BecomesGuest implements AuthService {
  static const _guest = Account(id: 'guest-1', isAnonymous: true);

  final events = StreamController<Account?>.broadcast();

  @override
  Account? currentUser;

  @override
  Stream<Account?> authStateChanges() => events.stream;

  @override
  Future<Account> signInAnonymously() async {
    currentUser = _guest;
    scheduleMicrotask(() => events.add(_guest));
    return _guest;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not needed here');
}
