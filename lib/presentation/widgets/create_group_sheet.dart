import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import 'currency_picker.dart';

Future<void> showCreateGroupSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => const _CreateGroupSheet(),
);

/// Naming a group, and — exactly once, ever — naming yourself.
///
/// The name field used to be unconditional, pre-filled from the account and
/// written back to it on save. That made one name editable from two places
/// with no indication that the second one was an account edit at all, and the
/// write-back ran *before* the group was created, so a profile save that failed
/// took the group down with it while still having changed the name. Reopening
/// the sheet then pre-filled the new name, the comparison matched, the save was
/// skipped, and the group appeared — which reads exactly like "it works the
/// second time" and is impossible to reason about.
///
/// Now the field is shown only when the account genuinely has no name, which
/// [Profile.displayName] can finally express, and answering it is understood as
/// the account edit it always was. Once there is a name there is nothing to
/// mismatch, because there is only one place holding it.
class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet();

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _name = TextEditingController();
  final _yourName = TextEditingController();
  String _currency = 'INR';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _yourName.dispose();
    super.dispose();
  }

  /// The account's name, or null if nobody has chosen one.
  ///
  /// Watched rather than read once in `initState`. The profile arrives from a
  /// database stream, so on the first frame there is nothing yet — reading it
  /// there is why the field could open blank for someone who did have a name.
  String? get _accountName {
    final name = ref.watch(myProfileProvider).value?.displayName?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  Future<void> _create(String? accountName) async {
    final groupName = _name.text.trim();
    // Whichever of the two is in play: the name already on the account, or the
    // one being given for the first time in the field below.
    final myName = accountName ?? _yourName.text.trim();
    if (groupName.isEmpty || myName.isEmpty) return;

    final accountId = ref.read(currentAccountIdProvider);
    if (accountId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // The group first, and the account second. Both orderings write the same
      // two things, but only this one cannot lose the group: creating it is
      // what the user asked for, and naming the account is a consequence.
      final created = await ref
          .read(groupRepositoryProvider)
          .createGroup(
            name: groupName,
            defaultCurrency: _currency,
            creatorDisplayName: myName,
            // What makes "you" findable among the members afterwards.
            creatorProfileId: accountId,
          );

      if (accountName == null) {
        await ref
            .read(myProfileControllerProvider.notifier)
            .save(displayName: myName);
      }

      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push('/g/${created.group.id}');
    } catch (error) {
      // Shown rather than swallowed. This used to have a bare `finally`, so
      // anything thrown here left the sheet open, the button live and no
      // explanation anywhere on screen.
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final accountName = _accountName;
    final needsName = accountName == null;
    final ready =
        _name.text.trim().isNotEmpty &&
        (!needsName || _yourName.text.trim().isNotEmpty);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New group', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Group name',
              hintText: 'Goa trip, Flat 4B, …',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (needsName) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _yourName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                // Said out loud, because it is true: this is not a field about
                // this group. Everyone in every group you join will see it,
                // and it is changed afterwards on the Account screen.
                helperText: 'How everyone in your groups will see you.',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 16),
          CurrencyPicker(
            value: _currency,
            label: 'Default currency',
            onChanged: (code) => setState(() => _currency = code),
          ),
          const SizedBox(height: 8),
          Text(
            'Expenses can be in any currency. This is only what totals are '
            'summarised in.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving || !ready ? null : () => _create(accountName),
            child: const Text('Create group'),
          ),
        ],
      ),
    );
  }
}
