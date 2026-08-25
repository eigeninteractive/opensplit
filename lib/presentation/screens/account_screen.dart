import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation.dart';
import '../widgets/account_section.dart';
import '../widgets/page_body.dart';

/// Attaching a real account, on a screen of its own.
///
/// It used to be a section three quarters of the way down Settings, below the
/// name field, the UPI field and the notification switch. That is the wrong
/// place for the one action that decides whether a user's data survives losing
/// their phone, and it made every prompt about it a two-step handoff: the
/// banner said "save my account" and then dropped the reader on a settings page
/// to go looking.
///
/// Having a route means the prompts can land on the thing they are promising,
/// and it means the address is linkable — which matters for the flow where
/// someone is told to sign in on a second device.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/settings')),
        title: const Text('Account'),
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [AccountSection()],
        ),
      ),
    );
  }
}
