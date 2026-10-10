import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/ledger_providers.dart';
import 'package:opensplit/application/local_providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/screens/avatar_picker_screen.dart';
import 'package:opensplit/presentation/screens/edit_profile_screen.dart';
import 'package:opensplit/presentation/widgets/sync_status_notice.dart';
import 'package:opensplit_api/opensplit_api.dart' show AvatarKind;

const _account = 'account-1';

const _saved = Profile(
  avatarKind: AvatarKind.initials,
  id: _account,
  displayName: 'Ana Lima',
);

/// Reading the saved profile draws nothing; waiting on a server is shown.
void main() {
  Future<StreamController<Profile?>> mount(
    WidgetTester tester,
    Widget screen,
  ) async {
    final profile = StreamController<Profile?>();
    addTearDown(profile.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue(_account),
          myProfileProvider.overrideWith((ref) => profile.stream),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    return profile;
  }

  testWidgets('the profile editor waits on the device without a spinner', (
    tester,
  ) async {
    final profile = await mount(tester, const EditProfileScreen());
    expect(find.byType(SavedDataLoading), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Read, and not on this device yet: now it is waiting on the server.
    profile.add(null);
    await tester.pump();
    expect(find.byType(SavedDataLoading), findsNothing);
    expect(find.bySemanticsLabel('Waiting for your profile'), findsOneWidget);

    profile.add(_saved);
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'Ana Lima'), findsOneWidget);
  });

  testWidgets('the picture picker does not start before the saved picture', (
    tester,
  ) async {
    final profile = await mount(tester, const AvatarPickerScreen.profile());
    // Before the fix this drew initials at once and kept them as the
    // "unchanged" picture, whatever the saved one turned out to be.
    expect(find.byType(SavedDataLoading), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    profile.add(_saved);
    await tester.pump();
    expect(find.byType(SavedDataLoading), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
      reason: 'nothing has been changed yet',
    );
  });
}
