import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/ledger_providers.dart';
import '../../application/session_providers.dart';
import '../../domain/auth_service.dart';
import '../../domain/avatar.dart';
import '../../data/local/database.dart';
import '../feedback.dart';
import '../widgets/avatar_view.dart';
import '../widgets/page_body.dart';
import 'edit_profile_screen.dart';

/// Who you are, in one place: the name and payment handle everybody who shares
/// a group with you reads, whether the account survives losing this device,
/// and the ways to leave.
///
/// Read-only. It shows the stored profile as it is, and editing happens on its
/// own screen, so nothing here holds a copy that could fall behind.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _deleting = false;

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This device keeps nothing: the groups and expenses stored here are '
          'removed, so whoever uses it next cannot read them.\n\n'
          'Synced changes return when you sign back in. Any pending or '
          'conflicting edits must be synced or resolved before signing out.',
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
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// Deletes the account, after saying precisely what that costs.
  /// Sends a code to the account's own address and asks for it. True once the
  /// session has been replaced with a fresh one.
  Future<bool> _confirmItIsYou() async {
    final session = ref.read(sessionControllerProvider.notifier);
    final email = await session.startReauthentication();
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _ConfirmItIsYou(email: email, verify: session.reauthenticate),
    );
    return confirmed ?? false;
  }

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
            onPressed: () {
              confirmedIrreversibly();
              Navigator.of(context).pop(true);
            },
            child: const Text('Delete for good'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    setState(() => _deleting = true);
    try {
      final session = ref.read(sessionControllerProvider.notifier);
      try {
        await session.deleteAccount();
      } on ReauthenticationRequired {
        // A session lasts a year, so holding one is not proof enough for
        // this. Nothing has been deleted yet.
        if (!await _confirmItIsYou()) {
          if (mounted) setState(() => _deleting = false);
          return;
        }
        await session.deleteAccount();
      }
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
    final profile = ref.watch(myProfileProvider).value;

    return DestinationScaffold(
      title: 'Account',
      slivers: [
        SliverList.list(
          children: [
            _Identity(
              id: account?.id ?? '',
              avatar: profile?.avatar ?? const InitialsAvatar(),
              name: profile?.displayName,
              email: account?.email,
              isGuest: account?.isAnonymous ?? false,
            ),
            if (account != null && account.isAnonymous) ...[
              const SizedBox(height: 16),
              const _SaveAccountCard(),
            ],

            const _SectionHeader('Profile'),
            _ProfileRow(
              icon: Icons.badge_outlined,
              label: 'Name',
              value: profile?.displayName,
              unset: 'Add the name your groups see',
              field: ProfileField.name,
            ),
            _ProfileRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'UPI ID',
              value: profile?.upiVpa,
              unset: 'Add one so people can pay you by UPI',
              field: ProfileField.upi,
            ),

            if (account != null) ...[
              const _SectionHeader('Account'),
              // Offered only to an account somebody can get back into.
              if (!account.isAnonymous)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout, color: theme.colorScheme.error),
                  title: Text(
                    'Sign out',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: const Text(
                    'Removes this device\'s copy. Sign back in to get it again.',
                  ),
                  onTap: _signOut,
                )
              // Said out loud rather than left as a gap.
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.no_accounts_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    'Signing out would end this account',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  subtitle: const Text(
                    'Nothing but this device identifies a guest, so there '
                    'would be no signing back in. Save your account first.',
                  ),
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
      ],
    );
  }
}

/// Who this is, as the people in your groups see them.
class _Identity extends StatelessWidget {
  const _Identity({
    required this.id,
    required this.avatar,
    required this.name,
    required this.email,
    required this.isGuest,
  });

  final String id;
  final Avatar avatar;
  final String? name;
  final String? email;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final named = name?.trim() ?? '';

    return Card.filled(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _edit(context, ProfileField.name),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Tooltip(
                message: 'Change picture',
                child: InkResponse(
                  onTap: () => context.push('/account/picture'),
                  radius: 36,
                  child: AvatarView(
                    avatar: avatar,
                    name: named,
                    id: id,
                    radius: 32,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      named.isEmpty ? 'No name yet' : named,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: named.isEmpty ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isGuest
                          ? 'Guest account on this device'
                          : email ?? 'Saved account',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit profile',
                onPressed: () => _edit(context, ProfileField.name),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one thing a guest should do, said once and with one button.
class _SaveAccountCard extends StatelessWidget {
  const _SaveAccountCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onCard = scheme.onSecondaryContainer;

    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save your account',
              style: theme.textTheme.titleMedium?.copyWith(color: onCard),
            ),
            const SizedBox(height: 8),
            Text(
              'Add an email address or Google so you can get back in after '
              'losing this device, and use OpenSplit on more than one.',
              style: theme.textTheme.bodyMedium?.copyWith(color: onCard),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/account/save'),
              child: const Text('Save my account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// One stored value, read-only, opening the editor on its own field.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.unset,
    required this.field,
  });

  final IconData icon;
  final String label;
  final String? value;

  /// What to say instead of a value, as an invitation rather than a blank.
  final String unset;
  final ProfileField field;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = value?.trim() ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        shown.isEmpty ? unset : shown,
        style: shown.isEmpty ? TextStyle(color: scheme.onSurfaceVariant) : null,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _edit(context, field),
    );
  }
}

void _edit(BuildContext context, ProfileField field) =>
    context.push('/account/edit?field=${field.name}');

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

/// Asks for the code sent to [email], and checks it before closing.
class _ConfirmItIsYou extends StatefulWidget {
  const _ConfirmItIsYou({required this.email, required this.verify});

  final String email;
  final Future<void> Function(String code) verify;

  @override
  State<_ConfirmItIsYou> createState() => _ConfirmItIsYouState();
}

class _ConfirmItIsYouState extends State<_ConfirmItIsYou> {
  final _code = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.verify(code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'That code is wrong or has expired.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirm it is you'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'We sent a code to ${widget.email}. Enter it to delete your account.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          autofocus: true,
          enabled: !_checking,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: InputDecoration(labelText: 'Code', errorText: _error),
          onSubmitted: (_) => _check(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _checking ? null : () => Navigator.of(context).pop(false),
        child: const Text('Keep my account'),
      ),
      FilledButton(
        onPressed: _checking ? null : _check,
        child: const Text('Confirm'),
      ),
    ],
  );
}
