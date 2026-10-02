import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind;

import '../../application/ledger_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../domain/calendar_date.dart';
import '../../domain/models/entry.dart';
import '../../domain/money_format.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/avatar_view.dart';
import '../widgets/balance_arrow.dart';
import '../widgets/balances_panel.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state.dart';
import '../widgets/group_cover.dart';
import '../widgets/group_pane.dart';
import '../widgets/group_standing.dart';
import '../widgets/page_body.dart';
import '../widgets/sync_refresh_button.dart';
import '../widgets/sync_status_notice.dart';

/// Width at which the two halves of a group stop competing for the screen.
const double _wideBreakpoint = 840;

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));
    final ledger = ref.watch(groupLedgerProvider(groupId));

    // The ledger stays usable during a refresh; status is shown separately.
    ref.watch(groupSyncProvider(groupId));

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

    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final scaffold = Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/g/$groupId/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, scrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: _GroupAppBar(
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
                      child: BalancesPanel(ledger: ledger, showsBanners: false),
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
    );

    // A TabBar needs a controller in scope, but only the narrow layout has
    // tabs at all; the wide one shows both panes at once.
    return wide ? scaffold : DefaultTabController(length: 2, child: scaffold);
  }
}

/// The group's own top app bar: its name, its cover and picture, and where
/// you stand, collapsing to the name and the tabs once you scroll.
class _GroupAppBar extends StatelessWidget {
  const _GroupAppBar({
    required this.ledger,
    required this.tabs,
    required this.measure,
  });

  final GroupLedger ledger;
  final bool tabs;

  /// The width the panes below keep to, which the header's picture and
  /// standing line up with.
  final double measure;

  @override
  Widget build(BuildContext context) {
    final groupId = ledger.group.id;
    void open(String path) => context.push('/g/$groupId/$path');

    return SliverAppBar(
      pinned: true,
      expandedHeight: _GroupHeader.height + (tabs ? kTextTabBarHeight : 0),
      leading: BackButton(onPressed: () => goBack(context, '/')),
      title: Text(ledger.group.name),
      actions: [
        if (kIsWeb) SyncRefreshButton.group(groupId),
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
          tooltip: 'More',
          onSelected: open,
          itemBuilder: (context) => [
            for (final action in _moreActions)
              PopupMenuItem(
                value: action.path,
                child: ListTile(
                  leading: Icon(action.icon),
                  title: Text(action.label),
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
      bottom: tabs
          ? const TabBar(
              tabs: [
                Tab(text: 'Expenses'),
                Tab(text: 'Balances'),
              ],
            )
          : null,
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

  /// Room for the standing, under the cover.
  static const _standingHeight = 72.0;

  /// The expanded height, toolbar included and tabs not.
  static const height = 64 + _coverBelowToolbar + _standingHeight;

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
              onTap: () => context.push('/g/${group.id}/picture'),
              radius: _avatarRadius + ring,
              child: CircleAvatar(
                radius: _avatarRadius + ring,
                backgroundColor: scheme.surface,
                child: AvatarView(
                  avatar: group.avatar,
                  name: group.name,
                  id: group.id,
                  radius: _avatarRadius,
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: start + (_avatarRadius + ring) * 2 + 16,
          end: 16,
          top: coverHeight + 12,
          bottom: bottomInset,
          child: GroupStanding(
            ledger: ledger,
            currencies: currencies,
            style: Theme.of(context).textTheme.titleMedium,
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

    // Entries arrive newest first, so a day's run is contiguous.
    final rows = <Object>[];
    DateTime? day;
    for (final entry in ledger.entries) {
      if (entry.row.entryDate != day) {
        day = entry.row.entryDate;
        rows.add(day);
      }
      rows.add(entry);
    }

    return GroupPane(
      groupId: ledger.group.id,
      storageKey: 'expenses',
      slivers: [
        if (ledger.entries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyEntries(),
          )
        else
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => switch (rows[index]) {
              final DateTime day => _DayHeader(day: day),
              final Entry entry => _EntryTile(
                entry: entry,
                ledger: ledger,
                currency: currencies[entry.row.currency],
                category: categories[entry.row.categoryId],
              ),
              _ => const SizedBox.shrink(),
            },
          ),
      ],
    );
  }
}

/// The calendar day the expenses under it happened on.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          dayLabel(day, today: calendarDay(DateTime.now())),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", or the date, with the year only when it is not this
/// one.
@visibleForTesting
String dayLabel(DateTime day, {required DateTime today}) {
  final daysAgo = today.difference(day).inDays;
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  return day.year == today.year
      ? DateFormat.MMMEd().format(day)
      : DateFormat.yMMMEd().format(day);
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.ledger,
    required this.currency,
    required this.category,
  });

  final Entry entry;
  final GroupLedger ledger;
  final Currency? currency;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = ledger.me;
    final isSettlement = entry.row.kind == EntryKind.settlement;

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

    // The same arithmetic, described in the two different things it can mean.
    final myDeltaWords = isSettlement
        ? (myDelta > 0
              ? 'you paid ${formatMoneyAbs(currency, myDelta)}'
              : 'you received ${formatMoneyAbs(currency, myDelta)}')
        : (myDelta > 0
              ? 'you lent ${formatMoneyAbs(currency, myDelta)}'
              : 'you owe ${formatMoneyAbs(currency, myDelta)}');

    final payerNames = entry.payers
        .map((p) => ledger.nameOf(p.memberId))
        .join(', ');

    // The day is the header above; a time is worth saying only when known.
    final at = entry.row.occurredAt;
    final when = at == null ? '' : ' · ${DateFormat.jm().format(at.toLocal())}';
    final String subtitle;
    if (isSettlement) {
      final payee = entry.shares.isEmpty
          ? '—'
          : ledger.nameOf(entry.shares.first.memberId);
      subtitle = '$payerNames paid $payee$when';
    } else {
      subtitle = '$payerNames paid$when';
    }

    // A settlement in the tertiary role, so money changing hands reads apart
    // from money being spent.
    final (background, foreground) = isSettlement
        ? (scheme.tertiaryContainer, scheme.onTertiaryContainer)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);

    return ListTile(
      onTap: () => context.push('/g/${ledger.group.id}/e/${entry.id}'),
      leading: CircleAvatar(
        backgroundColor: background,
        foregroundColor: foreground,
        child: Icon(
          isSettlement
              ? Icons.handshake_outlined
              : categoryIcon(category?.icon ?? ''),
        ),
      ),
      title: Text(
        isSettlement && entry.row.description.isEmpty
            ? 'Settlement'
            : entry.row.description.isEmpty
            ? 'Expense'
            : entry.row.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatMoney(currency, entry.row.amountMinor),
            style: moneyStyle(Theme.of(context).textTheme.titleMedium!),
          ),
          if (me != null && myDelta != 0)
            BalanceAmount(
              balanceMinor: myDelta,
              text: myDeltaWords,
              semanticsLabel: myDeltaWords,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.receipt_long_outlined,
    title: 'Nothing yet',
    message: 'Add the first expense and balances appear straight away.',
  );
}
