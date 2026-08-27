import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/auth/google_sign_in_gateway.dart';
import '../../domain/repositories/auth_service.dart';

/// The three ways to become somebody, offered together.
///
/// Used wherever there is no session yet: the welcome screen, and the invite
/// screen once it has shown what the link is for. It is deliberately *not* the
/// same widget as [AccountSection], which attaches an account to a session that
/// already exists — that one has to weigh what a sign-in would cost and stop to
/// ask. Here there is nothing on the device and nothing to lose, so every path
/// is one tap with no warning attached, and folding the two together would mean
/// a widget whose behaviour is half flags.
class IdentityChoices extends ConsumerStatefulWidget {
  const IdentityChoices({super.key, this.onSignedIn, this.guestNote});

  /// Work that only makes sense once a session exists, whichever route
  /// produced it.
  ///
  /// Optional, and usually absent: nothing has to be done to *move* somebody
  /// on, because the router's guard already reconsiders where a signed-in
  /// visitor belongs the moment the session appears. The invite screen passes
  /// one because it has a token to spend.
  final Future<void> Function()? onSignedIn;

  /// What being a guest means *here*, if the caller wants to say something
  /// more specific than the general warning.
  final String? guestNote;

  @override
  ConsumerState<IdentityChoices> createState() => _IdentityChoicesState();
}

class _IdentityChoicesState extends ConsumerState<IdentityChoices> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// Sign-ins that did not begin with a call — the web's, from Google's own
  /// button. Null on Android, where [GoogleSignInGateway.obtainIdToken] awaits
  /// the token instead.
  StreamSubscription<GoogleCredential>? _googleSignIns;

  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (GoogleSignInGateway.isConfigured &&
        !GoogleSignInGateway.startsOnDemand) {
      // Rendering Google's button needs the plugin initialised first, and the
      // button reports its result to a stream rather than to whoever drew it.
      unawaited(GoogleSignInGateway().prepare());
      _googleSignIns = GoogleSignInGateway.signIns.listen(_signInWith);
    }
  }

  @override
  void dispose() {
    unawaited(_googleSignIns?.cancel());
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
    await ref
        .read(accountControllerProvider.notifier)
        .sendEmailCode(_email.text.trim());
    if (mounted) setState(() => _codeSent = true);
  });

  Future<void> _verify() => _run(() async {
    await ref
        .read(accountControllerProvider.notifier)
        .verifyEmailCode(
          email: _email.text.trim(),
          code: _code.text.trim(),
          // With no session there is nothing to attach an address to, so
          // sendEmailCode can only have started a sign-in.
          flow: EmailFlow.signInPending,
        );
    await widget.onSignedIn?.call();
  });

  Future<void> _google() => _run(() async {
    final credential = await GoogleSignInGateway().obtainIdToken();
    if (credential == null) return;
    await _exchange(credential);
  });

  /// The web's arrival point: Google's button has already produced a token.
  void _signInWith(GoogleCredential credential) =>
      unawaited(_run(() => _exchange(credential)));

  Future<void> _exchange(GoogleCredential credential) async {
    // allowSignIn, unconditionally: with no session this can only ever be a
    // sign-in, so the refusal that exists to protect an anonymous account's
    // data has nothing here to protect.
    await ref
        .read(accountControllerProvider.notifier)
        .continueWithGoogle(
          idToken: credential.idToken,
          accessToken: credential.accessToken,
          allowSignIn: true,
        );
    await widget.onSignedIn?.call();
  }

  Future<void> _guest() => _run(() async {
    await ref.read(sessionControllerProvider.notifier).continueAsGuest();
    await widget.onSignedIn?.call();
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (GoogleSignInGateway.isConfigured && !_codeSent) ...[
          // Android gets an ordinary button because it has a call to make. The
          // web gets Google's own, because Google Identity Services will not
          // start a sign-in from anything else.
          if (GoogleSignInGateway.startsOnDemand)
            OutlinedButton.icon(
              onPressed: _busy ? null : _google,
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('Continue with Google'),
            )
          else
            Align(child: GoogleSignInGateway().button()),
          const SizedBox(height: 20),
        ],

        TextField(
          controller: _email,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
          ),
          onSubmitted: (_) => _busy ? null : _sendCode(),
        ),

        if (_codeSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              labelText: 'Six-digit code',
              helperText: 'Check your email.',
            ),
            onSubmitted: (_) => _busy ? null : _verify(),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
        ],

        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
          child: Text(_codeSent ? 'Verify code' : 'Continue with email'),
        ),

        if (_codeSent)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _codeSent = false;
                    _code.clear();
                  }),
            child: const Text('Use a different address'),
          ),

        if (!_codeSent) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),

          // A real button, the same size as the others. Being a guest is a
          // supported way to use this app, not a way of giving up on it, and
          // demoting it to a text link would say the opposite.
          OutlinedButton(
            onPressed: _busy ? null : _guest,
            child: const Text('Continue as guest'),
          ),
          const SizedBox(height: 8),
          Text(
            widget.guestNote ??
                'Everything works and shared groups are synchronized. This '
                    'device is the only way back into the guest account until '
                    'you add an email address or Google account.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
