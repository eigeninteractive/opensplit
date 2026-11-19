import 'dart:math' show max;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/clock_provider.dart';
import '../../application/ledger_providers.dart';
import '../../data/local/database.dart';
import '../../domain/analytics/spending.dart';
import '../../domain/calendar_date.dart';
import '../../domain/money_format.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/avatar_view.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_button.dart';
import '../widgets/page_body.dart';
import '../widgets/segmented_list.dart';

/// The days an insight covers.
typedef _Period = ({String label, DateTime? from, DateTime? to});

const _Period _allTime = (label: 'All time', from: null, to: null);

/// What a group spent: how much, on what, by whom and when.
///
/// Every figure is in one currency, because adding two together would need a
/// rate nobody agreed to, and every figure opens the expenses behind it.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  /// Whether the figures are your own shares rather than whole bills.
  bool _mine = false;
  String? _currency;
  _Period _period = _allTime;

  @override
  Widget build(BuildContext context) {
    final groupId = widget.groupId;
    final ledger = ref.watch(groupLedgerProvider(groupId));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/g/$groupId')),
        title: const Text('Insights'),
        actions: [ExportButton(groupId: groupId)],
      ),
      body: PageBody(
        child: ledger == null ? const SizedBox.shrink() : _body(ledger),
      ),
    );
  }

  Widget _body(GroupLedger ledger) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final categories = {
      for (final category
          in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id: category,
    };
    final used = _currenciesSpentIn(ledger);
    if (used.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'Nothing to show yet',
        message: 'Insights appear once the group has an expense.',
      );
    }

    final code = used.contains(_currency) ? _currency! : used.first;
    final me = ledger.me;
    final summary = SpendingSummary.of(
      ledger.entries,
      currency: code,
      memberId: _mine ? me?.id : null,
      from: _period.from,
      to: _period.to,
    );
    final view = _View(
      ledger: ledger,
      currency: currencies[code],
      categories: categories,
      summary: summary,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (me != null)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Group')),
                  ButtonSegment(value: true, label: Text('You')),
                ],
                selected: {_mine},
                onSelectionChanged: (selection) =>
                    setState(() => _mine = selection.single),
              ),
            _PeriodChip(
              today: calendarDay(ref.watch(clockProvider)()),
              period: _period,
              onChanged: (period) => setState(() => _period = period),
            ),
            if (used.length > 1)
              for (final option in used)
                ChoiceChip(
                  label: Text(option),
                  selected: option == code,
                  onSelected: (_) => setState(() => _currency = option),
                ),
          ],
        ),
        _Headline(view: view),
        if (summary.expenses.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'Nothing spent here',
              message: 'No expenses match these choices.',
            ),
          )
        else ...[
          _Categories(view: view),
          if (!_mine) _People(view: view),
          _OverTime(view: view),
          _Biggest(view: view),
        ],
      ],
    );
  }

  /// Currencies with any spending, most used first.
  static List<String> _currenciesSpentIn(GroupLedger ledger) {
    final counts = <String, int>{};
    for (final entry in ledger.entries) {
      if (!entry.isSpend) continue;
      counts[entry.row.currency] = (counts[entry.row.currency] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }
}

/// What every section draws from.
class _View {
  const _View({
    required this.ledger,
    required this.currency,
    required this.categories,
    required this.summary,
  });

  final GroupLedger ledger;
  final Currency? currency;
  final Map<String, Category> categories;
  final SpendingSummary summary;

  String money(int amountMinor) => formatMoney(currency, amountMinor);

  String categoryName(String id) => categories[id]?.name ?? 'Uncategorised';

  /// Lists [expenses] in a sheet, each opening its expense.
  void open(
    BuildContext context,
    String title,
    Iterable<CountedExpense> expenses,
  ) {
    final rows = expenses.toList()
      ..sort((a, b) => b.entry.row.entryDate.compareTo(a.entry.row.entryDate));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) =>
            _ExpenseSheet(view: this, title: title, rows: rows, scroll: scroll),
      ),
    );
  }
}

