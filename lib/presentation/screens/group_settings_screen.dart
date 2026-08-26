import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/models/member.dart';
import '../format.dart';
import '../navigation.dart';
import '../widgets/page_body.dart';

/// Renaming, archiving and leaving.
///
/// Everything here was reachable in the repository and from nowhere in the app,
/// which is the same as not existing. Changing the group's default currency is
/// still absent, and on purpose: every entry carries an fx snapshot taken
/// against the default of the day, so changing it later would restate every one
/// of those numbers against a currency they were never converted to.
class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  final _name = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _loadOnce(String name) {
    if (_loaded) return;
    _loaded = true;
    _name.text = name;
  }

  Future<void> _rename(GroupLedger ledger) async {
    final name = _name.text.trim();
    if (name.isEmpty || name == ledger.group.name) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(groupRepositoryProvider)
          .updateGroup(ledger.group.copyWith(name: name));
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
  ///
  /// Leaving with a balance outstanding is how a group's arithmetic stops
  /// making sense to everyone still in it, so it is named rather than hinted
  /// at.
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

  Future<void> _leave(GroupLedger ledger, Member me) async {
    final owners = ledger.members.where(
      (m) => m.role == MemberRole.owner && m.leftAt == null,
    );
    final others = ledger.members.where(
      (m) => m.id != me.id && m.leftAt == null,
    );

    if (me.role == MemberRole.owner &&
        owners.length == 1 &&
        others.isNotEmpty) {
      await _tell(
        'Make somebody else an owner first',
        'You are the only owner of this group. If you leave now, nobody left '
            'in it can add an owner, rename it or remove anyone.\n\n'
            'Open People, and make another member an owner.',
      );
      return;
    }

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
            onPressed: () => Navigator.of(context).pop(true),
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

  Future<void> _tell(String title, String body) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(groupLedgerProvider(widget.groupId));
    final scheme = Theme.of(context).colorScheme;

    if (ledger == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    _loadOnce(ledger.group.name);

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
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Group name'),
              onSubmitted: (_) => _rename(ledger),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : () => _rename(ledger),
                child: const Text('Save name'),
              ),
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
