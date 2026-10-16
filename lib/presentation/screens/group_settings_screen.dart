import 'dart:async';

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
import '../widgets/group_access.dart';
import '../widgets/segmented_list.dart';

/// Group settings and departure.
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
    if (name == null || name == ledger.group.name || !mounted) return;

    setState(() => _busy = true);
    try {
      final saved = await saveWithFeedback(context, () async {
        // Read again: the row may have changed while the dialog was open.
        final groups = ref.read(groupRepositoryProvider);
        final group = await groups.getGroup(widget.groupId);
        if (group == null) {
          throw StateError('This group is no longer available.');
        }
        await groups.updateGroup(group.copyWith(name: name));
      });
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Renamed')));
      }
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

  /// Leaving needs you settled up first, as removing anybody else does: a
  /// balance left behind would sit with somebody who can no longer see it.
  /// There are no roles, so there is nothing else to hand over.
  Future<void> _leave(GroupLedger ledger, Member me) async {
    final debts = _outstanding(ledger, me);
    if (debts.isNotEmpty) return _settleFirst(debts);
    final lastAccount = !ledger.members.any(
      (member) => member.id != me.id && member.profileId != null,
    );
    if (lastAccount && !ledger.isSettled) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Settle the group first'),
          content: const Text(
            'You are the last account holder. All balances, including people without accounts, must be settled before you can leave and delete the group.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this group?'),
        content: Text(
          lastAccount
              ? 'You are the last account holder. Leaving permanently deletes this group and its expenses. Export a copy first if you need one.'
              : 'Leaving ends your access on all your devices. Your expenses stay in the group for the remaining members. Export a copy first if you need one.',
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

    // Membership changes can unmount this screen before its save completes.
    final groups = ref.read(groupRepositoryProvider);
    final sync = ref.read(syncControllerProvider.notifier);
    final router = GoRouter.of(context);
    final groupId = widget.groupId;
    setState(() => _busy = true);
    try {
      final saved = await saveWithFeedback(
        context,
        () => groups.leaveGroup(memberId: me.id),
      );
      if (!saved) return;
      // Best effort: the leave is already recorded locally and queued, so an
      // unreachable server only delays it.
      router.go('/');
      await sync.syncGroup(groupId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Says why leaving has to wait, and offers the way to get there.
  Future<void> _settleFirst(List<String> debts) async {
    final settle = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settle up first'),
        content: Text(
          'You are not settled up in this group: ${debts.join(', ')}. Once '
          'nothing is owed either way, you can leave.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Settle up'),
          ),
        ],
      ),
    );
    if ((settle ?? false) && mounted) {
      unawaited(context.push('/g/${widget.groupId}/settle'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(groupLedgerProvider(widget.groupId));
    final scheme = Theme.of(context).colorScheme;

    if (ledger == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }

    if (ledger.me?.isActive != true) return const GroupUnavailableScreen();
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
            SegmentedList(
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Name'),
                  subtitle: Text(ledger.group.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || !ledger.canEdit
                      ? null
                      : () => _rename(ledger),
                ),
                ListTile(
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
                  onTap: ledger.canEdit
                      ? () => context.push('/g/${widget.groupId}/picture')
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 24),
            SegmentedList(
              children: [
                SwitchListTile(
                  value: ledger.group.simplifyDebts,
                  onChanged: _busy || !ledger.canEdit
                      ? null
                      : (value) => saveWithFeedback(
                          context,
                          () => ref
                              .read(groupRepositoryProvider)
                              .updateGroup(
                                ledger.group.copyWith(simplifyDebts: value),
                              ),
                        ),
                  title: const Text('Suggest the fewest payments'),
                  subtitle: const Text(
                    'Fewer payments, same balances. You may pay someone '
                    'you did not directly owe.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SegmentedList(
              children: [ExportButton.tile(groupId: widget.groupId)],
            ),
            const SizedBox(height: 24),

            if (!ledger.canEdit || me == null)
              Text(
                'Update OpenSplit to make changes.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              SegmentedList(
                children: [
                  ListTile(
                    leading: Icon(Icons.logout, color: scheme.error),
                    title: Text(
                      'Leave group',
                      style: TextStyle(color: scheme.error),
                    ),
                    subtitle: const Text(
                      'Export any records you want to keep first.',
                    ),
                    onTap: _busy ? null : () => _leave(ledger, me),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Leaving ends your access. Export a copy beforehand if you need it.',
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
