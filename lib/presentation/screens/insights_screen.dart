import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/analytics/analytics_query.dart';
import '../../domain/models/currency.dart';
import '../format.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/export_button.dart';
import '../widgets/page_body.dart';

/// Spend analytics and search.
///
/// Everything here is local SQL over data already on the device: no endpoint,
/// no per-query cost, nothing to invalidate, and it all works with no
/// connection. Search in particular is something other apps have put behind a
/// paywall; here it is a query against a table the phone already holds.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(groupLedgerProvider(groupId));
    final filter = ref.watch(analyticsFilterControllerProvider(groupId));
    final controller = ref.read(
      analyticsFilterControllerProvider(groupId).notifier,
    );
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final used = ref.watch(groupCurrenciesProvider(groupId)).value ?? const [];

    // Analytics are per currency by construction; default to whichever the
    // group uses most rather than silently summing across rates.
    final active = filter.currency ?? (used.isEmpty ? null : used.first);
    if (filter.currency == null && active != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.update(filter.copyWith(currency: active)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/g/$groupId')),
        title: const Text('Insights'),
        actions: [ExportButton(groupId: groupId)],
      ),
      body: PageBody(
        child: ledger == null
            ? const SizedBox.shrink()
            // A CustomScrollView rather than a ListView because the search
            // results underneath are unbounded — every entry in the group can
            // match — and a ListView's children are all built at once. The
            // fixed part of the page is a handful of widgets, so it stays a
            // plain list; only the results need to be lazy. Nesting a second
            // scrollable would have been the other way to get there, and it is
            // the wrong one: two scroll positions in one gesture.
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverList.list(
                          children: [
                            // SearchBar is Material 3's search field: a
                            // pill-shaped bar on surfaceContainerHigh with its
                            // own elevation and leading/trailing slots. A
                            // TextField dressed up with a prefixIcon is the
                            // Material 2 way of drawing one.
                            SearchBar(
                              hintText: 'Search descriptions and notes',
                              leading: const Icon(Icons.search),
                              trailing: [
                                if (filter.query.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Clear search',
                                    onPressed: () => controller.update(
                                      filter.copyWith(query: ''),
                                    ),
                                  ),
                              ],
                              onChanged: (value) => controller.update(
                                filter.copyWith(query: value),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (used.length > 1)
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final code in used)
                                    ChoiceChip(
                                      label: Text(code),
                                      selected: active == code,
                                      onSelected: (_) => controller.update(
                                        filter.copyWith(currency: code),
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            _MemberFilter(
                              groupId: groupId,
                              filter: filter,
                              onChanged: controller.update,
                            ),
                            if (filter.isNarrowed)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: controller.reset,
                                  icon: const Icon(
                                    Icons.filter_alt_off_outlined,
                                  ),
                                  label: const Text('Clear filters'),
                                ),
                              ),
                            const SizedBox(height: 8),
                            _Section(
                              title: 'By category',
                              buckets: ref.watch(
                                spendByCategoryProvider(groupId),
                              ),
                              currencies: currencies,
                            ),
                            _Section(
                              title: 'By person',
                              subtitle:
                                  'What each person consumed, not what they '
                                  'happened to pay.',
                              buckets: ref.watch(
                                spendByMemberProvider(groupId),
                              ),
                              currencies: currencies,
                            ),
                            _Section(
                              title: 'Over time',
                              buckets: ref.watch(spendByMonthProvider(groupId)),
                              currencies: currencies,
                              sorted: false,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                        _Results(groupId: groupId, currencies: currencies),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MemberFilter extends ConsumerWidget {
  const _MemberFilter({
    required this.groupId,
    required this.filter,
    required this.onChanged,
  });

  final String groupId;
  final AnalyticsFilter filter;
  final ValueChanged<AnalyticsFilter> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(groupLedgerProvider(groupId));
    if (ledger == null) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      children: [
        for (final member in ledger.members)
          FilterChip(
            label: Text(ledger.nameOfMember(member)),
            selected: filter.memberId == member.id,
            onSelected: (selected) => onChanged(
              selected
                  ? filter.copyWith(memberId: member.id)
                  : filter.copyWith(clearMember: true),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.buckets,
    required this.currencies,
    this.subtitle,
    this.sorted = true,
  });

  final String title;
  final String? subtitle;
  final AsyncValue<List<SpendBucket>> buckets;
  final Map<String, Currency> currencies;
  final bool sorted;

  @override
  Widget build(BuildContext context) {
    final rows = buckets.value ?? const <SpendBucket>[];
    if (rows.isEmpty) return const SizedBox.shrink();

    final max = rows.map((b) => b.amountMinor).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final bucket in rows)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                bucket.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              formatMoney(
                                currencies[bucket.currency],
                                bucket.amountMinor,
                              ),
                              style: moneyStyle(
                                Theme.of(context).textTheme.bodyMedium!,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _ShareBar(
                          fraction: max == 0 ? 0 : bucket.amountMinor / max,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// How big one row is against the biggest row in its section.
///
/// A bar rather than a pie: comparing lengths is far easier than comparing
/// angles.
///
/// Not a [LinearProgressIndicator], which is what this used to be. That widget
/// means "this task is 40% finished" — it announces itself to assistive tech as
/// a progress bar, and Material's own styling for it is now a moving thing with
/// a gap and a stop indicator at the end of the track. None of that is true of
/// a spend figure, which is finished, static, and already stated in full as
/// text on the line above.
///
/// So this is drawn plainly, from the same scheme roles, and hidden from
/// assistive tech entirely: the label and the amount beside it already say
/// everything the bar is a picture of.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.fraction});

  /// 0…1 of the widest bar in this section.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: ColoredBox(color: scheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.groupId, required this.currencies});

  final String groupId;
  final Map<String, Currency> currencies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(analyticsFilterControllerProvider(groupId));
    if (!filter.isNarrowed) return const SliverToBoxAdapter();

    final results = ref.watch(analyticsResultsProvider(groupId)).value;
    if (results == null) return const SliverToBoxAdapter();

    // Slivers rather than widgets, so the rows are built as they are scrolled
    // to. There is no upper bound on how many entries a search matches.
    //
    // The rows are a plain divided list rather than the card the summary
    // sections above use. A card is a container for a bounded, glanceable
    // group, and it also cannot wrap a lazy list without hand-drawing its own
    // border — which is the thing this app just stopped doing. Material's own
    // pattern for a result set of unknown length is a list on the surface.
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              '${results.length} matching '
              '${results.length == 1 ? 'entry' : 'entries'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        SliverList.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = results[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push('/g/$groupId/e/${entry.id}'),
              title: Text(
                entry.description.isEmpty ? 'Expense' : entry.description,
              ),
              subtitle: Text(DateFormat.yMMMd().format(entry.entryDate)),
              trailing: Text(
                formatMoney(currencies[entry.currency], entry.amountMinor),
                style: moneyStyle(Theme.of(context).textTheme.bodyMedium!),
              ),
            );
          },
        ),
      ],
    );
  }
}
