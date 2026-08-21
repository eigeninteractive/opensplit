import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/settle/upi.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _vpa;
  String? _vpaError;

  @override
  void initState() {
    super.initState();
    final identity = ref.read(localIdentityControllerProvider);
    _name = TextEditingController(text: identity.displayName);
    _vpa = TextEditingController(text: identity.upiVpa ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _vpa.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final vpa = _vpa.text.trim();
    if (vpa.isNotEmpty && !isValidUpiVpa(vpa)) {
      setState(() => _vpaError = 'That does not look like a UPI ID.');
      return;
    }
    setState(() => _vpaError = null);

    final controller = ref.read(localIdentityControllerProvider.notifier);
    await controller.setDisplayName(_name.text);
    await controller.setUpiVpa(vpa.isEmpty ? null : vpa);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('You', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name',
              helperText: 'How you appear to other people in a group.',
            ),
          ),
          const SizedBox(height: 24),
          Text('Payments', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _vpa,
            decoration: InputDecoration(
              labelText: 'UPI ID (optional)',
              hintText: 'you@bank',
              errorText: _vpaError,
              helperText:
                  'Lets people in your groups open their UPI app to pay you. '
                  'OpenSplit never handles the money.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const Divider(height: 48),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline),
            title: Text('Your data is on this device'),
            subtitle: Text(
              'Expenses are stored locally in SQLite. The app keeps working '
              'with what it has even if it can never reach a server again.',
            ),
            isThreeLine: true,
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.favorite_outline),
            title: Text('Free forever'),
            subtitle: Text(
              'Logging an expense is never gated, there are no ads, and no '
              'analytics SDK is present in this app.',
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}
