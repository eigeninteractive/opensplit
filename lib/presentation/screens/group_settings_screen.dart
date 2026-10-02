import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/ledger_providers.dart';
import '../../application/local_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../domain/avatar.dart';
import '../../domain/money_format.dart';
import '../feedback.dart';
import '../navigation.dart';
import '../widgets/avatar_view.dart';
import '../widgets/export_button.dart';
import '../widgets/page_body.dart';

/// Renaming, archiving and leaving.
class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  bool _busy = false;

  /// Asks for the new name in a dialog, which holds its own copy only while
  /// it is open; the screen itself shows the stored name.
  Future<void> _rename(GroupLedger ledger) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(current: ledger.group.name),
    );
    if (name == null || name == ledger.group.name) return;

    setState(() => _busy = true);
    try {
      // Read again: the row may have changed while the dialog was open.
      final groups = ref.read(groupRepositoryProvider);
      final group = await groups.getGroup(widget.groupId);
      if (group == null) return;
      await groups.updateGroup(group.copyWith(name: name));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Renamed')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setArchived(
    GroupLedger ledger, {
    required bool archived,
  }) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(groupRepositoryProvider)
          .setArchived(widget.groupId, archived: archived);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// What this member still owes or is owed, per currency, in words.
  List<String> _outstanding(GroupLedger ledger, Member me) {
    // read, not watch: this is called from a button handler, not from build,
    // and watching outside build subscribes a widget that is not rebuilding.
    final currencies = ref.read(currenciesProvider).value ?? const {};
    return [
      for (final code in ledger.activeCurrencies)
        if (ledger.balanceOf(me.id, code) != 0)
          formatMoney(
            currencies[code],
            ledger.balanceOf(me.id, code),
            alwaysSigned: true,
          ),
    ];
  }

  /// Leaving is always available, settled or not. There are no roles, so there
  /// is nothing to hand over first.
  Future<void> _leave(GroupLedger ledger, Member me) async {
    final debts = _outstanding(ledger, me);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this group?'),
        content: Text(
          [
            'You stop getting updates, and you will not appear in new '
                'expenses.',
            if (debts.isNotEmpty)
              'You are not settled up: ${debts.join(', ')}. Leaving does not '
                  'clear that — it stays in the group\'s history for everyone '
                  'still in it.',
            'Everything you have already paid for or owed stays exactly as it '
                'is. This device keeps a copy, archived and read-only.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () {
              confirmedIrreversibly();
              Navigator.of(context).pop(true);
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(groupRepositoryProvider)
          .leaveGroup(groupId: widget.groupId, memberId: me.id);
      // Best effort: the leave is already recorded locally and queued, so an
      // unreachable server only delays it.
      await ref.read(syncControllerProvider.notifier).syncGroup(widget.groupId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) goBack(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(groupLedgerProvider(widget.groupId));
    final scheme = Theme.of(context).colorScheme;

    if (ledger == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }

    final archived = ledger.group.archivedAt != null;
    final me = ledger.me;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => goBack(context, '/g/${widget.groupId}'),
        ),
        title: const Text('Group settings'),
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Name'),
              subtitle: Text(ledger.group.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _rename(ledger),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AvatarView(
                avatar: ledger.group.avatar,
                name: ledger.group.name,
                id: ledger.group.id,
              ),
              title: const Text('Picture'),
              subtitle: Text(switch (ledger.group.avatar) {
                EmojiAvatar() => 'An emoji',
                IconAvatar() => 'An icon',
                InitialsAvatar() || PhotoAvatar() => 'Its initials',
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/g/${widget.groupId}/picture'),
            ),

            const Divider(height: 40),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.ios_share),
              title: const Text('Export this group'),
              subtitle: const Text(
                'A spreadsheet to read, or a full backup that keeps every '
                'split, rate and change.',
              ),
              isThreeLine: true,
              trailing: ExportButton(groupId: widget.groupId),
            ),

            const Divider(height: 40),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ledger.group.simplifyDebts,
              onChanged: _busy
                  ? null
                  : (value) => ref
                        .read(groupRepositoryProvider)
                        .updateGroup(
                          ledger.group.copyWith(simplifyDebts: value),
                        ),
              title: const Text('Suggest the fewest payments'),
              subtitle: const Text(
                'Nets debts down to as few transfers as settle the group. The '
                'individual debts underneath are unchanged either way.',
              ),
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: archived,
              onChanged: _busy
                  ? null
                  : (value) => _setArchived(ledger, archived: value),
              title: const Text('Archive'),
              subtitle: const Text(
                'Hides it from your list. Nothing is deleted, everyone stays '
                'in it, and un-archiving brings it straight back.',
              ),
            ),

            const Divider(height: 40),

            if (me == null)
              Text(
                'You are not a member of this group, so there is nothing here '
                'to leave.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text(
                  'Leave group',
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: const Text(
                  'Your past expenses stay in the group. You stop appearing in '
                  'new ones.',
                ),
                onTap: _busy ? null : () => _leave(ledger, me),
              ),
              const SizedBox(height: 8),
              Text(
                'A group cannot be deleted once it has expenses in it, by '
                'design — somebody else\'s record of who paid for what is not '
                'yours to remove. Archive it instead.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One field and two buttons, the size of the change it makes.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.current);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename group'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Group name'),
        validator: (value) =>
            (value ?? '').trim().isEmpty ? 'A group needs a name.' : null,
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Rename')),
    ],
  );
}
