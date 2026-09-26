import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../feedback.dart';
import '../navigation.dart';

import '../widgets/page_body.dart';
import '../../application/providers.dart';
import '../../domain/models/member.dart';
import '../../domain/settle/upi.dart';
import '../widgets/group_link_sheet.dart';
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
        leading: BackButton(onPressed: () => goBack(context, '/g/$groupId')),
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
                  // Above the list rather than in a menu, because it is what
                  // somebody who has just made a group came here to do.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: FilledButton.tonalIcon(
                      onPressed: () => showGroupLinkSheet(context, groupId),
                      icon: const Icon(Icons.link),
                      label: const Text('Share an invite link'),
                    ),
                  ),
                  for (final member in ledger.members)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: member.isPlaceholder
                            ? scheme.surfaceContainerHighest
                            : scheme.primaryContainer,
                        foregroundColor: member.isPlaceholder
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimaryContainer,
                        child: Text(
                          ledger
                                  .nameOfMember(member)
                                  .characters
                                  .firstOrNull
                                  ?.toUpperCase() ??
                              '?',
                        ),
                      ),
                      title: Text(
                        ledger.nameOfMember(member) +
                            (member.id == ledger.me?.id ? ' (you)' : ''),
                      ),
                      subtitle: Text(
                        ledger.upiOf(member) != null
                            // The handle is the useful thing to see at a glance
                            // here: it is what makes settling with this person
                            // one tap instead of a chat message asking for it.
                            ? ledger.upiOf(member)!
                            : member.isPlaceholder
                            // Blunt on purpose: a placeholder is a real member
                            // with real money attached, not a draft.
                            ? 'Added by someone here — no account yet'
                            : 'Member',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => switch (action) {
                          'invite' => showInviteSheet(context, ref, member),
                          'me' => context.go('/account'),
                          'rename' => _rename(context, ref, member),
                          'upi' => _setUpi(context, ref, member),
                          'remove' => _remove(context, ref, member, ledger),
                          _ => null,
                        },
                        // Only placeholders can be renamed or given a payment
                        // handle here, and that is not a permission rule — it
                        // is what the fields are.
                        itemBuilder: (context) {
                          final mine = member.id == ledger.me?.id;

                          // Your own row, or a placeholder's.
                          final editable = member.isPlaceholder || mine;

                          // Removing somebody also cuts off their access to the
                          // group, so it is offered only once nothing is owed
                          // either way.
                          final removable =
                              !mine && ledger.isSettledUp(member.id);

                          return [
                            if (member.isPlaceholder)
                              const PopupMenuItem(
                                value: 'invite',
                                child: Text('Send invite link'),
                              ),
                            if (member.isPlaceholder && editable) ...[
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
                            ],
                            if (mine)
                              const PopupMenuItem(
                                value: 'me',
                                child: Text('Edit your name and UPI ID'),
                              ),
                            if (removable)
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove from group'),
                              )
                            // Said rather than silently withheld: an absent
                            // menu item reads as a bug, and the reason here is
                            // something the group can act on.
                            else if (!mine)
                              PopupMenuItem(
                                enabled: false,
                                child: Text(
                                  '${ledger.nameOfMember(member)} is not '
                                  'settled up',
                                ),
                              ),
                          ];
                        },
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
        title: Text('Remove ${ledger.nameOfMember(member)}?'),
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
            onPressed: () {
              confirmedIrreversibly();
              Navigator.of(context).pop(true);
            },
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

/// Asks for a person's name, in a sheet rather than a dialog.
Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  required String hint,
  String? initial,
  String? helper,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) =>
      _NameSheet(title: title, hint: hint, initial: initial, helper: helper),
);

class _NameSheet extends StatefulWidget {
  const _NameSheet({
    required this.title,
    required this.hint,
    this.initial,
    this.helper,
  });

  final String title;
  final String hint;
  final String? initial;
  final String? helper;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => Padding(
    // Lifts the sheet clear of the keyboard rather than letting it sit
    // underneath one.
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.hint,
            // Room to say the whole thing. A sheet has the height for it, and
            // this is the sentence that explains what a placeholder is.
            helperText: widget.helper,
            helperMaxLines: 3,
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    ),
  );
}

/// Collects a UPI ID, validating it before it is stored.
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
