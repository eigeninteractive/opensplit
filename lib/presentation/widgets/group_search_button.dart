import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind;

import '../../application/ledger_providers.dart';
import '../../data/local/database.dart';
import '../../domain/models/entry.dart';
import '../../domain/money_format.dart';

/// Opens Material's search view over a group's local expenses and payments.
class GroupSearchButton extends StatelessWidget {
  const GroupSearchButton({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      viewHintText: 'Search descriptions and notes',
      builder: (context, controller) => IconButton(
        tooltip: 'Search expenses and payments',
        icon: const Icon(Icons.search),
        onPressed: controller.openView,
      ),
      // The result list is lazy and watches Drift while the search view is open.
      viewBuilder: (children) => Builder(
        builder: (context) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: children.firstOrNull ?? const SizedBox.shrink(),
          ),
        ),
      ),
      suggestionsBuilder: (_, controller) => [
        _SearchResults(
          groupId: groupId,
          query: controller.text,
          onSelected: (entry) {
            controller.closeView(null);
            GoRouter.of(context).push('/g/$groupId/e/${entry.id}');
          },
        ),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.groupId,
    required this.query,
    required this.onSelected,
  });

  final String groupId;
  final String query;
  final ValueChanged<Entry> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(groupLedgerProvider(groupId));
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    if (ledger == null || ledger.me?.isActive != true) {
      return const _SearchMessage('This group is no longer available.');
    }
    if (query.trim().isEmpty) {
      return const _SearchMessage(
        'Search descriptions and notes across this group’s expenses and payments.',
      );
    }
    final provider = groupSearchResultsProvider(groupId, query);
    final results = ref.watch(provider);
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _SearchMessage(
        'Couldn’t search this group.',
        action: TextButton(
          onPressed: () => ref.invalidate(provider),
          child: const Text('Try again'),
        ),
      ),
      data: (entries) => entries.isEmpty
          ? const _SearchMessage('No matching expenses or payments.')
          : ListView.builder(
              key: ValueKey(query),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              itemBuilder: (context, index) => _SearchResultTile(
                entry: entries[index],
                ledger: ledger,
                currency: currencies[entries[index].row.currency],
                onTap: () => onSelected(entries[index]),
              ),
            ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.entry,
    required this.ledger,
    required this.currency,
    required this.onTap,
  });

  final Entry entry;
  final GroupLedger ledger;
  final Currency? currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final payment = entry.row.kind == EntryKind.settlement;
    final payers = entry.payers.map((payer) => ledger.nameOf(payer.memberId));
    final recipients = entry.shares.map(
      (share) => ledger.nameOf(share.memberId),
    );
    final title = payment
        ? '${payers.join(', ')} paid ${recipients.join(', ')}'
        : entry.row.description.isEmpty
        ? 'Expense'
        : entry.row.description;
    final notes = entry.row.notes?.trim();
    final amount = formatMoney(
      currency,
      entry.row.amountMinor,
      withSymbol: false,
    );
    return ListTile(
      onTap: onTap,
      leading: Icon(
        payment ? Icons.handshake_outlined : Icons.receipt_long_outlined,
      ),
      title: Text(title),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notes != null && notes.isNotEmpty)
            Text(notes, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(
            '${DateFormat.yMMMd().format(entry.row.entryDate)} · '
            '${entry.row.currency} $amount',
          ),
        ],
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage(this.message, {this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}
