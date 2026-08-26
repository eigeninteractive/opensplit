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

  @override
  void initState() {
    super.initState();
    _yourName.text = ref.read(myProfileProvider).value?.displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _yourName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final yourName = _yourName.text.trim();
    if (name.isEmpty || yourName.isEmpty) return;

    setState(() => _saving = true);
    try {
      final accountId = ref.read(currentAccountIdProvider);
      if (accountId == null) return;

      // Typing a name here is editing your account, not naming yourself for
      // this group. There is one name now, and this is often the first place
      // anybody is asked for it.
      final profile = ref.read(myProfileProvider).value;
      if (profile?.displayName != yourName) {
        await ref
            .read(myProfileControllerProvider.notifier)
            .save(displayName: yourName, upiVpa: profile?.upiVpa);
      }

      final created = await ref
          .read(groupRepositoryProvider)
          .createGroup(
            name: name,
            defaultCurrency: _currency,
            ownerDisplayName: yourName,
            // Claims the owner slot, which is what makes "you" findable among
            // the members later.
            ownerProfileId: accountId,
          );

      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push('/g/${created.group.id}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);

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
          const SizedBox(height: 16),
          TextField(
            controller: _yourName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name'),
            onChanged: (_) => setState(() {}),
          ),
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
          const SizedBox(height: 20),
          FilledButton(
            onPressed:
                _saving ||
                    _name.text.trim().isEmpty ||
                    _yourName.text.trim().isEmpty
                ? null
                : _create,
            child: const Text('Create group'),
          ),
        ],
      ),
    );
  }
}
