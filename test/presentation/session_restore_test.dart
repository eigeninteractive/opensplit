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

/// What a reload shows somebody who is already signed in.
///
/// The answer has to be "their groups", on the first frame and every frame
/// after it. Anything else is a flash of the sign-in screen at somebody who
/// signed in weeks ago, and on the web it is worse than cosmetic: the static
/// boot skeleton has already painted a signed-in layout, so the app contradicts
/// the page it is replacing.
void main() {
  testWidgets('a restored session never shows the welcome screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authServiceProvider.overrideWithValue(_SignedIn()),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const OpenSplitApp(),
      ),
    );

    // Deliberately not pumpAndSettle. The bug is a frame, and settling is what
    // hides it: by the time everything has come to rest the redirect has
    // already corrected itself and the flash has been and gone.
    for (var frame = 0; frame < 5; frame++) {
      expect(
        find.text('Continue as guest'),
        findsNothing,
        reason: 'welcome screen visible on frame $frame of a restored session',
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a signed-out device still lands on welcome', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authServiceProvider.overrideWithValue(_SignedOut()),
        ],
        child: const OpenSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The other half of the same mapping. Deciding that "not known yet" means
    // signed in would fix the flash by breaking arrival, which is the more
    // expensive of the two: somebody who has never opened the app would land
    // on an empty group list with no way to say who they are.
    expect(find.text('Continue as guest'), findsOneWidget);
  });

  test(
    'session follows later auth events without an initial loading state',
    () async {
      final auth = _ChangingAuth();
      final container = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );
      container.listen(sessionControllerProvider, (_, _) {});
      addTearDown(() async {
        container.dispose();
        await auth.events.close();
      });
      expect(container.read(signedInProvider), isTrue);
      await container.read(accountProvider.future);

      auth.currentUser = null;
      auth.events.add(null);
      await container.pump();

      expect(container.read(sessionControllerProvider), isNull);
      expect(container.read(signedInProvider), isFalse);
    },
  );
}

class _ChangingAuth implements AuthService {
  late final StreamController<Account?> events =
      StreamController<Account?>.broadcast(
        onListen: () => events.add(currentUser),
      );

  @override
  Account? currentUser = const Account(id: 'user-1', isAnonymous: false);

  @override
  Stream<Account?> authStateChanges() => events.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not needed here');
}

/// An auth service with no session, the way one is on a fresh install.
class _SignedOut implements AuthService {
  @override
  Account? get currentUser => null;

  @override
  Stream<Account?> authStateChanges() => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not needed here');
}

/// An auth service holding a session, the way one does after a reload.
class _SignedIn implements AuthService {
  static const _account = Account(id: 'user-1', isAnonymous: false);

  @override
  Account? get currentUser => _account;

  @override
  Stream<Account?> authStateChanges() => Stream.value(_account);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not needed here');
}
