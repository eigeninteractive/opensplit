import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/session_providers.dart';
import '../navigation.dart';
import '../widgets/page_body.dart';
import '../widgets/save_account_form.dart';

/// Where a guest attaches an email address or Google, so the account no longer
/// depends on this one device.
///
/// Also where the web's Google redirect lands, so an account that arrives here
/// already saved is told so rather than shown a form it no longer needs.
class SaveAccountScreen extends ConsumerWidget {
  const SaveAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    final saved = account != null && !account.isAnonymous;

    // Saved while this screen was open: its job is done.
    ref.listen(accountProvider, (previous, next) {
      final was = previous?.value;
      final now = next.value;
      if (was != null && was.isAnonymous && now != null && !now.isAnonymous) {
        goBack(context, '/account');
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/account')),
        title: const Text('Save your account'),
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [saved ? const _Saved() : const _Unsaved()],
        ),
      ),
    );
  }
}

class _Unsaved extends StatelessWidget {
  const _Unsaved();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your groups are synchronized, but this device is the only way back '
          'into this guest account, and only while you open OpenSplit at '
          'least once a year. Adding an email address lets you recover it and '
          'use OpenSplit on more than one device.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        const SaveAccountForm(),
      ],
    );
  }
}

class _Saved extends ConsumerWidget {
  const _Saved();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(accountProvider).value?.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Your account is saved'),
          subtitle: Text(
            email == null
                ? 'You can sign in on another device.'
                : 'Signed in as $email. You can sign in on another device '
                      'with this address.',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => goBack(context, '/account'),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
