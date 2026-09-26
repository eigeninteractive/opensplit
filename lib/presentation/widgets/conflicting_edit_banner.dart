import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../data/repositories/drift_conflict_repository.dart';
import '../../domain/money_format.dart';

/// Says that an edit did not apply, and what the expense says instead.
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
  String _explain(WidgetRef ref, PendingConflict conflict, int count) {
    if (count > 1) {
      return 'Somebody else changed them first. The group has their versions, '
          'and yours were not applied.';
    }

    final mine = _money(
      ref,
      conflict.attempted.currency,
      conflict.attempted.amountMinor,
    );
    final theirs = conflict.current;

    if (theirs == null) {
      return 'You set it to $mine, but somebody else changed it first and it '
          'is no longer on this device.';
    }
    return 'You set it to $mine. Somebody else changed it first, so the group '
        'has ${_money(ref, theirs.currency, theirs.amountMinor)}.';
  }

  /// The same formatter every other amount in the app goes through, so a
  /// notice about money reads like the money it is about.
  String _money(WidgetRef ref, String currency, int amountMinor) =>
      formatMoney(ref.watch(currenciesProvider).value?[currency], amountMinor);
}
