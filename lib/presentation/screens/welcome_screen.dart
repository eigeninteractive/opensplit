import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/identity_choices.dart';
import '../widgets/page_body.dart';

/// Where somebody with no session lands.
///
/// It exists because the app used to answer this question on the user's behalf,
/// signing in anonymously the moment it opened. That was defended as removing a
/// wall from the invite path, and the wall really is worth removing — but the
/// implementation put a throwaway account in the way of everyone who already
/// had a real one, which is most people arriving from a link. They could not
/// sign in to what was already theirs without first being somebody else.
///
/// So the three routes are offered together and none of them is a wall: being
/// a guest is one tap, it is a real account, and everything works afterwards.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: PageBody(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'OpenSplit',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Split expenses with the people you actually spend money '
                    'with.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),

                  IdentityChoices(
                    onSignedIn: () async {
                      if (context.mounted) context.go('/');
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
