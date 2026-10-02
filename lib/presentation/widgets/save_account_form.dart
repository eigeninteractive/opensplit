import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opensplit_api/opensplit_api.dart' show EmailFlow;

import '../../application/session_providers.dart';
import '../../data/auth/google_sign_in_gateway.dart';
import '../../domain/auth_service.dart';
import '../navigation.dart';

/// Attaches an email address or Google to a guest session, or signs in to the
/// account either already belongs to.
class SaveAccountForm extends ConsumerStatefulWidget {
  const SaveAccountForm({super.key});

  @override
  ConsumerState<SaveAccountForm> createState() => _SaveAccountFormState();
}

class _SaveAccountFormState extends ConsumerState<SaveAccountForm> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(googleRefusalProvider.notifier).take() == null) return;
      unawaited(_run(() => _signInAfterRefusal()));
    });
  }

  /// Asks the question the redirect could not, then signs in if told to.
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
  Future<bool> _confirmSignIn(String who) async {
    final count = await ref
        .read(accountControllerProvider.notifier)
        .groupsToHandOver();
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign in as $who?'),
        content: Text(
          count > 0
              ? 'That already has an OpenSplit account, so this signs you in '
                    'to it and this guest account ends.\n\n'
                    'Your place in ${count == 1 ? 'your group' : 'all $count '
                              'groups'} comes with you, balances and all. In '
                    'any group that account is already in, your guest place '
                    'stays behind as a placeholder under its name.'
              : 'That already has an OpenSplit account, so this signs you in '
                    'to it and this guest account ends. It is in no groups, '
                    'so there is nothing to bring along.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign in'),
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
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            'signs you in to it, and your groups come with you.',
          ),
        ],
        if (_codeSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              labelText: 'Eight-digit code',
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
