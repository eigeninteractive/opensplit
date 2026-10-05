import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/ledger_providers.dart';
import '../../application/local_providers.dart';
import '../../data/repositories/drift_group_repository.dart';
import '../navigation.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_body.dart';

/// Groups that have been put away or left, and the way back.
class ArchivedGroupsScreen extends ConsumerWidget {
  const ArchivedGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(groupListingsProvider).value;
    final archived = [
      for (final listing in listings ?? const <GroupListing>[])
        if (!listing.isCurrent) listing,
    ];

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
                    : _ArchivedTile(listing: archived[index - 1]),
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
      'and adding an expense brings one back by itself. Groups you left are '
      'here too, read-only: a link from somebody still in one brings you '
      'back.',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ArchivedTile extends ConsumerWidget {
  const _ArchivedTile({required this.listing});

  final GroupListing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final group = listing.group;

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
          listing.hasLeft
              // A link from somebody still in it is the way back, not a button.
              ? 'You left · read-only'
              : 'Archived ${DateFormat.yMMMd().format(group.archivedAt!.toLocal())}',
        ),
        trailing: listing.hasLeft
            ? null
            : TextButton(
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
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.inventory_2_outlined,
    title: 'Nothing is archived',
    message:
        'Archiving a group puts it out of the way without deleting any of '
        'it. Nothing here has been put away yet.',
  );
}
