import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/models/group.dart';
import '../navigation.dart';
import '../widgets/page_body.dart';

/// Groups that have been put away, and the way back.
///
/// Archiving is not deleting and never was — the ledger is intact, the
/// balances still resolve, and an archived group can be opened, exported and
/// un-archived. Until this screen existed there was simply nowhere to see one:
/// the group list filters them out, and both the leave-group flow and the
/// server's dormancy job archive without asking, so a group could vanish from
/// the app with nothing anywhere to say where it went.
///
/// Adding an expense to an archived group un-archives it, on the device and on
/// the server alike, so this is a resting place rather than a state anyone has
/// to manage.
class ArchivedGroupsScreen extends ConsumerWidget {
  const ArchivedGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider(includeArchived: true)).value;
    final archived = [
      for (final group in groups ?? const <Group>[])
        if (group.isArchived) group,
    ]..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/')),
        title: const Text('Archived groups'),
      ),
      body: PageBody(
        child: archived.isEmpty
            ? const _Empty()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: archived.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => index == 0
                    ? const _Explanation()
                    : _ArchivedTile(group: archived[index - 1]),
              ),
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      'These are out of the way, not gone. Everything in them still adds up, '
      'and adding an expense brings one back by itself.',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ArchivedTile extends ConsumerWidget {
  const _ArchivedTile({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Card.outlined(
      child: ListTile(
        onTap: () => context.push('/g/${group.id}'),
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(
            Icons.inventory_2_outlined,
            color: scheme.onSurfaceVariant,
          ),
        ),
        title: Text(group.name),
        subtitle: Text(
          'Archived ${DateFormat.yMMMd().format(group.archivedAt!.toLocal())}',
        ),
        trailing: TextButton(
          onPressed: () => ref
              .read(groupRepositoryProvider)
              .setArchived(group.id, archived: false),
          child: const Text('Restore'),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        'Nothing is archived.',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
