import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/account_screen.dart';
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
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: GroupListScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsScreen()),
        ),
        // Pushed rather than lateral: it is reached from Settings and from the
        // prompt on the group list, and both want a back arrow that returns
        // where it came from.
        GoRoute(
          path: '/account',
          builder: (context, state) => const AccountScreen(),
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

/// A top-level destination, which is not a page pushed on top of anything.
///
/// Material's page transitions describe a hierarchy: a screen slides in from
/// the edge because it sits on top of the one before it, and the direction is
/// what tells you a level was entered and can be left again. Moving between
/// destinations in the navigation rail is not that. There is no deeper or
/// shallower, so a slide claims a spatial relationship that does not exist —
/// which is what made switching from Groups to Settings look like a drill-down
/// in the wrong direction.
///
/// [NoTransitionPage] is go_router's own answer for this, and no transition is
/// the honest one. It is also what Flutter's own NavigationRail and
/// NavigationBar samples do: the destination's body is swapped, not routed to.
///
/// Everything pushed on top of these keeps the platform's page transition,
/// which on Android is the predictive-back one and is exactly right for a
/// drill-down.
/// Adds a navigation rail once there is room for one.
///
/// On a phone the app bar and the back stack are the navigation, and a rail
/// would eat a quarter of the width. On a desktop browser there is otherwise no
/// persistent chrome at all — the only way back to the group list is the app
/// bar's back arrow, which is a phone affordance shown on a 27-inch monitor.
class _AdaptiveShell extends StatelessWidget {
  const _AdaptiveShell({required this.state, required this.child});

  /// Below this the rail is not shown at all.
  ///
  /// 840 is Material 3's own boundary between the medium and expanded window
  /// classes, rather than a number picked because it looked right. The spec
  /// puts a rail at medium too, from 600 up; this app stops short of that
  /// because it has two destinations and one of them is Settings, and 80dp of
  /// permanent chrome to reach a screen with an app bar button already on it is
  /// a poor trade on a tablet held in portrait.
  static const double _railBreakpoint = 840;

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
            // the web loading skeleton draws a rail of exactly this width
            // before Flutter starts — see the 840px block in web/index.html,
            // and the test that holds the two numbers together.
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
