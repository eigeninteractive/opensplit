import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import 'navigation.dart';
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
/// One list, read by the drawer and the rail alike, so the two presentations of
/// the same three destinations cannot drift apart.
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
///    own page transition (predictive back on Android), and grow a back button
///    rather than a menu button.
///
/// Which is the whole rule: a screen whose app bar opens the navigation menu is
/// a destination, and one whose app bar goes back was pushed.
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
  redirect: (context, state) =>
      redirectAppRoute(state.uri, signedIn: isSignedIn()),
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
/// Material 3 gives the same set of destinations several presentations and this
/// picks between them by width: a modal navigation drawer on a phone, a rail
/// down the side once there is room. Both are driven by the same
/// [StatefulNavigationShell], so "which destination am I on" has exactly one
/// answer and neither can disagree with the URL.
///
/// There used to be no third option — a settings button in the app bar, which
/// pushed a screen that was not on top of anything, on a route that then had
/// to suppress its own transition to avoid looking like a drill-down. That is
/// the arrangement this replaces.
class AdaptiveNavigation extends StatelessWidget {
  const AdaptiveNavigation({super.key, required this.shell});

  /// Below this the destinations live in a drawer instead.
  ///
  /// 840 is Material 3's own boundary between the medium and expanded window
  /// classes. The spec allows a rail from 600 up; this app stays with the
  /// drawer to 840, because a phone-sized window is held in a hand however many
  /// pixels it reports and a rail eats width a ledger wants.
  static const double _railBreakpoint = 840;

  /// Material 3's own default destination width, and the rail's width outright:
  /// a destination is padded 8dp either side *within* this, and only pushes
  /// past it if a label needs more. None of the three labels is anywhere near,
  /// so the rail is a fixed 80dp and the skeleton can count on it.
  static const double _railWidth = 80;

  final StatefulNavigationShell shell;

  /// The drawer a destination screen should hang off its own Scaffold, or null
  /// when the window is wide enough that the rail is already showing.
  ///
  /// Returned to the screens rather than placed on a Scaffold here, and that is
  /// forced rather than chosen: every destination builds its own Scaffold with
  /// its own AppBar, and an AppBar grows its menu button from the *nearest*
  /// Scaffold. A drawer on an outer one would exist with nothing to open it.
  ///
  /// Keeping the breakpoint in this class is the point of the method — the
  /// alternative is three screens each deciding for themselves what counts as
  /// narrow, and eventually disagreeing.
  static Widget? drawerFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _railBreakpoint
      ? const _NavigationDrawer()
      : null;

  /// Switches destination, or returns to the top of the one already open.
  ///
  /// `initialLocation: true` when the destination is already selected is
  /// go_router's own idiom for the second half, and it is what people expect:
  /// choosing the destination you are already on goes back to its root rather
  /// than doing nothing.
  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    // Narrow: nothing here at all. The destinations live in a drawer each
    // screen opens for itself — see [drawerFor] — so this adds no chrome and,
    // deliberately, no Scaffold: a second one between the shell and the screen
    // would be the thing an AppBar found when it looked for a drawer.
    if (MediaQuery.sizeOf(context).width < _railBreakpoint) return shell;

    final l10n = AppLocalizations.of(context);
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
///
/// Reached through [AdaptiveNavigation.drawerFor] rather than constructed
/// directly, so no screen has to know when a drawer is the right surface and
/// when the rail has already taken over.
///
/// The shell comes from the tree rather than from a constructor argument.
/// go_router puts a [StatefulNavigationShell] above every branch, and this is
/// only ever built inside one, so asking for it is both correct and shorter
/// than threading it through three screens.
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
