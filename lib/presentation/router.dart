import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/account_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/archived_groups_screen.dart';
import 'screens/entry_editor_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/group_list_screen.dart';
import 'screens/group_settings_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/join_screen.dart';
import 'screens/members_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/settle_up_screen.dart';
import 'screens/welcome_screen.dart';

/// The app's three top-level destinations, in the order the branches below
/// declare them.
///
/// One list, read by the navigation bar and the rail alike, so the two
/// presentations of the same three destinations cannot drift apart.
const _destinations = <_Destination>[
  _Destination(
    label: 'Groups',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
  ),
  _Destination(
    label: 'Account',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
  _Destination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// One route table serving both Android and the web.
///
/// The URL is the state. Every meaningful screen is deep-linkable and browser
/// back works, because these same paths have to function as Android App Links
/// later — a route that only exists as an in-memory navigation push cannot be
/// opened from a shared link.
///
/// The shape is deliberate, and it is what makes navigation behave the same
/// way everywhere:
///
///  * The three destinations are branches of a [StatefulShellRoute]. Switching
///    between them swaps an [IndexedStack] child, so it is instant, keeps each
///    branch's scroll position, and is never a push — there is no back arrow
///    to Groups from Settings, because Settings is not on top of anything.
///  * Everything else — a group, an expense, an invite — is an ordinary route
///    above the shell. Those are pushed, so they animate with the platform's
///    own page transition (predictive back on Android), grow a back button by
///    themselves, and cover the navigation bar rather than sitting under it.
///
/// Which is the whole rule: if a screen shows the navigation bar it is a
/// destination, and if it does not, it was pushed and can be popped.
GoRouter buildRouter({
  required bool Function() isSignedIn,

  /// Notifies the router that [isSignedIn] may now answer differently, so the
  /// redirect below is reconsidered without the router itself being rebuilt.
  Listenable? refresh,
}) => GoRouter(
  initialLocation: '/',
  refreshListenable: refresh,
  errorBuilder: (context, state) =>
      NotFoundScreen(location: state.uri.toString()),

  /// Nothing above the welcome screen works without a session.
  ///
  /// Not a policy decision so much as a structural one: the local database is
  /// named after the account, so with nobody signed in there is no ledger to
  /// open and every repository below it would be built against nothing.
  ///
  /// `/join/:token` is the deliberate exception. It has to work for somebody
  /// who has never opened the app, and it shows what the link is for *before*
  /// asking who they are — which is the ordering that stops an invite being
  /// spent by an account the arrival did not want.
  redirect: (context, state) {
    final path = state.uri.path;
    final open = path == '/welcome' || path.startsWith('/join/');

    if (!isSignedIn()) return open ? null : '/welcome';
    // Signed in already: the welcome screen has nothing left to offer.
    return path == '/welcome' ? '/' : null;
  },
  routes: [
    // One shell around everything, for one reason: SelectionArea.
    //
    // It cannot go in MaterialApp.builder, which runs above the Navigator,
    // because SelectableRegion needs an Overlay ancestor and only a route has
    // one. Putting it on the destinations alone would leave every pushed
    // screen — which is most of the app — unselectable.
    ShellRoute(
      builder: (context, state, child) => SelectionArea(child: child),
      routes: [
        GoRoute(
          path: '/welcome',
          builder: (context, state) => const WelcomeScreen(),
        ),
        // The link a friend sends. Deliberately free of any guard: this route
        // has to work for someone who has never opened the app before, and
        // deliberately outside the destinations, because an arrival has one
        // decision to make and a navigation bar is an invitation to wander off
        // before making it.
        GoRoute(
          path: '/join/:token',
          builder: (context, state) =>
              JoinScreen(token: state.pathParameters['token']!),
        ),
        GoRoute(
          path: '/archived',
          builder: (context, state) => const ArchivedGroupsScreen(),
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
              path: 'activity',
              builder: (context, state) =>
                  ActivityScreen(groupId: state.pathParameters['groupId']!),
            ),
            GoRoute(
              path: 'insights',
              builder: (context, state) =>
                  InsightsScreen(groupId: state.pathParameters['groupId']!),
            ),
            GoRoute(
              path: 'settings',
              builder: (context, state) => GroupSettingsScreen(
                groupId: state.pathParameters['groupId']!,
              ),
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
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AdaptiveNavigation(shell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const GroupListScreen(),
                ),
              ],
            ),
            // A top-level destination, not a detail reached from Settings. It
            // holds the name everybody in your groups sees, the payment handle
            // they settle against, and whether the account survives this
            // device — none of which is a setting.
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/account',
                  builder: (context, state) => const AccountScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const SettingsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// The app's only navigation surface, in whichever form the window has room
/// for.
///
/// Material 3 gives the same set of destinations two presentations and this
/// picks between them by width: a navigation bar along the bottom on a phone,
/// a rail down the side once there is room. Both are driven by the same
/// [StatefulNavigationShell], so "which destination am I on" has exactly one
/// answer and neither can disagree with the URL.
///
/// There used to be no third option — a settings button in the app bar, which
/// pushed a screen that was not on top of anything, on a route that then had
/// to suppress its own transition to avoid looking like a drill-down. That is
/// the arrangement this replaces.
class AdaptiveNavigation extends StatelessWidget {
  const AdaptiveNavigation({super.key, required this.shell});

  /// Below this the destinations are shown along the bottom instead.
  ///
  /// 840 is Material 3's own boundary between the medium and expanded window
  /// classes. The spec allows a rail from 600 up; this app stays with the
  /// bottom bar to 840 because a bar is reachable one-handed and a phone-sized
  /// window is held in a hand however many pixels it reports.
  static const double _railBreakpoint = 840;

  /// Material 3's own default destination width, and the rail's width outright:
  /// a destination is padded 8dp either side *within* this, and only pushes
  /// past it if a label needs more. None of the three labels is anywhere near,
  /// so the rail is a fixed 80dp and the skeleton can count on it.
  static const double _railWidth = 80;

  final StatefulNavigationShell shell;

  /// Switches destination, or returns to the top of the one already open.
  ///
  /// `initialLocation: true` when the destination is already selected is
  /// go_router's own idiom for the second half, and it is what people expect
  /// from a navigation bar: tapping the lit destination goes back to its root
  /// rather than doing nothing.
  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < _railBreakpoint) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _select,
          destinations: [
            for (final destination in _destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            labelType: NavigationRailLabelType.all,
            // Material's own default, stated rather than inherited because
            // the web loading skeleton draws a rail of exactly this width
            // before Flutter starts — see the 840px block in web/index.html,
            // and the test that holds the two numbers together.
            minWidth: _railWidth,
            onDestinationSelected: _select,
            destinations: [
              for (final destination in _destinations)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}
