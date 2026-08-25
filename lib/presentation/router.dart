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
      builder: (context, state, child) => SelectionArea(
        child: _AdaptiveShell(state: state, child: child),
      ),
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

/// Adds a navigation rail once there is room for one.
///
/// On a phone the app bar and the back stack are the navigation, and a rail
/// would eat a quarter of the width. On a desktop browser there is otherwise no
/// persistent chrome at all — the only way back to the group list is the app
/// bar's back arrow, which is a phone affordance shown on a 27-inch monitor.
class _AdaptiveShell extends StatelessWidget {
  const _AdaptiveShell({required this.state, required this.child});

  /// Below this the rail is not shown at all. Chosen so that a rail plus a
  /// readable content measure both fit without squeezing either.
  static const double _railBreakpoint = 900;

  /// Material 3's own default destination width, and the rail's width outright:
  /// a destination is padded 8dp either side *within* this, and only pushes
  /// past it if a label needs more. "Groups" and "Settings" are nowhere near,
  /// so the rail is a fixed 80dp and the skeleton can count on it.
  static const double _railWidth = 80;

  final GoRouterState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < _railBreakpoint) return child;

    final path = state.uri.path;
    final onSettings = path == '/settings';

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: onSettings ? 1 : 0,
            labelType: NavigationRailLabelType.all,
            // Material's own default, stated rather than inherited because
            // the web loading skeleton has to leave exactly this much room on
            // the left — see the 900px block in web/index.html.
            minWidth: _railWidth,
            onDestinationSelected: (index) =>
                context.go(index == 1 ? '/settings' : '/'),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups),
                label: Text('Groups'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
