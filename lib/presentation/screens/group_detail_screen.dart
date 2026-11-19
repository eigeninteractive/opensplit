import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind;

import '../../application/ledger_providers.dart';
import '../../application/preferences_providers.dart';
import '../../application/backend_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../domain/models/entry.dart';
import '../../domain/models/group_event.dart';
import '../../domain/money_format.dart';
import '../detail_transition.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/group_avatar_hero.dart';
import '../widgets/balances_panel.dart';
import '../widgets/category_icon.dart';
import '../widgets/day_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/group_cover.dart';
import '../widgets/leading_icon.dart';
import '../widgets/group_pane.dart';
import '../widgets/group_standing.dart';
import '../widgets/group_search_button.dart';
import '../widgets/offline_indicator.dart';
import '../widgets/page_body.dart';
import '../widgets/scroll_aware_fab.dart';
import '../widgets/group_access.dart';
import '../widgets/segmented_list.dart';
import '../widgets/sync_refresh_button.dart';
import '../widgets/sync_status_notice.dart';

/// Width at which the two halves of a group stop competing for the screen.
const double _wideBreakpoint = 840;

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  /// Whether the button shows its label. Material's guidance: scrolling
  /// down the list shrinks it to its icon, scrolling back up restores it.
  final _fabExtended = ValueNotifier(true);

  /// When this group was last open before now. Changes other people made
  /// after it are new to this visit, until the activity feed has been read.
  DateTime? _newSince;

  @override
  void initState() {
    super.initState();
    _newSince = ref.read(groupSeenAtProvider(widget.groupId));
    // After the frame, since a provider may not change while widgets build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _markSeen(ref.read(groupActivityProvider(widget.groupId)).value);
      }
    });
  }

  /// Having the group open counts as having seen everything in it so far,
  /// your own changes included, on this device and the account's others.
  void _markSeen(List<GroupEvent>? events) {
    if (events == null || events.isEmpty) return;
    final newest = events
        .map((event) => event.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    unawaited(
      ref.read(groupSeenAtProvider(widget.groupId).notifier).markSeen(newest),
    );
  }

  @override
  void dispose() {
    _fabExtended.dispose();
    super.dispose();
  }

  bool _onScroll(UserScrollNotification notification) {
    // A swipe between the tabs is not a reason to shrink anything.
    if (notification.metrics.axis == Axis.vertical) {
      _fabExtended.value = switch (notification.direction) {
        ScrollDirection.reverse => false,
        ScrollDirection.forward => true,
        ScrollDirection.idle => _fabExtended.value,
      };
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final groupId = widget.groupId;
    final groupAsync = ref.watch(groupProvider(groupId));
    final ledger = ref.watch(groupLedgerProvider(groupId));

    // The ledger stays usable during a refresh; status is shown separately.
    ref.watch(groupSyncProvider(groupId));
    ref.listen(
      groupActivityProvider(groupId),
      (_, activity) => _markSeen(activity.value),
    );

    if (groupAsync.hasValue && groupAsync.value == null) {
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          actions: [if (kIsWeb) SyncRefreshButton.group(groupId)],
        ),
        body: const Center(
          child: InitialSyncGate(
            child: Text('That group is not on this device.'),
          ),
        ),
      );
    }
    if (ledger == null) {
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          actions: [if (kIsWeb) SyncRefreshButton.group(groupId)],
        ),
        body: const SavedDataLoading(label: 'Loading saved group…'),
      );
    }

    if (ledger.me?.isActive != true) return const GroupUnavailableScreen();

    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final scaffold = Scaffold(
      floatingActionButton: !ledger.canEdit
          ? null
          : ScrollAwareFab(
              extended: _fabExtended,
              onPressed: () => context.push('/g/$groupId/add'),
              icon: Icons.add,
              label: 'Add expense',
            ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onScroll,
        child: NestedScrollView(
          headerSliverBuilder: (context, scrolled) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: _GroupAppBar(
                newSince: _newSince,
                onActivityRead: () => setState(() => _newSince = null),
                ledger: ledger,
                tabs: !wide,
                measure: wide ? 1200 : 760,
              ),
            ),
          ],
          // The header spans the window; the panes keep to a readable measure.
          // Two panes are a master–detail layout and can take more width than a
          // single column, but not an unbounded amount: on a 27-inch monitor an
          // uncapped Row puts the expense list and the balances a foot apart.
          body: PageBody(
            maxWidth: wide ? 1200 : 760,
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _EntriesPane(ledger: ledger)),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 2,
                        child: BalancesPanel(
                          ledger: ledger,
                          showsBanners: false,
                        ),
                      ),
                    ],
                  )
                : TabBarView(
                    children: [
                      _EntriesPane(ledger: ledger),
                      BalancesPanel(ledger: ledger),
                    ],
                  ),
          ),
        ),
      ),
    );

    // Keep the app bar and its focus nodes mounted across the breakpoint,
    // including when this page is resizing during its exit transition.
    return DefaultTabController(length: 2, child: scaffold);
  }
}

