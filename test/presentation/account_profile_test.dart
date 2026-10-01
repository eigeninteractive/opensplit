import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/application/router_provider.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_profile_repository.dart';
import 'package:opensplit/domain/auth_service.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/screens/account_screen.dart';
import 'package:opensplit_api/opensplit_api.dart' show Account;
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// The account page shows the stored profile; editing happens on its own
/// screen and comes back to it.
void main() {
  late AppDatabase db;

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> openAccount(WidgetTester tester, {bool guest = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      signedInApp(
        db: db,
        prefs: prefs,
        overrides: [authServiceProvider.overrideWithValue(_Auth(guest: guest))],
        child: const OpenSplitApp(),
      ),
    );
    await settle(tester);
    ProviderScope.containerOf(
      tester.element(find.byType(OpenSplitApp)),
    ).read(routerProvider).go('/account');
    await settle(tester);
  }

  Future<void> store(WidgetTester tester, {String? name, String? upi}) =>
      tester.runAsync(
        () => DriftProfileRepository(
          db,
        ).upsert(Profile(id: testAccountId, displayName: name, upiVpa: upi)),
      );

  Future<Profile?> stored(WidgetTester tester) => tester.runAsync<Profile?>(
    () => DriftProfileRepository(db).byId(testAccountId),
  );

  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await settle(tester);
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  /// Unmounts inside the test, so Drift's stream cleanup timers fire while
  /// there is still a tree to pump.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('shows the stored profile, including a name saved elsewhere', (
    tester,
  ) async {
    await store(tester);
    await openAccount(tester);
    expect(find.text('No name yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'a view, not a form');

    // What the group sheet does with "Your name" on an account without one.
    await store(tester, name: 'Ana Lima');
    await settle(tester);

    expect(find.text('Ana Lima'), findsNWidgets(2));
    expect(find.text('AL'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('editing saves and comes back to the page', (tester) async {
    await store(tester, name: 'Ana');
    await openAccount(tester);

    await tapAndSettle(tester, find.byTooltip('Edit profile'));
    expect(find.text('Edit profile'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
      reason: 'nothing to save until something changes',
    );

    await tester.enterText(field('Name'), 'Ana Lima');
    await tester.enterText(field('UPI ID (optional)'), 'ana@okbank');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));

    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('ana@okbank'), findsOneWidget);
    final profile = await stored(tester);
    expect(profile?.displayName, 'Ana Lima');
    expect(profile?.upiVpa, 'ana@okbank');
    await unmount(tester);
  });

  testWidgets('refuses a blank name and a malformed UPI ID', (tester) async {
    await store(tester, name: 'Ana');
    await openAccount(tester);
    await tapAndSettle(tester, find.text('UPI ID'));

    await tester.enterText(field('Name'), '  ');
    await tester.enterText(field('UPI ID (optional)'), 'not a handle');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));

    expect(find.text('Your name cannot be blank.'), findsOneWidget);
    expect(find.text('That does not look like a UPI ID.'), findsOneWidget);
    expect((await stored(tester))?.displayName, 'Ana');
    await unmount(tester);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await store(tester, name: 'Ana');
    await openAccount(tester);
    await tapAndSettle(tester, find.text('Name'));

    await tester.enterText(field('Name'), 'Someone else');
    await tapAndSettle(tester, find.byTooltip('Close'));
    expect(find.text('Discard changes?'), findsOneWidget);

    await tapAndSettle(tester, find.text('Keep editing'));
    expect(find.text('Edit profile'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Close'));
    await tapAndSettle(tester, find.text('Discard'));
    expect(find.text('Edit profile'), findsNothing);
    expect((await stored(tester))?.displayName, 'Ana');
    await unmount(tester);
  });

  testWidgets('a guest is offered one way to save the account', (tester) async {
    await store(tester, name: 'Ana');
    await openAccount(tester, guest: true);
    expect(find.text('Guest account on this device'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tapAndSettle(tester, find.text('Save my account'));

    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    await unmount(tester);
  });

  test('initials come from the first and last words', () {
    expect(initialsOf('Ana Lima'), 'AL');
    expect(initialsOf('ana'), 'A');
    expect(initialsOf('Ana Maria  da Silva'), 'AS');
    expect(initialsOf('  '), '');
  });
}

/// Who the account is, and nothing else: no test here signs in or out.
class _Auth implements AuthService {
  _Auth({required bool guest})
    : currentUser = Account(
        id: testAccountId,
        isAnonymous: guest,
        email: guest ? null : 'ana@example.com',
      );

  @override
  final Account? currentUser;

  @override
  Stream<Account?> authStateChanges() => Stream.value(currentUser);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
