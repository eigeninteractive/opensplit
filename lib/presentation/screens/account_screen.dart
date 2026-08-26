import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/models/profile.dart';
import '../../domain/settle/upi.dart';
import '../widgets/account_section.dart';
import '../widgets/page_body.dart';
import '../router.dart';

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

  /// Seeded once, from the first profile that arrives. Re-seeding would fight
  /// whoever is typing.
  bool _seeded = false;
  bool _saving = false;
  bool _deleting = false;
  String? _nameError;
  String? _vpaError;

  @override
  void initState() {
    super.initState();
    // Filling a form from asynchronous data is initialisation, not something to
    // do while building: writing to a controller notifies the field attached to
    // it, and doing that from inside a build is how a widget ends up marking
    // itself dirty mid-frame. listenManual fires once with whatever is already
    // known and again when the profile lands, runs outside the build phase, and
    // unsubscribes with the widget.
    ref.listenManual(
      myProfileProvider,
      (_, next) => _seed(next.value),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _vpa.dispose();
    super.dispose();
  }

  /// No setState: the controllers notify the fields bound to them, which is the
  /// only thing on screen that any of this changes.
  void _seed(Profile? profile) {
    if (_seeded || profile == null) return;
    _seeded = true;
    _name.text = profile.displayName;
    _vpa.text = profile.upiVpa ?? '';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final vpa = _vpa.text.trim();

    // Refused here as well as by the column's own CHECK, because a blank name
    // is not a visible error: GroupLedger.nameOfMember falls back to the member
    // row, so the field would look saved while the name quietly stopped
    // travelling to anybody else.
    if (name.isEmpty) {
      setState(() => _nameError = 'Your name cannot be blank.');
      return;
    }
    if (vpa.isNotEmpty && !isValidUpiVpa(vpa)) {
      setState(() => _vpaError = 'That does not look like a UPI ID.');
      return;
    }
    setState(() {
      _nameError = null;
      _vpaError = null;
      _saving = true;
    });
    try {
      await ref
          .read(myProfileControllerProvider.notifier)
          .save(displayName: name, upiVpa: vpa);
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

  /// Deletes the account, after saying precisely what that costs.
  ///
  /// Two steps rather than one, and the second names numbers. Play requires
  /// this to be reachable in the app rather than only by email, which means it
  /// sits a few taps from a screen people open to change their name — so the
  /// only protection against a mis-tap is a dialog nobody could confirm by
  /// accident.
  Future<void> _deleteAccount() async {
    final impact = await ref.read(deletionImpactProvider.future);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This cannot be undone.'),
            const SizedBox(height: 16),
            if (impact.solo > 0)
              _Bullet(
                '${impact.solo} ${impact.solo == 1 ? 'group' : 'groups'} '
                'nobody else has an account in will be deleted outright, '
                'along with every expense in '
                '${impact.solo == 1 ? 'it' : 'them'}.',
              ),
            if (impact.shared > 0)
              _Bullet(
                'In ${impact.shared} shared '
                '${impact.shared == 1 ? 'group' : 'groups'}, what you paid '
                'and what you owe stays, under your name. It is your '
                "co-members' record of their own money as much as yours, and "
                'removing it would leave their balances wrong.',
              ),
            const _Bullet(
              'Your account, your sign-in and your notifications go for good. '
              'There is no way to sign back in.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete for good'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(sessionControllerProvider.notifier).deleteAccount();
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      // Said out loud rather than swallowed. A delete that silently failed
      // would leave somebody believing their account is gone when it is not.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete your account. $error'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      drawer: AdaptiveNavigation.drawerFor(context),
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
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _nameError,
              ),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Delete account',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: const Text(
                  'Removes your account and everything only you can see. '
                  'Permanent.',
                ),
                trailing: _deleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _deleting ? null : _deleteAccount,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A dash and a line of text, for a dialog that has to list consequences.
class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('\u2014  '),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
