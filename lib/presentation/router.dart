import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import 'navigation.dart';
import 'screens/about_screen.dart';
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
const _destinations = <_Destination>[
  _Destination(
    kind: _DestinationKind.groups,
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
  ),
  _Destination(
    kind: _DestinationKind.account,
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
  _Destination(
    kind: _DestinationKind.settings,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];

class _Destination {
  const _Destination({
    required this.kind,
    required this.icon,
    required this.selectedIcon,
  });

  final _DestinationKind kind;
  final IconData icon;
  final IconData selectedIcon;

  String label(AppLocalizations l10n) => switch (kind) {
    _DestinationKind.groups => l10n.navigationGroups,
    _DestinationKind.account => l10n.navigationAccount,
    _DestinationKind.settings => l10n.navigationSettings,
  };
}

enum _DestinationKind { groups, account, settings }

/// One route table serving both Android and the web.
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
  redirect: (context, state) =>
      redirectAppRoute(state.uri, signedIn: isSignedIn()),
  routes: [
    // One shell around everything, for one reason: SelectionArea.
    ShellRoute(
      builder: (context, state, child) => SelectionArea(child: child),
      routes: [
        // No transition, in both directions.
        GoRoute(
          path: '/welcome',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: WelcomeScreen()),
        ),
        // The link a friend sends.
        GoRoute(
          path: '/join/:token',
          builder: (context, state) =>
              JoinScreen(token: state.pathParameters['token']!),
        ),
        GoRoute(
          path: '/archived',
          builder: (context, state) => const ArchivedGroupsScreen(),
        ),
        // Above the shell rather than inside Settings' branch, so it arrives
        // with a back arrow instead of a menu button -- it is a screen reached
        // from a destination, not a destination.
        GoRoute(
          path: '/about',
          builder: (context, state) => const AboutScreen(),
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
        // The other half of that, and the half that actually does the work: an
        // outgoing page is only removed once the *incoming* one has finished
        // arriving, so silencing the welcome screen alone changed nothing while
        // the destinations still animated in over it.
        StatefulShellRoute.indexedStack(
          pageBuilder: (context, state, shell) =>
              NoTransitionPage(child: AdaptiveNavigation(shell: shell)),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const GroupListScreen(),
                ),
              ],
            ),
            // A top-level destination, not a detail reached from Settings.
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
class AdaptiveNavigation extends StatelessWidget {
  const AdaptiveNavigation({super.key, required this.shell});

  /// Below this the destinations live in a drawer instead.
  static const double _railBreakpoint = 840;

  /// Material 3's own default destination width, and the rail's width outright:
  /// a destination is padded 8dp either side *within* this, and only pushes
  /// past it if a label needs more. None of the three labels is anywhere near,
  /// so the rail is a fixed 80dp and the skeleton can count on it.
  static const double _railWidth = 80;

  final StatefulNavigationShell shell;

  /// The drawer a destination screen should hang off its own Scaffold, or null
  /// when the window is wide enough that the rail is already showing.
  static Widget? drawerFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _railBreakpoint
      ? const _NavigationDrawer()
      : null;

  /// Switches destination, or returns to the top of the one already open.
  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    // Narrow: nothing here at all.
    if (MediaQuery.sizeOf(context).width < _railBreakpoint) return shell;

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            labelType: NavigationRailLabelType.all,
            // Material's own default, stated rather than inherited because the
            // web loading skeleton draws a rail of exactly this width before
            // Flutter starts — see the 840px block in web/index.html, and the
            // test that holds the two numbers together.
            minWidth: _railWidth,
            onDestinationSelected: _select,
            destinations: [
              for (final destination in _destinations)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.label(l10n)),
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

/// The three destinations, as a Material 3 navigation drawer.
class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer();

  @override
  Widget build(BuildContext context) {
    final shell = StatefulNavigationShell.of(context).widget;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return NavigationDrawer(
      // Counts destinations only, so the heading below does not shift it.
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (index) {
        // Closed first: a drawer that is still open while the destination
        // changes behind it animates two things at once and reads as a glitch.
        Navigator.of(context).pop();
        shell.goBranch(index, initialLocation: index == shell.currentIndex);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
          child: Text(l10n.appTitle, style: theme.textTheme.titleSmall),
        ),
        for (final destination in _destinations)
          NavigationDrawerDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: Text(destination.label(l10n)),
          ),
      ],
    );
  }
}