/// A chip naming the days covered, opening the choice of others.
class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.today,
    required this.period,
    required this.onChanged,
  });

  final DateTime today;
  final _Period period;
  final ValueChanged<_Period> onChanged;

  static List<_Period> _presets(DateTime today) => [
    _allTime,
    (
      label: 'This month',
      from: DateTime.utc(today.year, today.month),
      to: DateTime.utc(today.year, today.month + 1, 0),
    ),
    (
      label: 'Last month',
      from: DateTime.utc(today.year, today.month - 1),
      to: DateTime.utc(today.year, today.month, 0),
    ),
    (
      label: 'Last 30 days',
      from: today.subtract(const Duration(days: 29)),
      to: today,
    ),
  ];

  Future<void> _pickRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(today.year + 1, 12, 31),
      currentDate: today,
      initialDateRange: period.from == null || period.to == null
          ? null
          : DateTimeRange(start: period.from!, end: period.to!),
    );
    if (range == null) return;
    final from = calendarDay(range.start);
    final to = calendarDay(range.end);
    final format = DateFormat.MMMd();
    onChanged((
      label: '${format.format(from)} – ${format.format(to)}',
      from: from,
      to: to,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final preset in _presets(today))
          MenuItemButton(
            onPressed: () => onChanged(preset),
            child: Text(preset.label),
          ),
        MenuItemButton(
          onPressed: () => _pickRange(context),
          child: const Text('Choose dates…'),
        ),
      ],
      builder: (context, menu, _) => ActionChip(
        avatar: const Icon(Icons.event_outlined),
        label: Text(period.label),
        tooltip: 'Change the dates',
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

/// The figure the screen is about, and the few words that frame it.
class _Headline extends StatelessWidget {
  const _Headline({required this.view});

  final _View view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = view.summary;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final count = summary.expenses.length;
    final span = summary.span;
    final days = span == null ? 0 : span.last.difference(span.first).inDays + 1;
    final format = DateFormat.MMMd();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.memberId == null ? 'The group spent' : 'Your share',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            view.money(summary.totalMinor),
            style: moneyStyle(theme.textTheme.displaySmall!),
          ),
          const SizedBox(height: 4),
          if (span != null)
            Text(
              [
                '$count ${count == 1 ? 'expense' : 'expenses'}',
                days == 1
                    ? format.format(span.first)
                    : '${format.format(span.first)} – '
                          '${format.format(span.last)}',
                if (days > 1)
                  '${view.money((summary.totalMinor / days).round())} a day',
              ].join(' · '),
              style: muted,
            ),
          if (summary.paidMinor case final paid? when span != null)
            Text('You paid ${view.money(paid)} of the bills.', style: muted),
        ],
      ),
    );
  }
}

/// A section's heading, in the style of the lists elsewhere in a group.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// The fill and the colour drawn on it for the [index]th largest category.
///
/// The few biggest get a role of their own so the bar and the rows can be
/// matched by eye; the long tail shares a quiet one.
(Color, Color) _categoryColors(ColorScheme scheme, int index) =>
    switch (index) {
      0 => (scheme.primary, scheme.onPrimary),
      1 => (scheme.tertiary, scheme.onTertiary),
      2 => (scheme.secondary, scheme.onSecondary),
      3 => (scheme.primaryContainer, scheme.onPrimaryContainer),
      4 => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

/// Where the money went: one bar cut in proportion, then a row for each cut.
class _Categories extends StatelessWidget {
  const _Categories({required this.view});

  final _View view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = view.summary;
    final slices = summary.byCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Where it went'),
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                spacing: 2,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, slice) in slices.indexed)
                    Expanded(
                      flex: max(1, slice.amountMinor),
                      child: ColoredBox(
                        color: _categoryColors(scheme, index).$1,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedList(
          children: [
            for (final (index, slice) in slices.indexed)
              ListTile(
                onTap: () => view.open(
                  context,
                  view.categoryName(slice.key),
                  summary.expenses.where(
                    (e) => (e.entry.row.categoryId ?? '') == slice.key,
                  ),
                ),
                leading: CircleAvatar(
                  backgroundColor: _categoryColors(scheme, index).$1,
                  foregroundColor: _categoryColors(scheme, index).$2,
                  child: Icon(
                    categoryIcon(view.categories[slice.key]?.icon ?? ''),
                  ),
                ),
                title: Text(view.categoryName(slice.key)),
                subtitle: Text(
                  '${_percent(slice.amountMinor, summary.totalMinor)} · '
                  '${slice.entryCount} '
                  '${slice.entryCount == 1 ? 'expense' : 'expenses'}',
                ),
                trailing: _Amount(view.money(slice.amountMinor)),
              ),
          ],
        ),
      ],
    );
  }
}

