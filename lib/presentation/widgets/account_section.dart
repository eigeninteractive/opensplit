import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/auth/google_sign_in_gateway.dart';
import '../../domain/repositories/auth_service.dart';
import '../navigation.dart';

/// Attaches a real account to an anonymous session.
///
/// A six-digit code, not a magic link. Magic links open in whichever browser
/// the mail app prefers rather than the one holding the session, lose the app's
/// context entirely on mobile, and are routinely followed and consumed by
/// corporate mail scanners before the recipient ever sees them. That requires
/// an email template carrying the token — see `supabase/templates/`.
///
/// No SMS either, despite being the Indian default: per-message cost scales
/// linearly with signups and never goes away, and SMS pumping fraud can produce
/// a real bill overnight. That is exactly the kind of recurring per-user cost
/// that forces a paywall later.
///
/// ## Two outcomes, and the difference matters
///
/// Giving an address that is free ATTACHES it: the user id does not change and
/// every expense on this device is still theirs. Giving one that already has an
/// OpenSplit account is a SIGN-IN: the session is replaced, and what this
/// device recorded anonymously stays with the anonymous account, unreachable.
///
/// The screen has to name that before it happens rather than after, so both
/// paths stop and ask, and both say how many expenses are at stake.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// Null until a code has been asked for. Decides which token type verifying
  /// uses, and whether a warning is shown above the field.
  EmailFlow? _flow;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A refusal that came back from a redirect has no caller left to catch it,
    // so it waits in a provider for whichever screen the user was returned to.
    // This is that screen: nothing else ever asks to link without permission
    // to fall back, so nothing else can be refused.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final parked = ref.read(googleRefusalProvider);
      final refusal = parked.value;
      if (refusal == null) return;
      parked.value = null;
      unawaited(_run(() => _signInAfterRefusal()));
    });
  }

  /// Asks the question the redirect could not, then signs in if told to.
  ///
  /// The same two steps [_attach] takes on Android, split across the page load
  /// that happened in between.
  Future<void> _signInAfterRefusal() async {
    final returnTo = returnDestination(GoRouterState.of(context).uri);
    if (!await _confirmSignIn('that Google account')) return;
    if (!mounted) return;
    await ref
        .read(accountControllerProvider.notifier)
        .continueWithGoogle(returnTo: returnTo, allowSignIn: true);
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _codeSent =>
      _flow == EmailFlow.linkPending || _flow == EmailFlow.signInPending;

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on IdentityAlreadyInUse catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saved() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Your account is saved')));
  }

  /// Asks whether to go ahead with replacing the session, naming the cost.
  ///
  /// Returns false if they back out, and false if the widget went away while
  /// the dialog was open.
  Future<bool> _confirmSignIn(String who) async {
    final count = await ref
        .read(accountControllerProvider.notifier)
        .entriesLeftBehind();
    if (!mounted) return false;

    final loses = count > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign in as $who?'),
        content: Text(
          loses
              ? 'That already has an OpenSplit account, so this signs you in '
                    'to it rather than saving what is here.\n\n'
                    'The $count ${count == 1 ? 'expense' : 'expenses'} on this '
                    'device belong to the anonymous account that recorded '
                    'them. They will be removed from this device and they '
                    'cannot be moved across.'
              : 'That already has an OpenSplit account, so this signs you in '
                    'to it. There is nothing recorded on this device to lose.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(loses ? 'Sign in and remove' : 'Sign in'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _send() => _run(() async {
    final flow = await ref
        .read(accountControllerProvider.notifier)
        .sendEmailCode(_email.text.trim());

    if (!mounted) return;
    // Nothing was sent and nothing is pending: this deployment attaches an
    // address without confirming it. Already done.
    if (flow == EmailFlow.linked) {
      setState(() => _flow = null);
      _saved();
      return;
    }
    setState(() => _flow = flow);
  });

  Future<void> _verify() => _run(() async {
    final flow = _flow;
    if (flow == null) return;

    if (flow == EmailFlow.signInPending &&
        !await _confirmSignIn(_email.text.trim())) {
      return;
    }

    final outcome = await ref
        .read(accountControllerProvider.notifier)
        .verifyEmailCode(
          email: _email.text.trim(),
          code: _code.text.trim(),
          flow: flow,
        );

    if (!mounted) return;
    setState(() {
      _flow = null;
      _code.clear();
    });
    _reportOutcome(outcome);
  });

  Future<void> _google() => _run(_attach);

  /// Attaches Google to this session, or signs in as it.
  ///
  /// Linking is tried first and the refusal is the one chance to ask before a
  /// sign-in replaces the session and strands this device's rows.
  ///
  /// On Android the whole exchange happens here. On the web the first call
  /// hands the page to Google and returns [AttemptRedirected]; the refusal, if
  /// there is one, is raised on the way back by
  /// [AccountController.resumeGoogleRedirect] on the next launch and asked from
  /// [_resumeRedirect] — the same question, from the other end of a page load.
  Future<void> _attach() async {
    // Read before any await: on the web this navigates the page away.
    final returnTo = returnDestination(GoRouterState.of(context).uri);
    final controller = ref.read(accountControllerProvider.notifier);
    final GoogleAttempt attempt;
    try {
      // Linking first, and without permission to fall back.
      attempt = await controller.continueWithGoogle(returnTo: returnTo);
    } on IdentityAlreadyInUse {
      if (!await _confirmSignIn('that Google account')) return;
      if (!mounted) return;
      await controller.continueWithGoogle(
        returnTo: returnTo,
        allowSignIn: true,
      );
      return;
    }
    switch (attempt) {
      case AttemptCompleted(:final outcome):
        _reportOutcome(outcome);
      // The page is leaving, or the picker was dismissed.
      case AttemptRedirected():
      case AttemptCancelled():
        return;
    }
  }

  /// Says what an identity change did, once it is known to have happened.
  void _reportOutcome(IdentityOutcome outcome) {
    switch (outcome) {
      case SessionKept():
        _saved();
      case SessionReplaced():
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in. Fetching your groups…')),
        );
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
          'Your groups are synchronized, but this device is the only way back '
          'into this guest account. Adding an email address lets you recover '
          'it and use OpenSplit on more than one device.',
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
        if (_flow == EmailFlow.signInPending) ...[
          const SizedBox(height: 12),
          _Notice(
            'That address already has an OpenSplit account. Entering the code '
            'signs you in to it — what is on this device stays with the '
            'anonymous account that recorded it.',
          ),
        ],
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
          child: Text(
            _flow == EmailFlow.signInPending
                ? 'Verify and sign in'
                : _codeSent
                ? 'Verify code'
                : 'Send me a code',
          ),
        ),
        if (GoogleSignInGateway.isOffered && !_codeSent) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _google,
            icon: const Icon(Icons.account_circle_outlined),
            label: const Text('Continue with Google'),
          ),
        ],
        if (_codeSent)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _flow = null),
            child: const Text('Use a different address'),
          ),
      ],
    );
  }
}

/// A short caution, styled so it is read before the field under it.
class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
