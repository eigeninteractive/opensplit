import '../../application/backend_providers.dart';
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
import '../widgets/link_account_prompt.dart';
import '../widgets/page_body.dart';
import '../widgets/segmented_list.dart';
import '../widgets/sync_status_notice.dart';
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
          'This removes OpenSplit data from this device. Sign back in to '
          'restore synced groups and expenses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
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
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            const Text('This is permanent.'),
            if (impact.solo > 0)
              Text(
                '${impact.solo} ${impact.solo == 1 ? 'group' : 'groups'} '
                'with no other accounts will be deleted, including all expenses.',
              ),
            if (impact.shared > 0)
              Text(
                'Your name, expenses, and balances stay in ${impact.shared} '
                'shared ${impact.shared == 1 ? 'group' : 'groups'}.',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
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
            child: const Text('Delete account'),
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
    final accountState = ref.watch(accountProvider);
    final profileState = ref.watch(myProfileProvider);
    final account = accountState.value;
    final profile = profileState.value;

    return DestinationScaffold(
      title: 'Account',
      slivers: [
        // Not read yet is not the same as not set: drawn as "Add the name
        // your groups see" for a frame, a saved name arrives as a correction.
        if (!accountState.hasValue || !profileState.hasValue)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: SavedDataLoading(label: 'Loading your account'),
          )
        else
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
                const LinkAccountPrompt.account(),
              ],

              const _SectionHeader('Profile'),
              SegmentedList(
                children: [
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
                ],
              ),

              if (account != null) ...[
                const _SectionHeader('Account'),
                SegmentedList(
                  children: [
                    // Offered only to an account somebody can get back into.
                    if (!account.isAnonymous)
                      ListTile(
                        leading: Icon(
                          Icons.logout,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          'Sign out',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        onTap: ref.watch(requiresAppUpdateProvider)
                            ? null
                            : _signOut,
                      ),
                    ListTile(
                      leading: Icon(
                        Icons.delete_forever_outlined,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Delete account',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      trailing: _deleting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: _deleting || ref.watch(requiresAppUpdateProvider)
                          ? null
                          : _deleteAccount,
                    ),
                  ],
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// Who this is, as the people in your groups see them.
class _Identity extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final named = name?.trim() ?? '';

    return Card.filled(
      color: scheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: ref.watch(requiresAppUpdateProvider)
            ? null
            : () => _edit(context, ProfileField.name),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Tooltip(
                message: 'Change picture',
                child: InkResponse(
                  onTap: ref.watch(requiresAppUpdateProvider)
                      ? null
                      : () => context.push('/account/picture'),
                  radius: 36,
                  child: AvatarHero.profile(
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
                onPressed: ref.watch(requiresAppUpdateProvider)
                    ? null
                    : () => _edit(context, ProfileField.name),
              ),
            ],
          ),
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
class _ProfileRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final shown = value?.trim() ?? '';
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        shown.isEmpty ? unset : shown,
        style: shown.isEmpty ? TextStyle(color: scheme.onSurfaceVariant) : null,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: ref.watch(requiresAppUpdateProvider)
          ? null
          : () => _edit(context, field),
    );
  }
}

void _edit(BuildContext context, ProfileField field) =>
    context.push('/account/edit?field=${field.name}');

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
