import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/auth/google_sign_in_gateway.dart';

/// Attaches a real account to an anonymous session.
///
/// A six-digit code, not a magic link. Magic links open in whichever browser
/// the mail app prefers rather than the one holding the session, lose the app's
/// context entirely on mobile, and are routinely followed and consumed by
/// corporate mail scanners before the recipient ever sees them.
///
/// No SMS either, despite being the Indian default: per-message cost scales
/// linearly with signups and never goes away, and SMS pumping fraud can produce
/// a real bill overnight. That is exactly the kind of recurring per-user cost
/// that forces a paywall later.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.sendEmailCode(_email.text.trim());
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await GoogleSignInGateway().obtainIdToken();
      if (token == null) return;

      // Exchanging the ID token keeps the current user id, so an anonymous
      // session upgrades in place with nothing to migrate.
      await auth.linkGoogle(
        idToken: token.idToken,
        accessToken: token.accessToken,
      );
      ref.invalidate(sessionControllerProvider);
      await ref.read(syncControllerProvider.notifier).syncAll();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Your account is saved')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Upgrading keeps the same user id, so nothing in the database has to
      // move — the anonymous session simply gains a way back in.
      await auth.verifyEmailCode(
        email: _email.text.trim(),
        code: _code.text.trim(),
      );
      ref.invalidate(sessionControllerProvider);
      await ref.read(syncControllerProvider.notifier).syncAll();

      if (mounted) {
        setState(() {
          _codeSent = false;
          _code.clear();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Your account is saved')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'That code did not work. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider).value;
    final scheme = Theme.of(context).colorScheme;

    if (account == null) {
      return const SizedBox.shrink();
    }

    if (!account.isAnonymous) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.verified_user_outlined),
        title: const Text('Your account is saved'),
        subtitle: Text(
          account.email == null
              ? 'You can sign in on another device.'
              : 'Signed in as ${account.email}. You can sign in on another '
                    'device with this address.',
        ),
        isThreeLine: account.email != null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Save your account',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Right now your expenses exist only on this device and cannot be '
          'recovered. Adding an email address lets you get back in, and lets '
          'you use OpenSplit on more than one device.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
          ),
        ),
        if (_codeSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              labelText: 'Six-digit code',
              helperText: 'Check your email.',
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : (_codeSent ? _verify : _send),
          child: Text(_codeSent ? 'Verify code' : 'Send me a code'),
        ),
        if (GoogleSignInGateway.isConfigured && !_codeSent) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _google,
            icon: const Icon(Icons.account_circle_outlined),
            label: const Text('Continue with Google'),
          ),
        ],
        if (_codeSent)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _codeSent = false),
            child: const Text('Use a different address'),
          ),
      ],
    );
  }
}
