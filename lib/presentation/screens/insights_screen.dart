import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/models/currency.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../format.dart';
import '../widgets/export_button.dart';

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/g/$groupId'),
        ),
        title: const Text('Insights'),
        actions: [ExportButton(groupId: groupId)],
      ),
      body: ledger == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search descriptions and notes',
                    suffixIcon: filter.query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () =>
                                controller.update(filter.copyWith(query: '')),
                          ),
                  ),
                  onChanged: (value) =>
                      controller.update(filter.copyWith(query: value)),
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
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Clear filters'),
                    ),
                  ),
                const SizedBox(height: 8),
                _Section(
                  title: 'By category',
                  buckets: ref.watch(spendByCategoryProvider(groupId)),
                  currencies: currencies,
                ),
                _Section(
                  title: 'By person',
                  subtitle:
                      'What each person consumed, not what they happened to pay.',
                  buckets: ref.watch(spendByMemberProvider(groupId)),
                  currencies: currencies,
                ),
                _Section(
                  title: 'Over time',
                  buckets: ref.watch(spendByMonthProvider(groupId)),
                  currencies: currencies,
                  sorted: false,
                ),
                const SizedBox(height: 8),
                _Results(groupId: groupId, currencies: currencies),
              ],
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
            label: Text(member.displayName),
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
    final scheme = Theme.of(context).colorScheme;

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
        Card(
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
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // A bar rather than a pie: comparing lengths is far
                        // easier than comparing angles, and it degrades
                        // gracefully to a screen reader.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: max == 0 ? 0 : bucket.amountMinor / max,
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
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

class _Results extends ConsumerWidget {
  const _Results({required this.groupId, required this.currencies});

  final String groupId;
  final Map<String, Currency> currencies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(analyticsFilterControllerProvider(groupId));
    if (!filter.isNarrowed) return const SizedBox.shrink();

    final results = ref.watch(analyticsResultsProvider(groupId)).value;
    if (results == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          '${results.length} matching ${results.length == 1 ? 'entry' : 'entries'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final entry in results)
                ListTile(
                  dense: true,
                  onTap: () => context.go('/g/$groupId/e/${entry.id}'),
                  title: Text(
                    entry.description.isEmpty ? 'Expense' : entry.description,
                  ),
                  subtitle: Text(DateFormat.yMMMd().format(entry.entryDate)),
                  trailing: Text(
                    formatMoney(currencies[entry.currency], entry.amountMinor),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
