import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/models/profile.dart';
import '../../domain/settle/upi.dart';
import '../widgets/account_section.dart';
import '../widgets/page_body.dart';

/// Who you are, in one place.
///
/// Everything here used to be somewhere else and worse. Linking an account was
/// three quarters of the way down Settings, below the notification switch —
/// the wrong place for the one action that decides whether somebody's data
/// survives losing their phone. The name and payment handle were device
/// preferences mirrored into a profile row and copied again into every group's
/// member row, so a rename was three writes that nothing kept in step, and it
/// never reached the people who actually see the name.
///
/// One name now, on the account, read by everybody who shares a group with you.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _name = TextEditingController();
  final _vpa = TextEditingController();

  /// Seeded once, from the first profile that arrives. Re-seeding on every
  /// build would fight whoever is typing.
  bool _seeded = false;
  bool _saving = false;
  String? _vpaError;

  @override
  void dispose() {
    _name.dispose();
    _vpa.dispose();
    super.dispose();
  }

  void _seed(Profile? profile) {
    if (_seeded || profile == null) return;
    _seeded = true;
    _name.text = profile.displayName;
    _vpa.text = profile.upiVpa ?? '';
  }

  Future<void> _save() async {
    final vpa = _vpa.text.trim();
    if (vpa.isNotEmpty && !isValidUpiVpa(vpa)) {
      setState(() => _vpaError = 'That does not look like a UPI ID.');
      return;
    }
    setState(() {
      _vpaError = null;
      _saving = true;
    });
    try {
      await ref
          .read(myProfileControllerProvider.notifier)
          .save(displayName: _name.text, upiVpa: vpa);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This device keeps nothing: the groups and expenses stored here are '
          'removed, so whoever uses it next cannot read them.\n\n'
          'Everything is on the server under your account, and signing back '
          'in brings it all down again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider).value;
    final profile = ref.watch(myProfileProvider).value;
    _seed(profile);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // The prompt to attach a real account, when there is not one yet.
            // Renders nothing once there is, rather than becoming a permanent
            // banner about a settled question.
            const AccountSection(),

            if (account != null && !account.isAnonymous)
              const SizedBox(height: 8),

            const Divider(height: 40),

            Text('Your name', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'What everybody in your groups sees. Changing it here changes it '
              'everywhere, including for them.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),

            const SizedBox(height: 32),
            Text('Getting paid', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _vpa,
              decoration: InputDecoration(
                labelText: 'UPI ID (optional)',
                hintText: 'you@bank',
                errorText: _vpaError,
                helperText:
                    'Lets people in your groups open their UPI app to pay '
                    'you. OpenSplit never handles the money.',
                helperMaxLines: 3,
              ),
            ),

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),

            if (account != null) ...[
              const Divider(height: 48),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text(
                  'Sign out',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: Text(
                  account.isAnonymous
                      ? 'You are a guest, so there is nothing to sign back in '
                            'with. Signing out deletes everything on this '
                            'device permanently.'
                      : 'Removes this device\'s copy. Sign back in to get it '
                            'again.',
                  style: theme.textTheme.bodySmall,
                ),
                isThreeLine: account.isAnonymous,
                onTap: _signOut,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