/// The group's own top app bar: its name, its cover and picture, and where
/// you stand, collapsing to the name and the tabs once you scroll.
class _GroupAppBar extends ConsumerWidget {
  const _GroupAppBar({
    required this.newSince,
    required this.onActivityRead,
    required this.ledger,
    required this.tabs,
    required this.measure,
  });

  /// Changes by other people after this moment are flagged as new.
  final DateTime? newSince;

  /// Called once the activity feed has been opened and come back from.
  final VoidCallback onActivityRead;

  final GroupLedger ledger;
  final bool tabs;

  /// The width the panes below keep to, which the header's picture and
  /// standing line up with.
  final double measure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupId = ledger.group.id;
    final compactRefresh = kIsWeb && MediaQuery.sizeOf(context).width < 400;
    final sync = ref.watch(syncControllerProvider);
    final canRefresh = sync.enabled && !ref.watch(requiresAppUpdateProvider);
    final since = newSince;
    final fresh = since == null
        ? 0
        : (ref.watch(groupActivityProvider(groupId)).value ?? const [])
              .where(
                (event) =>
                    event.createdAt.isAfter(since) &&
                    event.actorId != ledger.me?.id,
              )
              .length;
    Future<void> open(String path) async {
      if (path == 'refresh') {
        await ref.read(syncControllerProvider.notifier).syncGroup(groupId);
      } else if (path == 'activity' && since != null) {
        await context.push(
          '/g/$groupId/activity?since=${since.millisecondsSinceEpoch}',
        );
        onActivityRead();
      } else {
        await context.push('/g/$groupId/$path');
      }
    }

