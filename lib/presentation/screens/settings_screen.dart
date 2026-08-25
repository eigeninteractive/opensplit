import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/page_body.dart';
import '../../application/providers.dart';
import '../../config.dart';
import '../../domain/settle/upi.dart';
import '../widgets/account_section.dart';

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
      body: PageBody(
        child: ListView(
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
            // Hidden entirely rather than shown broken when the build has
            // no FCM credentials, matching how every other integration behaves
            // here.
            if (hasPush) ...[
              const Divider(height: 48),
              const _NotificationSetting(),
            ],
            const Divider(height: 48),
            const AccountSection(),
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
      ),
    );
  }
}

/// The switch that governs whether this device is told about group activity.
///
/// This is the only place the app asks for notification permission unprompted,
/// and it asks only when the switch is turned on — a deliberate action, taken
/// on a screen the user navigated to. Nothing about launching the app produces
/// a system dialog.
class _NotificationSetting extends ConsumerStatefulWidget {
  const _NotificationSetting();

  @override
  ConsumerState<_NotificationSetting> createState() =>
      _NotificationSettingState();
}

class _NotificationSettingState extends ConsumerState<_NotificationSetting> {
  bool _busy = false;

  Future<void> _toggle(bool wanted) async {
    setState(() => _busy = true);
    try {
      final controller = ref.read(notificationPreferenceProvider.notifier);
      if (!wanted) {
        await controller.disable();
        return;
      }

      final granted = await controller.enable();
      if (!mounted || granted) return;

      // The switch springs back, because it would otherwise claim a state the
      // OS has refused. Android stops showing the dialog after a second
      // refusal, so "try again" is not useful advice — system settings is.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Android did not grant permission. You can turn notifications on '
            'for OpenSplit in system settings.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(notificationPreferenceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: _busy ? null : _toggle,
          title: const Text('Tell me about group activity'),
          subtitle: const Text(
            'A quiet notification when someone adds an expense or settles up. '
            'The message is put together on your device — the server only '
            'sends an id, never an amount.',
          ),
          isThreeLine: true,
        ),
      ],
    );
  }
}
