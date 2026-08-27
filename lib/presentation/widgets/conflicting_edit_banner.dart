import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../data/repositories/drift_conflict_repository.dart';
import '../../domain/models/entry.dart';
import '../../domain/money_format.dart';

/// Says that an edit did not apply, and what the expense says instead.
///
/// Distinct from [UnsyncedChangesBanner] in colour and in wording, because they
/// mean opposite things. A dead letter says nobody else can see this. This says
/// everybody can see the expense — your change to it was just not the one that
/// landed. The first is a fault; the second is two people editing at once,
/// which is ordinary, so it is coloured as information.
///
/// It offers no way to re-apply the edit, and that is the design rather than an
/// omission. A one-tap "use mine" in a shared ledger is a button for
/// overwriting somebody's deliberate correction without reading it — the same
/// kind of silent, unexamined rewrite the server check exists to catch. So the
/// notice states both versions, which is usually enough to settle it on the
/// spot, and the only way to change the expense is the screen that changes
/// expenses.
///
/// It does not time out. The whole point is that a losing edit is never
/// discarded silently, and a banner that vanished on its own would discard it
/// silently a few seconds later.
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
    final first = conflicts.first;
    final count = conflicts.length;

    return Padding(
      padding: padding,
      child: MaterialBanner(
        backgroundColor: scheme.tertiaryContainer,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onTertiaryContainer,
        ),
        leading: Icon(
          Icons.published_with_changes_rounded,
          color: scheme.onTertiaryContainer,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count == 1
                  ? 'Your change to “${first.attempted.description}” did not '
                        'apply'
                  : '$count of your changes did not apply',
              style: text.titleSmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(_explain(ref, first, count)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(conflictRepositoryProvider).forget(first.entryId),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () =>
                context.go('/g/${first.groupId}/e/${first.entryId}'),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  /// The two amounts, in the group's own words.
  ///
  /// Amounts and not a field-by-field diff, because amounts are exactly what
  /// the server refuses over: an edit that moves no money is never refused, so
  /// if there is a notice at all, these two numbers are what differ.
  String _explain(WidgetRef ref, PendingConflict conflict, int count) {
    if (count > 1) {
      return 'Somebody else changed them first. The group has their versions, '
          'and yours were not applied.';
    }

    final mine = _money(ref, conflict.attempted);
    final theirs = conflict.current;

    if (theirs == null) {
      return 'You set it to $mine, but somebody else changed it first and it '
          'is no longer on this device.';
    }
    return 'You set it to $mine. Somebody else changed it first, so the group '
        'has ${_money(ref, theirs)}.';
  }

  /// The same formatter every other amount in the app goes through, so a
  /// notice about money reads like the money it is about.
  String _money(WidgetRef ref, Entry entry) => formatMoney(
    ref.watch(currenciesProvider).value?[entry.currency],
    entry.amountMinor,
  );
}