    return SliverAppBar(
      pinned: true,
      expandedHeight:
          _GroupHeader.height(context) + (tabs ? kTextTabBarHeight : 0),
      leading: BackButton(onPressed: () => goBack(context, '/')),
      // FlexibleSpaceBar already supplies the scroll expansion state.
      title: _CollapsedGroupName(name: ledger.group.name),
      actions: [
        const OfflineIndicator(),
        if (kIsWeb && !compactRefresh) SyncRefreshButton.group(groupId),
        GroupSearchButton(key: ValueKey(groupId), groupId: groupId),
        if (ledger.canEdit)
          IconButton(
            tooltip: 'Settle up',
            onPressed: () => open('settle'),
            icon: const Icon(Icons.handshake_outlined),
          ),
        IconButton(
          tooltip: 'People',
          onPressed: () => open('members'),
          icon: const Icon(Icons.people_outline),
        ),
        PopupMenuButton<String>(
          tooltip: fresh == 0 ? 'More' : 'More, with new activity',
          icon: Badge(
            isLabelVisible: fresh > 0,
            child: const Icon(Icons.more_vert),
          ),
          onSelected: open,
          itemBuilder: (context) => [
            if (compactRefresh && canRefresh)
              PopupMenuItem(
                value: 'refresh',
                enabled: !sync.isSyncing,
                child: ListTile(
                  leading: const Icon(Icons.refresh),
                  title: Text(sync.isSyncing ? 'Syncing…' : 'Refresh'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            for (final action in _moreActions)
              PopupMenuItem(
                value: action.path,
                child: ListTile(
                  leading: Icon(action.icon),
                  title: Text(action.label),
                  trailing: action.path == 'activity' && fresh > 0
                      ? Badge.count(count: fresh)
                      : null,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _GroupHeader(
          ledger: ledger,
          bottomInset: tabs ? kTextTabBarHeight : 0,
          measure: measure,
        ),
      ),
      // AppBar changes its toolbar ancestry when bottom becomes null.
      // Keep the slot present so a resize preserves its focused controls.
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(tabs ? kTextTabBarHeight : 0),
        child: Visibility(
          visible: tabs,
          maintainState: true,
          child: const TabBar(
            tabs: [
              Tab(text: 'Expenses'),
              Tab(text: 'Balances'),
            ],
          ),
        ),
      ),
    );
  }
}

/// The expanded name owns the shared element; only the collapsed toolbar
/// repeats it. Keeping this widget mounted also preserves app-bar focus.
class _CollapsedGroupName extends StatelessWidget {
  const _CollapsedGroupName({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final collapsed =
        settings == null || settings.currentExtent <= settings.minExtent + 8;
    return Offstage(
      offstage: !collapsed,
      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// What the overflow menu holds: the places a group has that are visited
/// less often than settling up or seeing who is in it.
const _moreActions = [
  (label: 'Insights', icon: Icons.insights_outlined, path: 'insights'),
  (label: 'Activity', icon: Icons.history, path: 'activity'),
  (label: 'Group settings', icon: Icons.tune, path: 'settings'),
];

/// The expanded part of the group's app bar: the cover behind the toolbar,
/// the group's picture on its edge, and your standing beside it.
class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({
    required this.ledger,
    required this.bottomInset,
    required this.measure,
  });

  final GroupLedger ledger;
  final double bottomInset;
  final double measure;

  /// How far the cover reaches below the toolbar.
  static const _coverBelowToolbar = 64.0;
  static const _avatarRadius = 32.0;

  /// The expanded height, toolbar included and tabs not.
  static double height(BuildContext context) =>
      64 +
      _coverBelowToolbar +
      max(
        112,
        MediaQuery.textScalerOf(context).scale(24) * 2.4 +
            MediaQuery.textScalerOf(context).scale(16) * 2.4 +
            24,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final group = ledger.group;
    final top = MediaQuery.paddingOf(context).top;
    final coverHeight = top + 64 + _coverBelowToolbar;
    const ring = 4.0;
    // The cover spans the window; what sits on it starts where the panes do.
    final width = MediaQuery.sizeOf(context).width;
    final start = 16 + ((width - measure) / 2).clamp(0.0, double.infinity);

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: coverHeight,
          child: GroupCover(ledger: ledger),
        ),
        PositionedDirectional(
          start: start,
          top: coverHeight - _avatarRadius - ring,
          child: Tooltip(
            message: 'Group picture',
            child: InkResponse(
              onTap: ledger.canEdit
                  ? () => context.push('/g/${group.id}/picture')
                  : null,
              radius: _avatarRadius + ring,
              child: CircleAvatar(
                radius: _avatarRadius + ring,
                backgroundColor: scheme.surface,
                child: GroupAvatarHero(group: group, radius: _avatarRadius),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: start + (_avatarRadius + ring) * 2 + 16,
          end: 16,
          top: coverHeight + 12,
          bottom: bottomInset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall!.copyWith(color: scheme.onSurface),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              GroupStanding(ledger: ledger, currencies: currencies),
            ],
          ),
        ),
      ],
    );
  }
}

class _EntriesPane extends ConsumerWidget {
  const _EntriesPane({required this.ledger});

  final GroupLedger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final categories = <String, Category>{
      for (final category
          in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id: category,
    };

    // Entries arrive newest first, so a day's run is contiguous: each day is
    // a header and a segmented group under it.
    final rows = <Object>[];
    final days = <List<Entry>>[];
    for (final entry in ledger.entries) {
      if (days.isEmpty ||
          days.last.first.row.entryDate != entry.row.entryDate) {
        days.add([]);
        rows.add(entry.row.entryDate);
      }
      days.last.add(entry);
      rows.add((entry: entry, day: days.last));
    }

    return GroupPane(
      groupId: ledger.group.id,
      storageKey: 'expenses',
      slivers: [
        if (ledger.entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyEntries(canEdit: ledger.canEdit),
          )
        else
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => switch (rows[index]) {
              final DateTime day => DayHeader(day: day),
              (entry: final Entry entry, day: final List<Entry> day) => Padding(
                key: ValueKey(entry.id),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Segment(
                  index: day.indexOf(entry),
                  count: day.length,
                  // A payment is a record of money changing hands, not
                  // spending: tinted, so it reads apart from the expenses
                  // around it.
                  color: entry.row.kind == EntryKind.settlement
                      ? Theme.of(context).colorScheme.tertiaryContainer
                      : null,
                  child: _EntryTile(
                    entry: entry,
                    ledger: ledger,
                    currency: currencies[entry.row.currency],
                    category: categories[entry.row.categoryId],
                    corners: Segment.radiusAt(
                      index: day.indexOf(entry),
                      count: day.length,
                    ),
                  ),
                ),
              ),
              _ => const SizedBox.shrink(),
            },
          ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.ledger,
    required this.currency,
    required this.category,
    required this.corners,
  });

  final Entry entry;
  final GroupLedger ledger;
  final Currency? currency;
  final Category? category;
  final BorderRadius corners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final me = ledger.me;
    final isSettlement = entry.row.kind == EntryKind.settlement;
    final largeText = MediaQuery.textScalerOf(context).scale(12) > 16;

    // What this entry did to your position: what you paid, less what you owe.
    var myDelta = 0;
    if (me != null) {
      for (final payer in entry.payers) {
        if (payer.memberId == me.id) myDelta += payer.amountMinor;
      }
      for (final share in entry.shares) {
        if (share.memberId == me.id) myDelta -= share.amountMinor;
      }
    }

    String nameOrYou(String memberId) =>
        memberId == me?.id ? 'you' : ledger.nameOf(memberId);
    final payerNames = _capitalised(
      entry.payers.map((p) => nameOrYou(p.memberId)).join(', '),
    );
    final total = formatMoney(currency, entry.row.amountMinor);
    final subtitleStyle = theme.textTheme.bodyMedium!.copyWith(
      color: scheme.onSurfaceVariant,
    );
    void open() => openDetail(
      context,
      '/g/${ledger.group.id}/e/${entry.id}',
      color: isSettlement
          ? scheme.tertiaryContainer
          : scheme.surfaceContainerHigh,
      corners: corners,
    );

    if (isSettlement) {
      return _PaymentTile(
        entry: entry,
        onTap: open,
        title:
            '$payerNames paid '
            '${entry.shares.isEmpty ? '—' : nameOrYou(entry.shares.first.memberId)}',
        total: total,
      );
    }

    return ListTile(
      onTap: open,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(categoryIcon(category?.icon ?? '')),
      ),
      title: Text(
        entry.row.description.isEmpty ? 'Expense' : entry.row.description,
        style: theme.textTheme.titleMedium!.copyWith(color: scheme.onSurface),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // The whole bill lives here, so the trailing figure can be the one
      // that answers "what does this mean for me".
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wrapped, so a long name moves the figure to a line of its own
          // instead of cutting either short.
          Wrap(
            children: [
              Text('$payerNames paid '),
              Text(
                total,
                style: moneyStyle(subtitleStyle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          // At large text a stacked trailing figure no longer fits the row's
          // height, so it joins the lines under the title instead.
          if (largeText)
            _YourPart(myDelta: myDelta, currency: currency, inline: true),
        ],
      ),
      trailing: largeText
          ? null
          : _YourPart(myDelta: myDelta, currency: currency),
    );
  }
}

/// A recorded payment: who paid whom and how much, in the colours of the
/// tinted row it sits on, with its note beneath when it has one.
class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.entry,
    required this.onTap,
    required this.title,
    required this.total,
  });

  final Entry entry;
  final VoidCallback onTap;
  final String title;
  final String total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onTint = theme.colorScheme.onTertiaryContainer;
    // Older payments kept their note in the description.
    final detail = switch (entry.row.notes?.trim()) {
      final note? when note.isNotEmpty => note,
      _ => entry.row.description.trim(),
    };

    return ListTile(
      textColor: onTint,
      onTap: onTap,
      leading: SizedBox(
        width: LeadingIcon.width,
        child: Center(child: Icon(Icons.handshake_outlined, color: onTint)),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium!.copyWith(color: onTint),
      ),
      subtitle: Text(detail.isEmpty ? 'Payment' : detail),
      trailing: Text(
        total,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: moneyStyle(
          theme.textTheme.titleMedium!,
        ).copyWith(color: onTint, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// What an entry meant for you, as a label over its amount: the figure a
/// row's trailing edge is for.
class _YourPart extends StatelessWidget {
  const _YourPart({
    required this.myDelta,
    required this.currency,
    this.inline = false,
  });

  final int myDelta;
  final Currency? currency;

  /// One line of words, "you lent ₹640.00", rather than a label stacked
  /// over its figure.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amountStyle = moneyStyle(
      theme.textTheme.titleMedium!,
    ).copyWith(fontWeight: FontWeight.w600);

    if (myDelta == 0) {
      return Text(
        'not involved',
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final label = myDelta > 0 ? 'you lent' : 'you owe';
    final color = balanceColor(scheme, myDelta);
    final amount = formatMoneyAbs(currency, myDelta);
    if (inline) {
      return Text(
        '$label $amount',
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Semantics(
      label: '$label $amount',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
          Text(amount, style: amountStyle.copyWith(color: color)),
        ],
      ),
    );
  }
}

String _capitalised(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.receipt_long_outlined,
    title: canEdit ? 'Nothing yet' : 'No expenses',
    message: canEdit
        ? 'Add the first expense and balances appear straight away.'
        : 'There are no active expenses in this saved history.',
  );
}
