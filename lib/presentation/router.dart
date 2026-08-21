import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/entry_editor_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/group_list_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/join_screen.dart';
import 'screens/members_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/settle_up_screen.dart';

/// One route table serving both Android and the web.
///
/// The URL is the state. Every meaningful screen is deep-linkable and browser
/// back works, because these same paths have to function as Android App Links
/// later — a route that only exists as an in-memory navigation push cannot be
/// opened from a shared link.
GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  errorBuilder: (context, state) =>
      NotFoundScreen(location: state.uri.toString()),
  routes: [
    // Everything lives under one shell so that the selection wrapper is applied
    // in exactly one place.
    //
    // It cannot go in MaterialApp.builder: that runs above the Navigator, and
    // SelectableRegion needs an Overlay ancestor, which only exists inside a
    // route.
    ShellRoute(
      builder: (context, state, child) => SelectionArea(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const GroupListScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        // The link a friend sends. Deliberately free of any guard: this route
        // has to work for someone who has never opened the app before.
        GoRoute(
          path: '/join/:token',
          builder: (context, state) =>
              JoinScreen(token: state.pathParameters['token']!),
        ),
        GoRoute(
          path: '/g/:groupId',
          builder: (context, state) =>
              GroupDetailScreen(groupId: state.pathParameters['groupId']!),
          routes: [
            GoRoute(
              path: 'add',
              builder: (context, state) =>
                  EntryEditorScreen(groupId: state.pathParameters['groupId']!),
            ),
            GoRoute(
              path: 'insights',
              builder: (context, state) =>
                  InsightsScreen(groupId: state.pathParameters['groupId']!),
            ),
            GoRoute(
              path: 'members',
              builder: (context, state) =>
                  MembersScreen(groupId: state.pathParameters['groupId']!),
            ),
            GoRoute(
              path: 'settle',
              builder: (context, state) => SettleUpScreen(
                groupId: state.pathParameters['groupId']!,
                fromMemberId: state.uri.queryParameters['from'],
                toMemberId: state.uri.queryParameters['to'],
                amountMinor: int.tryParse(
                  state.uri.queryParameters['amount'] ?? '',
                ),
                currency: state.uri.queryParameters['currency'],
              ),
            ),
            GoRoute(
              path: 'e/:entryId',
              builder: (context, state) => EntryEditorScreen(
                groupId: state.pathParameters['groupId']!,
                entryId: state.pathParameters['entryId'],
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
