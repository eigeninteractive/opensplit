import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opensplit/application/app_startup.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/application/session_providers.dart';
import 'package:opensplit/data/auth/session_store.dart';
import 'package:opensplit/data/sync/invites.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/launch_hold.dart';
import 'package:opensplit/presentation/navigation.dart';
import 'package:opensplit/presentation/screens/join_screen.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'https://opensplit.eigeninteractive.com/app/join';

class _Invites implements Invites {
  final calls = <String>[];
  final delayed = Completer<api.LinkPreview?>();

  @override
  Future<api.LinkPreview?> preview(String token) async {
    calls.add(token);
    if (token == 'slow') return delayed.future;
    return _link(token);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

api.LinkPreview _link(String token) => api.LinkPreview(
  kind: token == 'named' ? api.LinkKind.invite : api.LinkKind.groupLink,
  groupId: 'group-$token',
  groupName: 'Trip $token',
  inviterName: 'Priya',
  memberCount: 2,
  memberName: token == 'named' ? 'Ravi' : null,
  isRedeemed: false,
  isExpired: token == 'expired',
  isRevoked: false,
  isMember: token == 'existing',
  hasLeft: false,
);

Future<AppStartup> _mount(
  WidgetTester tester,
  _Invites invites, {
  Future<AppStartup> Function()? load,
  bool signedIn = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final sessions = await SessionStore.load(prefs, vault: MemoryTokenVault());
  final resources = (preferences: prefs, sessions: sessions);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStartupProvider.overrideWith(
          (_) => load == null ? resources : load(),
        ),
        apiClientProvider.overrideWithValue(null),
        invitesProvider.overrideWithValue(invites),
        if (signedIn) signedInProvider.overrideWithValue(true),
      ],
      child: const OpenSplitApp(),
    ),
  );
  await tester.pump();
  return resources;
}

Future<bool> _tapLink(WidgetTester tester, String url) async {
  final reply = await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage(
        SystemChannels.navigation.name,
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('pushRouteInformation', {'location': url}),
        ),
        (_) {},
      );
  return const JSONMethodCodec().decodeEnvelope(reply!) as bool;
}

