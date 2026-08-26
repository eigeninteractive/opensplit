import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/repositories/invite_api.dart';
import '../widgets/identity_choices.dart';
import '../widgets/page_body.dart';

/// The critical path: someone taps a link a friend sent them.
///
/// It reads the invite before spending it, and that ordering is the whole
/// screen. The previous version signed every arrival in anonymously and
/// redeemed immediately, on the reasoning that a signup wall here is where
/// people leave. The wall really is worth avoiding — but claiming first meant
/// that anybody who already had an account, which is most people arriving from
/// a link, had their place taken by a throwaway account and the single-use
/// token spent. Signing in afterwards did not help: their real account had a
/// different id, the member row pointed at the anonymous one, and a group
/// refuses two places for the same person. Only the owner reissuing the link
/// fixed it.
///
/// So: show what the link is for, ask who they are, then claim once. There is
/// still no wall — being a guest is one of the three answers — and there is now
/// a way to say no, which matters when the link was meant for somebody else.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  InvitePreview? _preview;
  String? _error;
  bool _loading = true;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _peek());
  }

  Future<void> _peek() async {
    final invites = ref.read(inviteApiProvider);
    if (invites == null) {
      setState(() {
        _loading = false;
        _error =
            'This build has no server configured, so links cannot be opened '
            'on it.';
      });
      return;
    }

    try {
      final preview = await invites.peek(widget.token);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _preview = preview;
        if (preview == null) _error = 'This is not a link we recognise.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not open this link. $e';
        });
      }
    }
  }

  /// Spends the token as whoever holds the session now.
  Future<void> _join() async {
    final invites = ref.read(inviteApiProvider);
    if (invites == null) return;

    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final member = await invites.redeem(widget.token);
      // Pull the group down before showing it, so it is populated on arrival
      // rather than filling in underneath them.
      await ref.read(syncControllerProvider.notifier).syncGroup(member.groupId);
      if (mounted) context.go('/g/${member.groupId}');
    } on InviteRejected catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = 'Could not join. $e';
        });
      }
    }
  }

  /// Leaves this account and comes back to the same link.
  ///
  /// Safe to offer precisely because nothing has been claimed yet: the token is
  /// still unspent, so signing out and returning is a real way to fix having
  /// opened somebody else's invite while signed in as yourself.
  Future<void> _switchAccount() async {
    await ref.read(sessionControllerProvider.notifier).signOut();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: PageBody(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _body(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [CircularProgressIndicator()],
      );
    }

    final preview = _preview;
    if (preview == null) return _Dead(message: _error ?? 'Unknown problem.');

    if (preview.isRedeemed) {
      return _Dead(
        message:
            'This link has already been used. Links work once, so ask '
            '${preview.inviterName} to send a new one.',
      );
    }
    if (preview.isExpired) {
      return _Dead(
        message:
            'This link has expired. Ask ${preview.inviterName} to send a '
            'new one.',
      );
    }
    if (preview.isMember) {
      return _Dead(
        message:
            'You are already in ${preview.groupName}, so there is nothing to '
            'claim here.',
        action: FilledButton(
          onPressed: () => context.go('/g/${preview.groupId}'),
          child: const Text('Open the group'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.group_add_outlined,
          size: 40,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          '${preview.inviterName} invited you to ${preview.groupName}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'You would join as “${preview.memberName}”, alongside '
          '${preview.memberCount} '
          '${preview.memberCount == 1 ? 'person' : 'people'}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),

        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 16),
        ],

        _Claim(
          preview: preview,
          joining: _joining,
          onJoin: _join,
          onSwitchAccount: _switchAccount,
        ),
      ],
    );
  }
}

/// Who is about to claim the place, and the chance to say it should not be you.
class _Claim extends ConsumerWidget {
  const _Claim({
    required this.preview,
    required this.joining,
    required this.onJoin,
    required this.onSwitchAccount,
  });

  final InvitePreview preview;
  final bool joining;
  final Future<void> Function() onJoin;
  final Future<void> Function() onSwitchAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider).value;

    // Nobody yet. The three ways to become somebody, then the claim happens
    // against whichever one they picked.
    if (account == null) {
      return IdentityChoices(
        onSignedIn: onJoin,
        guestNote:
            'You will be in the group straight away. It stays on this device '
            'and cannot be recovered if you lose it — you can add an account '
            'later without leaving the group.',
      );
    }

    final me = ref.watch(myProfileProvider).value;
    final who = me?.displayName.trim().isNotEmpty ?? false
        ? me!.displayName
        : account.email ?? 'this device';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: joining ? null : onJoin,
          child: Text('Join as ${preview.memberName}'),
        ),
        const SizedBox(height: 12),
        Text(
          // Stated plainly, because this is the moment somebody discovers they
          // opened a link meant for a different person. Claiming a place named
          // for somebody else is not forbidden — a placeholder is only ever
          // what a friend happened to type — but it should never happen by
          // accident.
          'You are signed in as $who. Joining puts you in the place '
          '${preview.inviterName} labelled “${preview.memberName}”.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: joining ? null : onSwitchAccount,
          child: const Text('Use a different account'),
        ),
        TextButton(
          onPressed: joining ? null : () => context.go('/'),
          child: const Text('Not now'),
        ),
      ],
    );
  }
}

/// A link that cannot be used, and why.
class _Dead extends StatelessWidget {
  const _Dead({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link_off, size: 40, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'This link did not work',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        action ??
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Go to your groups'),
            ),
      ],
    );
  }
}
