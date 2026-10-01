import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/application/local_providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/domain/auth_service.dart';
import 'package:opensplit/presentation/screens/account_screen.dart';
import 'package:opensplit_api/opensplit_api.dart' show Account;

import '../harness.dart';

/// Deleting an account whose session is older than the server will vouch for:
/// a code to the account's own address, then the deletion it was asked for.

class _StaleSession implements AuthService {
  static const acceptedCode = '12345678';
  final calls = <String>[];
  bool _fresh = false;

  @override
  Account? currentUser = Account(
    id: testAccountId,
    isAnonymous: false,
    email: 'asha@example.com',
  );

  @override
  Stream<Account?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<void> deleteAccount() async {
    calls.add('delete');
    if (!_fresh) {
      throw const ReauthenticationRequired('Confirm it is you.');
    }
  }

  @override
  Future<String> startReauthentication() async {
    calls.add('send code');
    return 'asha@example.com';
  }

  @override
  Future<void> reauthenticate(String code) async {
    calls.add('verify $code');
    if (code != acceptedCode) throw StateError('wrong code');
    _fresh = true;
  }

  @override
  Future<void> signOut() async {
    calls.add('sign out');
    currentUser = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _beats(WidgetTester tester) async {
  for (var beat = 0; beat < 10; beat++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  AuthService auth,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentAccountIdProvider.overrideWithValue(testAccountId),
        authServiceProvider.overrideWithValue(auth),
        apiClientProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(home: AccountScreen()),
    ),
  );
  await _beats(tester);
}

Future<void> _askToDelete(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Delete account'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Delete account'));
  await _beats(tester);
  await tester.tap(find.text('Delete for good'));
  await _beats(tester);
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  late AppDatabase db;

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  testWidgets('asks for the emailed code, then deletes', (tester) async {
    final auth = _StaleSession();
    await _pump(tester, db, auth);
    await _askToDelete(tester);

    expect(find.text('Confirm it is you'), findsOneWidget);
    expect(
      find.textContaining('We sent a code to asha@example.com'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, '12345678');
    await tester.tap(find.text('Confirm'));
    await _beats(tester);

    expect(auth.calls, [
      'delete',
      'send code',
      'verify 12345678',
      'delete',
      'sign out',
    ]);
    await _teardown(tester);
  });

  testWidgets('a wrong code is said so, and nothing is deleted', (
    tester,
  ) async {
    final auth = _StaleSession();
    await _pump(tester, db, auth);
    await _askToDelete(tester);

    await tester.enterText(find.byType(TextField).last, '00000000');
    await tester.tap(find.text('Confirm'));
    await _beats(tester);

    expect(find.text('That code is wrong or has expired.'), findsOneWidget);
    expect(auth.calls.where((call) => call == 'delete'), hasLength(1));
    await _teardown(tester);
  });

  testWidgets('backing out keeps the account', (tester) async {
    final auth = _StaleSession();
    await _pump(tester, db, auth);
    await _askToDelete(tester);

    await tester.tap(find.text('Keep my account').last);
    await _beats(tester);

    expect(auth.calls, ['delete', 'send code']);
    expect(find.text('Confirm it is you'), findsNothing);
    await _teardown(tester);
  });
}