String _percent(int part, int whole) {
  if (whole == 0) return '0%';
  final percent = part * 100 / whole;
  return percent > 0 && percent < 1 ? 'Under 1%' : '${percent.round()}%';
}

/// A row's trailing figure.
class _Amount extends StatelessWidget {
  const _Amount(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: moneyStyle(
        theme.textTheme.titleMedium!,
      ).copyWith(color: theme.colorScheme.onSurface),
    );
  }
}

/// What each person paid beside what they used.
class _People extends StatelessWidget {
  const _People({required this.view});

  final _View view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = view.summary;
    final ledger = view.ledger;
    final most = summary.byPerson
        .map((person) => max(person.paidMinor, person.shareMinor))
        .fold(0, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          'Who paid and who spent',
          detail:
              'Paid is what someone handed over. Share is what they '
              'used up.',
        ),
        SegmentedList(
          children: [
            for (final person in summary.byPerson)
              ListTile(
                onTap: () => view.open(
                  context,
                  ledger.nameOf(person.memberId),
                  summary.expenses.where(
                    (e) =>
                        e.entry.shares.any(
                          (share) => share.memberId == person.memberId,
                        ) ||
                        e.entry.payers.any(
                          (payer) => payer.memberId == person.memberId,
                        ),
                  ),
                ),
                leading: switch (ledger.memberById(person.memberId)) {
                  final member? => MemberAvatar(ledger: ledger, member: member),
                  null => null,
                },
                title: Text(
                  person.memberId == ledger.me?.id
                      ? 'You'
                      : ledger.nameOf(person.memberId),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    spacing: 4,
                    children: [
                      _Meter(
                        label: 'Paid',
                        amount: view.money(person.paidMinor),
                        fraction: most == 0 ? 0 : person.paidMinor / most,
                        color: scheme.primary,
                      ),
                      _Meter(
                        label: 'Share',
                        amount: view.money(person.shareMinor),
                        fraction: most == 0 ? 0 : person.shareMinor / most,
                        color: scheme.tertiary,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A labelled amount with a bar showing its size against the largest.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.amount,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String amount;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label $amount',
      excludeSemantics: true,
      child: Row(
        spacing: 8,
        children: [
          SizedBox(width: 44, child: Text(label)),
          Expanded(
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              color: color,
            ),
          ),
          // A common width, so the bars in a list end at the same place.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 88),
            child: Text(
              amount,
              textAlign: TextAlign.end,
              style: moneyStyle(theme.textTheme.bodyMedium!),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spending as a bar for each day, week or month.
class _OverTime extends StatelessWidget {
  const _OverTime({required this.view});

  final _View view;

  /// Narrower than this and the labels under the bars collide; wider and a
  /// chart of two bars is two slabs.
  static const _minBarWidth = 36.0;
  static const _maxBarWidth = 72.0;

  String _label(DateTime start) => switch (view.summary.interval) {
    SpendingInterval.day => DateFormat.MMMd().format(start),
    SpendingInterval.week => 'Week of ${DateFormat.MMMd().format(start)}',
    SpendingInterval.month => DateFormat.yMMM().format(start),
  };

  String _tick(DateTime start) => switch (view.summary.interval) {
    SpendingInterval.day => DateFormat.d().format(start),
    SpendingInterval.week => DateFormat.Md().format(start),
    SpendingInterval.month => DateFormat.MMM().format(start),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = view.summary;
    final slices = summary.overTime;
    final peak = slices.reduce(
      (a, b) => a.amountMinor >= b.amountMinor ? a : b,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          switch (summary.interval) {
            SpendingInterval.day => 'Day by day',
            SpendingInterval.week => 'Week by week',
            SpendingInterval.month => 'Month by month',
          },
          detail: 'Most: ${view.money(peak.amountMinor)}, ${_label(peak.key)}.',
        ),
        Material(
          color: scheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: Segment.radiusAt(index: 0, count: 1),
          ),
          child: SizedBox(
            height: 184,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final room = constraints.maxWidth - 16;
                final width = (room / slices.length).clamp(
                  _minBarWidth,
                  _maxBarWidth,
                );
                // The newest bars are the ones in view when there are more
                // than fit.
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: room),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final slice in slices)
                          SizedBox(
                            width: width,
                            child: _Bar(
                              fraction: peak.amountMinor == 0
                                  ? 0
                                  : slice.amountMinor / peak.amountMinor,
                              tick: _tick(slice.key),
                              label:
                                  '${_label(slice.key)}: '
                                  '${view.money(slice.amountMinor)}',
                              onTap: slice.entryCount == 0
                                  ? null
                                  : () => view.open(
                                      context,
                                      _label(slice.key),
                                      summary.expensesIn(slice.key),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// One bar of the chart over its tick label.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.tick,
    required this.label,
    required this.onTap,
  });

  /// 0…1 of the tallest bar.
  final double fraction;
  final String tick;

  /// What the bar says to a tooltip or a screen reader.
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Column(
            children: [
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  // An empty stretch keeps a sliver of bar, so it reads as
                  // nothing spent rather than as missing.
                  heightFactor: max(0.02, fraction.clamp(0.0, 1.0)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: fraction == 0
                          ? scheme.outlineVariant
                          : scheme.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: Text(
                  tick,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The few expenses that account for the most.
class _Biggest extends StatelessWidget {
  const _Biggest({required this.view});

  final _View view;

  @override
  Widget build(BuildContext context) {
    final rows = view.summary.expenses.toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Biggest expenses'),
        SegmentedList(
          children: [
            for (final row in rows.take(5)) _ExpenseTile(view: view, row: row),
          ],
        ),
      ],
    );
  }
}

/// One expense in a list of them, opening it.
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.view, required this.row});

  final _View view;
  final CountedExpense row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entry = row.entry;
    final category = view.categories[entry.row.categoryId];
    final payers = entry.payers
        .map(
          (payer) => payer.memberId == view.ledger.me?.id
              ? 'You'
              : view.ledger.nameOf(payer.memberId),
        )
        .join(', ');

    return ListTile(
      onTap: () => context.push('/g/${view.ledger.group.id}/e/${entry.id}'),
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(categoryIcon(category?.icon ?? '')),
      ),
      title: Text(
        entry.row.description.isEmpty ? 'Expense' : entry.row.description,
      ),
      subtitle: Text(
        '${DateFormat.MMMd().format(entry.row.entryDate)} · $payers paid',
      ),
      trailing: _Amount(view.money(row.amountMinor)),
    );
  }
}

/// The expenses behind one figure.
class _ExpenseSheet extends StatelessWidget {
  const _ExpenseSheet({
    required this.view,
    required this.title,
    required this.rows,
    required this.scroll,
  });

  final _View view;
  final String title;
  final List<CountedExpense> rows;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = rows.fold(0, (sum, row) => sum + row.amountMinor);

    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) => index == 0
          ? Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge),
                  Text(
                    '${view.money(total)} · ${rows.length} '
                    '${rows.length == 1 ? 'expense' : 'expenses'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : _ExpenseTile(view: view, row: rows[index - 1]),
    );
  }
}
