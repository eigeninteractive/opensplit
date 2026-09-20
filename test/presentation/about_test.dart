import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opensplit/config.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/screens/about_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// The About screen exists to answer a licence obligation and a trust claim,
/// neither of which survives the row that reaches it being quietly dropped in a
/// refactor. So the test is about reachability rather than layout.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('Settings reaches About, which names the source', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('About OpenSplit'), 200);
    await tester.tap(find.text('About OpenSplit'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Source code'), findsOneWidget);
    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text('Licence — AGPL-3.0'), findsOneWidget);
    expect(find.text('Open-source licences'), findsOneWidget);

    // Pushed, not a destination: it arrives over Settings with a way back
    // rather than replacing it.
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    expect(router.state.uri.path, '/about');
    expect(find.byType(BackButton), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  test('the licence and issue pages hang off the repository', () {
    // A fork repoints one define and the whole screen follows, which is what
    // makes shipping this screen unmodified an honest answer to AGPL-3.0.
    expect(issuesUrl, startsWith(repositoryUrl));
    expect(licenseUrl, startsWith(repositoryUrl));
  });
}
