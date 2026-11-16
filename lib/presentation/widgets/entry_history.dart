import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind;

import '../../application/ledger_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../domain/activity/activity_text.dart';
import '../../domain/models/group_event.dart';

/// What has already happened to this entry.
class EntryHistory extends ConsumerWidget {
  const EntryHistory({super.key, required this.entryId, required this.ledger});

  final String entryId;
  final GroupLedger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(entryActivityProvider(entryId)).value;
    if (events == null || events.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final categoryNames = {
      for (final category
          in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id: category.name,
    };

    // See the note in ActivityScreen: a build with nowhere to sync to must not
    // mark every line as unsynced.
    final syncs = ref.watch(syncEngineProvider) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('History', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        // Narrowed rather than switched: watchEntry asks only for this
        // expense's own snapshots, so anything else here would be a bug in the
        // query rather than a kind to render.
        for (final event in events.whereType<EntryChanged>())
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ledger.nameOfActor(event.actorId)} '
                  '${describeKind(event.kind, isPayment: event.snapshot?.kind == EntryKind.settlement)}'
                  '${syncs && event.isProvisional ? ' — not synced yet' : ''}',
                  style: theme.textTheme.bodyMedium,
                ),
                for (final change in event.changes)
                  Text(
                    describeChange(
                      change,
                      currency:
                          currencies[event.snapshot?.currency ??
                              ledger.group.defaultCurrency],
                      memberNames: ledger.memberNames,
                      categoryNames: categoryNames,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  DateFormat.yMMMd().add_jm().format(event.createdAt.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
