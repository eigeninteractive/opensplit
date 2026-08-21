import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/page_body.dart';
import '../../application/providers.dart';
import '../../domain/models/member.dart';
import '../../domain/settle/upi.dart';
import '../widgets/invite_sheet.dart';

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
      body: PageBody(
        child: ledger == null
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
                        member.upiVpa != null
                            // The handle is the useful thing to see at a glance
                            // here: it is what makes settling with this person
                            // one tap instead of a chat message asking for it.
                            ? member.upiVpa!
                            : member.role == MemberRole.owner
                            ? 'Owner'
                            : member.isPlaceholder
                            // Blunt on purpose: a placeholder is a real member
                            // with real money attached, not a draft.
                            ? 'Added by someone here — no account yet'
                            : 'Member',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => switch (action) {
                          'invite' => showInviteSheet(context, ref, member),
                          'rename' => _rename(context, ref, member),
                          'upi' => _setUpi(context, ref, member),
                          'remove' => _remove(context, ref, member, ledger),
                          _ => null,
                        },
                        itemBuilder: (context) => [
                          if (member.isPlaceholder)
                            const PopupMenuItem(
                              value: 'invite',
                              child: Text('Send invite link'),
                            ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          PopupMenuItem(
                            value: 'upi',
                            child: Text(
                              member.upiVpa == null
                                  ? 'Add UPI ID'
                                  : 'Change UPI ID',
                            ),
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

  /// Records a UPI handle for a member of this group.
  ///
  /// Available for everyone, not just placeholders: the person who set up the
  /// group often knows a flatmate's UPI ID long before that flatmate gets round
  /// to filling in their own profile.
  Future<void> _setUpi(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final controller = TextEditingController(text: member.upiVpa ?? '');
    final saved = await showDialog<String?>(
      context: context,
      builder: (context) =>
          _UpiDialog(controller: controller, displayName: member.displayName),
    );
    controller.dispose();
    if (saved == null) return;

    await ref
        .read(groupRepositoryProvider)
        .setMemberUpiVpa(member.id, saved.isEmpty ? null : saved);
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

/// Collects a UPI ID, validating it before it is stored.
///
/// Validated here as well as in the repository and again by a check constraint
/// on the server. A handle that is wrong is worse than one that is missing:
/// the payment app opens, looks entirely normal, and the money goes nowhere or
/// to a stranger.
class _UpiDialog extends StatefulWidget {
  const _UpiDialog({required this.controller, required this.displayName});

  final TextEditingController controller;
  final String displayName;

  @override
  State<_UpiDialog> createState() => _UpiDialogState();
}

class _UpiDialogState extends State<_UpiDialog> {
  String? _error;

  void _submit() {
    final value = widget.controller.text.trim();
    if (value.isNotEmpty && !isValidUpiVpa(value)) {
      setState(() => _error = 'That does not look like a UPI ID.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('UPI ID for ${widget.displayName}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'UPI ID',
            hintText: 'name@bank',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Used to open a payment app when settling up. Leave it empty to '
          'remove it. OpenSplit never handles the money.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