void main() {
  test('native App Links lose only the app base prefix', () {
    expect(
      redirectAppRoute(
        Uri.parse('/app/join/token?source=share'),
        signedIn: false,
      ),
      '/join/token?source=share',
    );
    expect(redirectAppRoute(Uri.parse('/app'), signedIn: true), '/');
    expect(redirectAppRoute(Uri.parse('/app/'), signedIn: true), '/');
  });

  test('authentication returns to the original protected destination', () {
    final destination = Uri.parse('/g/group/e/entry?tab=history');
    final welcome = Uri.parse(redirectAppRoute(destination, signedIn: false)!);
    expect(welcome.path, '/welcome');
    expect(welcome.queryParameters['from'], destination.toString());
    expect(redirectAppRoute(welcome, signedIn: true), destination.toString());
  });

  test(
    'invite previews remain public and return URLs cannot leave the app',
    () {
      expect(
        redirectAppRoute(Uri.parse('/join/token'), signedIn: false),
        isNull,
      );
      for (final unsafe in [
        'https://attacker.example',
        '//attacker.example',
        'relative',
        '/welcome',
        '/app/welcome',
      ]) {
        expect(safeReturnLocation(unsafe), '/', reason: unsafe);
      }
    },
  );

  testWidgets('a cold Android link opens the invite before signing in', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue =
        '$_base/cold?source=whatsapp';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    final invites = _Invites();
    final startup = Completer<AppStartup>();
    final resources = await _mount(tester, invites, load: () => startup.future);
    expect(invites.calls, isEmpty);
    startup.complete(resources);
    await tester.pumpAndSettle();
    expect(invites.calls, ['cold']);
    expect(find.text('Join Trip cold on OpenSplit'), findsOneWidget);
    expect(find.textContaining('Priya invited'), findsNothing);
  });

  testWidgets(
    'Android links reach the router while the saved session is loading',
    (tester) async {
      final invites = _Invites();
      final startup = Completer<AppStartup>();
      final resources = await _mount(
        tester,
        invites,
        load: () => startup.future,
      );
      expect(await _tapLink(tester, '$_base/early'), isTrue);
      expect(invites.calls, isEmpty);
      expect(find.text('Continue as guest'), findsNothing);
      startup.complete(resources);
      await tester.pumpAndSettle();
      expect(invites.calls, ['early']);
      expect(find.text('Join Trip early on OpenSplit'), findsOneWidget);

      expect(await _tapLink(tester, '$_base/named'), isTrue);
      await tester.pumpAndSettle();
      expect(invites.calls, ['early', 'named']);
      expect(find.text('Priya invited you to Trip named'), findsOneWidget);
    },
  );

  testWidgets('only the newest link opens when two arrive during startup', (
    tester,
  ) async {
    final invites = _Invites();
    final startup = Completer<AppStartup>();
    final resources = await _mount(tester, invites, load: () => startup.future);
    expect(await _tapLink(tester, '$_base/early'), isTrue);
    expect(await _tapLink(tester, '$_base/named'), isTrue);
    startup.complete(resources);
    await tester.pumpAndSettle();
    expect(invites.calls, ['named']);
    expect(find.text('Priya invited you to Trip named'), findsOneWidget);
  });

  testWidgets('a slow invite preview does not keep the launch splash up', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '$_base/slow';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    final invites = _Invites();
    final startup = Completer<AppStartup>();
    bool? joinWasFirst;
    LaunchHold.begin(
      onShown: () {
        joinWasFirst = tester.any(find.byType(JoinScreen));
      },
    );
    addTearDown(LaunchHold.reset);
    final resources = await _mount(tester, invites, load: () => startup.future);
    expect(tester.binding.sendFramesToEngine, isFalse);

    startup.complete(resources);
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(invites.calls, ['slow']);
    expect(joinWasFirst, isTrue);

    invites.delayed.complete(_link('slow'));
    await tester.pumpAndSettle();
    expect(find.text('Join Trip slow on OpenSplit'), findsOneWidget);
  });

  testWidgets('retrying a failed startup keeps the incoming link', (
    tester,
  ) async {
    final invites = _Invites();
    final startup = Completer<AppStartup>();
    final retry = Completer<AppStartup>();
    final resources = await _mount(
      tester,
      invites,
      load: () => startup.isCompleted ? retry.future : startup.future,
    );
    expect(await _tapLink(tester, '$_base/early'), isTrue);
    startup.completeError(StateError('Could not read local storage'));
    await tester.pumpAndSettle();
    expect(invites.calls, isEmpty);
    await tester.tap(find.text('Try again'));
    retry.complete(resources);
    await tester.pumpAndSettle();
    expect(invites.calls, ['early']);
    expect(find.text('Join Trip early on OpenSplit'), findsOneWidget);
  });

  testWidgets(
    'a later link replaces an invite whose preview is still loading',
    (tester) async {
      final invites = _Invites();
      await _mount(tester, invites);
      await tester.pumpAndSettle();
      expect(await _tapLink(tester, '$_base/slow'), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(invites.calls, ['slow']);

      expect(await _tapLink(tester, '$_base/expired'), isTrue);
      await tester.pumpAndSettle();
      invites.delayed.complete(_link('slow'));
      await tester.pumpAndSettle();
      expect(invites.calls, ['slow', 'expired']);
      expect(
        find.text('This link has expired. Ask a group member for a new one.'),
        findsOneWidget,
      );
      expect(find.text('Join Trip slow on OpenSplit'), findsNothing);
    },
  );

  testWidgets('a signed-in member can open the group after tapping its link', (
    tester,
  ) async {
    final invites = _Invites();
    final startup = Completer<AppStartup>();
    final resources = await _mount(
      tester,
      invites,
      signedIn: true,
      load: () => startup.future,
    );
    expect(await _tapLink(tester, '$_base/existing/?source=whatsapp'), isTrue);
    startup.complete(resources);
    await tester.pumpAndSettle();
    expect(invites.calls, ['existing']);
    expect(find.text('Open the group'), findsOneWidget);
  });
}
