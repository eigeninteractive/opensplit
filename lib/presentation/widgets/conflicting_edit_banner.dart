import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/repositories/drift_conflict_repository.dart';
import '../../domain/models/entry.dart';

/// Says that an edit was overtaken, and asks which version was meant.
///
/// Distinct from [UnsyncedChangesBanner] on purpose, in colour and in wording.
/// A dead letter means "this never reached anybody and something is wrong"; this
/// means "everybody has this expense, and your change to it was not the one that
/// landed". The first is an error. The second is two people editing at once,
/// which is ordinary — so it is coloured as information and asks a question
/// rather than reporting a fault.
///
/// It does not go away on its own. The whole point of the mechanism is that a
/// losing edit is never discarded silently, and a banner that timed out would
/// discard it silently a few seconds later.
class ConflictingEditBanner extends ConsumerWidget {
  const ConflictingEditBanner({super.key, this.padding = EdgeInsets.zero});

  /// Applied only when there is something to show, so an empty banner does not
  /// leave a gap where a caller placed it in a column.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(pendingConflictsProvider).value ?? const [];
    if (conflicts.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = conflicts.length;

    return Padding(
      padding: padding,
      child: MaterialBanner(
        backgroundColor: scheme.tertiaryContainer,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onTertiaryContainer,
        ),
        leading: Icon(
          Icons.merge_type_rounded,
          color: scheme.onTertiaryContainer,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count == 1
                  ? 'Your edit was overtaken'
                  : '$count edits were overtaken',
              style: text.titleSmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              count == 1
                  ? 'Somebody changed “${conflicts.single.attempted.description}” '
                        'while you were editing it. The group has their '
                        'version; yours is kept here.'
                  : 'Somebody changed them while you were editing. The group '
                        'has their versions; yours are kept here.',
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => _review(context, ref, conflicts.first),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    PendingConflict conflict,
  ) async {
    final choice = await showDialog<_Resolution>(
      context: context,
      builder: (context) => _ConflictDialog(conflict: conflict),
    );
    if (choice == null) return;

    final conflicts = ref.read(conflictRepositoryProvider);
    switch (choice) {
      case _Resolution.keepTheirs:
        await conflicts.forget(conflict.entryId);
      case _Resolution.useMine:
        // Written through the ordinary edit path, from the base the server
        // holds now — so if somebody has changed it *again* in the meantime,
        // this is refused again and parked again rather than quietly winning.
        //
        // The actor is this device's member row, so the feed line reads as an
        // edit by whoever resolved it. Null is a real answer here and is
        // recorded as one: a change nobody can be attributed to still belongs
        // on the record.
        final ledger = ref.read(groupLedgerProvider(conflict.groupId));
        await ref
            .read(entryRepositoryProvider)
            .reapply(conflict.attempted, actorId: ledger?.me?.id);
        await conflicts.forget(conflict.entryId);
    }
  }
}

enum _Resolution { useMine, keepTheirs }

/// The two versions, side by side, and nothing else.
///
/// Only money is shown. The server refuses a stale write exactly when the
/// amounts disagree, so that is what the question is about — listing a
/// description that both versions share would bury the one line that decides
/// it.
class _ConflictDialog extends StatelessWidget {
  const _ConflictDialog({required this.conflict});

  final PendingConflict conflict;

  @override
  Widget build(BuildContext context) {
    final current = conflict.current;

    return AlertDialog(
      title: Text(conflict.attempted.description),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!conflict.stillDisagrees) ...[
              Text(
                'This has since been changed back — the two versions now '
                'agree. Either choice keeps what you see in the group.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],
            _Version(
              label: 'The group has',
              entry: current,
              emptyNote: 'This expense is no longer on this device.',
            ),
            const SizedBox(height: 16),
            _Version(label: 'You wrote', entry: conflict.attempted),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_Resolution.keepTheirs),
          child: const Text('Keep theirs'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_Resolution.useMine),
          child: const Text('Use mine'),
        ),
      ],
    );
  }
}

class _Version extends StatelessWidget {
  const _Version({required this.label, required this.entry, this.emptyNote});

  final String label;
  final Entry? entry;
  final String? emptyNote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final version = entry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        if (version == null)
          Text(emptyNote ?? 'Nothing', style: text.bodyMedium)
        else ...[
          Text(
            '${version.currency} '
            '${(version.amountMinor / 100).toStringAsFixed(2)}',
            style: text.titleMedium,
          ),
          Text(
            version.description,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
