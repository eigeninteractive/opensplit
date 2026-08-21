import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/models/member.dart';

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(groupLedgerProvider(groupId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/g/$groupId'),
        ),
        title: const Text('People'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addMember(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add person'),
      ),
      body: ledger == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final member in ledger.members)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: member.isPlaceholder
                          ? scheme.surfaceContainerHighest
                          : scheme.primaryContainer,
                      child: Text(
                        member.displayName.characters.firstOrNull
                                ?.toUpperCase() ??
                            '?',
                        style: TextStyle(
                          color: member.isPlaceholder
                              ? scheme.onSurfaceVariant
                              : scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      member.displayName +
                          (member.id == ledger.me?.id ? ' (you)' : ''),
                    ),
                    subtitle: Text(
                      member.role == MemberRole.owner
                          ? 'Owner'
                          : member.isPlaceholder
                          // Blunt on purpose: a placeholder is a real member
                          // with real money attached, not a draft.
                          ? 'Added by someone here — no account yet'
                          : 'Member',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => switch (action) {
                        'rename' => _rename(context, ref, member),
                        'remove' => _remove(context, ref, member, ledger),
                        _ => null,
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        if (member.role != MemberRole.owner)
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove from group'),
                          ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Text(
                    'People without the app are full members: they can pay, '
                    'owe, and be settled with. When they join, they claim '
                    'their place and nothing about the history changes.',
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final name = await _promptForName(
      context,
      title: 'Add person',
      hint: 'Their name',
      helper: 'They do not need the app. You can invite them later.',
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(groupRepositoryProvider)
        .addMember(groupId, displayName: name);
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final name = await _promptForName(
      context,
      title: 'Rename',
      hint: 'Name',
      initial: member.displayName,
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(groupRepositoryProvider).renameMember(member.id, name);
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    Member member,
    GroupLedger ledger,
  ) async {
    final owes = ledger.balances.any(
      (b) => b.memberId == member.id && b.balanceMinor != 0,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${member.displayName}?'),
        content: Text(
          owes
              ? 'They still have an unsettled balance. Removing them keeps '
                    'every expense they were part of, and their balance stays '
                    'visible so it can be settled.'
              : 'Their past expenses stay exactly as they are. They just stop '
                    'being included in new ones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(groupRepositoryProvider).removeMember(member.id);
    }
  }
}

Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  required String hint,
  String? initial,
  String? helper,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: hint, helperText: helper),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
