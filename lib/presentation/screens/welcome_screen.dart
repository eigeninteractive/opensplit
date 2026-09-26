import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/brand_mark.dart';
import '../widgets/identity_choices.dart';
import '../widgets/page_body.dart';

/// Where somebody with no session lands.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: BrandWash(
        child: PageBody(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandHeader(
                      title: 'OpenSplit',
                      subtitle:
                          'Split expenses with the people you actually spend '
                          'money with.',
                    ),
                    const SizedBox(height: 40),

                    const IdentityChoices(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
