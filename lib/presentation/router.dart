import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:animations/animations.dart';

import '../l10n/app_localizations.dart';
import 'navigation.dart';
import 'screens/about_screen.dart';
import 'screens/account_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/archived_groups_screen.dart';
import 'screens/avatar_picker_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/entry_editor_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/group_list_screen.dart';
import 'screens/group_settings_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/join_screen.dart';
import 'screens/members_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/save_account_screen.dart';
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
  errorBuilder: _selectable(
    (context, state) => NotFoundScreen(location: state.uri.toString()),
  ),

  /// Nothing above the welcome screen works without a session.
  redirect: (context, state) =>
      redirectAppRoute(state.uri, signedIn: isSignedIn()),
  // Every screen that can be pushed is a page on the one root navigator,
  // which is also where dialogs, date and time pickers and most sheets open.
  // A second navigator around these, as a ShellRoute would add, makes two
  // stacks with two tops: the system back gesture then pops the page that is
  // top of its own stack while a picker sits over it on the other. The
  // destinations' branches below are the only nested navigators, and each
  // holds just its destination, so there is never anything in them to pop.
  routes: [
    // No transition, in both directions.
    GoRoute(
      path: '/welcome',
      pageBuilder: (context, state) =>
          const NoTransitionPage(child: SelectionArea(child: WelcomeScreen())),
    ),
    // The link a friend sends.
    GoRoute(
      path: '/join/:token',
      builder: _selectable(
        (context, state) => JoinScreen(token: state.pathParameters['token']!),
      ),
    ),
    GoRoute(
      path: '/archived',
      builder: _selectable((context, state) => const ArchivedGroupsScreen()),
    ),
    // Above the shell rather than inside Settings' branch, so it arrives
    // with a back arrow instead of a menu button -- it is a screen reached
    // from a destination, not a destination.
    GoRoute(
      path: '/about',
      builder: _selectable((context, state) => const AboutScreen()),
    ),
    // Reached from the Account destination, above the shell for the same
    // reason as About.
    GoRoute(
      path: '/account/edit',
      builder: _selectable(
        (context, state) => EditProfileScreen(
          focus:
              ProfileField.values
                  .asNameMap()[state.uri.queryParameters['field']] ??
              ProfileField.name,
        ),
      ),
    ),
    GoRoute(
      path: '/account/save',
      builder: _selectable((context, state) => const SaveAccountScreen()),
    ),
    GoRoute(
      path: '/account/picture',
      builder: _selectable(
        (context, state) => const AvatarPickerScreen.profile(),
      ),
    ),
    GoRoute(
      path: '/g/:groupId',
      builder: _selectable(
        (context, state) =>
            GroupDetailScreen(groupId: state.pathParameters['groupId']!),
      ),
      routes: [
        GoRoute(
          path: 'add',
          builder: _selectable(
            (context, state) =>
                EntryEditorScreen(groupId: state.pathParameters['groupId']!),
          ),
        ),
        GoRoute(
          path: 'activity',
          builder: _selectable(
            (context, state) =>
                ActivityScreen(groupId: state.pathParameters['groupId']!),
          ),
        ),
        GoRoute(
          path: 'insights',
          builder: _selectable(
            (context, state) =>
                InsightsScreen(groupId: state.pathParameters['groupId']!),
          ),
        ),
        GoRoute(
          path: 'settings',
          builder: _selectable(
            (context, state) =>
                GroupSettingsScreen(groupId: state.pathParameters['groupId']!),
          ),
        ),
        GoRoute(
          path: 'members',
          builder: _selectable(
            (context, state) =>
                MembersScreen(groupId: state.pathParameters['groupId']!),
          ),
        ),
        GoRoute(
          path: 'picture',
          builder: _selectable(
            (context, state) => AvatarPickerScreen.group(
              groupId: state.pathParameters['groupId']!,
            ),
          ),
        ),
        GoRoute(
          path: 'settle',
          builder: _selectable(
            (context, state) => SettleUpScreen(
              groupId: state.pathParameters['groupId']!,
              fromMemberId: state.uri.queryParameters['from'],
              toMemberId: state.uri.queryParameters['to'],
              amountMinor: int.tryParse(
                state.uri.queryParameters['amount'] ?? '',
              ),
              currency: state.uri.queryParameters['currency'],
            ),
          ),
        ),
        GoRoute(
          path: 'e/:entryId',
          builder: _selectable(
            (context, state) => EntryEditorScreen(
              groupId: state.pathParameters['groupId']!,
              entryId: state.pathParameters['entryId'],
            ),
          ),
        ),
      ],
    ),
    // The other half of that, and the half that actually does the work: an
    // outgoing page is only removed once the *incoming* one has finished
    // arriving, so silencing the welcome screen alone changed nothing while
    // the destinations still animated in over it.
    StatefulShellRoute(
      pageBuilder: (context, state, shell) =>
          NoTransitionPage(child: AdaptiveNavigation(shell: shell)),
      navigatorContainerBuilder: (context, shell, children) =>
          _FadeThroughBranches(index: shell.currentIndex, children: children),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: _selectable((context, state) => const GroupListScreen()),
            ),
          ],
        ),
        // A top-level destination, not a detail reached from Settings.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/account',
              builder: _selectable((context, state) => const AccountScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: _selectable((context, state) => const SettingsScreen()),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Builds a screen whose text can be selected and copied.
///
/// One [SelectionArea] per route, as Flutter recommends: it needs the
/// route's overlay for its handles and toolbar, and a selection never runs
/// from a dialog into the page beneath it.
GoRouterWidgetBuilder _selectable(GoRouterWidgetBuilder build) =>
    (context, state) => SelectionArea(child: build(context, state));

/// Shows the selected destination, fading through from the last one.
///
/// Material's pattern for moving between top-level destinations, which are not
/// related to each other in the way a pushed screen is related to the one
/// below it. Every branch stays built, as in an `IndexedStack`, so each keeps
/// its scroll position and stack.
class _FadeThroughBranches extends StatefulWidget {
  const _FadeThroughBranches({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_FadeThroughBranches> createState() => _FadeThroughBranchesState();
}

class _FadeThroughBranchesState extends State<_FadeThroughBranches>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: Durations.medium2, value: 1)
        ..addStatusListener((status) {
          if (status.isCompleted) setState(() => _leaving = null);
        });

  /// The destination fading out, while it does.
  int? _leaving;

  @override
  void didUpdateWidget(_FadeThroughBranches oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _leaving = oldWidget.index;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    // Behind both while neither is fully drawn. A phone has nothing else
    // under the destinations, so without it the midpoint would be black.
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Stack(
      fit: StackFit.expand,
      children: [
        for (final (index, child) in widget.children.indexed)
          _Branch(
            selected: index == widget.index,
            leaving: index == _leaving,
            fade: _controller,
            child: child,
          ),
      ],
    ),
  );
}

/// One destination: shown, fading out, or kept offstage.
///
/// The same widgets in every state, so starting or ending a fade never
/// rebuilds a branch's navigator from scratch.
class _Branch extends StatelessWidget {
  const _Branch({
    required this.selected,
    required this.leaving,
    required this.fade,
    required this.child,
  });

  final bool selected;
  final bool leaving;

  /// Runs forward over a switch: this branch fades in on it when [selected],
  /// and out on it when [leaving].
  final Animation<double> fade;
  final Widget child;

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !selected && !leaving,
    child: TickerMode(
      enabled: selected,
      child: IgnorePointer(
        ignoring: !selected,
        child: ExcludeSemantics(
          excluding: !selected,
          child: FadeThroughTransition(
            animation: selected ? fade : kAlwaysCompleteAnimation,
            secondaryAnimation: leaving ? fade : kAlwaysDismissedAnimation,
            // The one fill is painted behind every branch, by the parent.
            fillColor: Colors.transparent,
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// The app's only navigation surface, in whichever form the window has room
/// for.
class AdaptiveNavigation extends StatelessWidget {
  const AdaptiveNavigation({super.key, required this.shell});

  /// Below this the destinations live in a drawer instead.
  static const double _railBreakpoint = 840;

  /// Material 3's own default destination width, and the rail's width outright:
  /// a destination is padded 8dp either side *within* this, and only pushes
  /// past it if a label needs more. None of the three labels is anywhere near,
  /// so the rail is a fixed 80dp.
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
