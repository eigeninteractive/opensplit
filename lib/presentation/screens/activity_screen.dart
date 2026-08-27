import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/activity/activity_text.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry_event.dart';
import '../navigation.dart';
import '../widgets/page_body.dart';

/// What has happened to this group's expenses, and who did it.
///
/// The reason editing in place is safe. Without this, correcting ₹400 to ₹300
/// two days later silently moves somebody else's balance with nothing anywhere
/// to say why or who — which is a trust problem rather than a data one, and the
/// kind that surfaces as an argument rather than a bug report.
///
/// Rendered from the local database like every other screen, from snapshots the
/// server wrote: each records what an expense looked like after a change, and
/// the lines below are the difference between consecutive ones.
///
/// Two properties matter here and they pull in opposite directions. The record
/// has to be trustworthy, so no client writes it — the table has no insert,
/// update or delete grant, and a trigger is its only writer. And the feed has
/// to work with no network, because the one screen whose job is to say what
/// happened must not be the one screen that needs a server to do it. So the
/// device also writes a provisional snapshot as it saves, marked as such on
/// screen and discarded the moment the server's account of the same expense
/// arrives.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(groupActivityProvider(groupId)).value;
    final ledger = ref.watch(groupLedgerProvider(groupId));

    // Only worth saying when there is somewhere for a line to be going. A
    // build with no backend at all -- a guest, a local-only install -- never
    // syncs anything, so marking every line "not synced yet" would be noise
    // that never resolves rather than information.
    final syncs = ref.watch(syncEngineProvider) != null;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/g/$groupId')),
        title: const Text('Activity'),
      ),
      body: PageBody(
        child: switch (events) {
          null => const Center(child: CircularProgressIndicator()),
          [] => _Empty(),
          _ => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: events.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = events[index];
              return _Line(
                event: event,
                actor: ledger?.nameOfActor(event.actorId) ?? 'Someone',
                memberNames: ledger?.memberNames ?? const {},
                pending: syncs && event.isProvisional,
                description: ledger?.entries
                    .where((e) => e.id == event.entryId)
                    .firstOrNull
                    ?.description,
                currency: ledger == null
                    ? null
                    : ref
                          .watch(currenciesProvider)
                          .value?[ledger.group.defaultCurrency],
              );
            },
          ),
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.event,
    required this.actor,
    required this.memberNames,
    required this.pending,
    required this.description,
    required this.currency,
  });

  final EntryEvent event;
  final String actor;
  final Map<String, String> memberNames;

  /// This device's own account of a change the server has not confirmed.
  final bool pending;
  final String? description;
  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final what = (description?.trim().isNotEmpty ?? false)
        ? '“${description!.trim()}”'
        : 'an expense';

    return ListTile(
      leading: Icon(_icon(event.kind), color: theme.colorScheme.primary),
      title: Text(
        '$actor ${describeKind(event.kind)} $what'
        '${pending ? ' — not synced yet' : ''}',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final change in event.changes)
            Text(
              describeChange(
                change,
                currency: currency,
                memberNames: memberNames,
              ),
              style: theme.textTheme.bodySmall,
            ),
          Text(
            _when(event.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: event.changes.isNotEmpty,
    );
  }

  static IconData _icon(EntryEventKind kind) => switch (kind) {
    EntryEventKind.created => Icons.add_circle_outline,
    EntryEventKind.edited => Icons.edit_outlined,
    EntryEventKind.deleted => Icons.remove_circle_outline,
    EntryEventKind.restored => Icons.restore,
  };

  /// Relative for the recent past, absolute once "3 days ago" stops being the
  /// more useful of the two.
  static String _when(DateTime at) {
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inHours < 1) return '${ago.inMinutes} min ago';
    if (ago.inDays < 1) return '${ago.inHours}h ago';
    if (ago.inDays < 7) return '${ago.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing has happened here yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Every expense added, edited or deleted in this group shows up '
              'here, with who did it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
