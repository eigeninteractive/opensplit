import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/ledger_providers.dart';
import '../../application/local_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import 'sync_status_notice.dart';

/// Keeps every group route behind the account's current membership.
class GroupAccess extends ConsumerWidget {
  const GroupAccess({super.key, required this.groupId, required this.child});

  final String groupId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(groupSyncProvider(groupId));
    final group = ref.watch(groupProvider(groupId));
    final members = ref.watch(membersProvider(groupId));
    final account = ref.watch(currentAccountIdProvider);
    if (!group.hasValue || !members.hasValue) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const SavedDataLoading(label: 'Loading saved group…'),
      );
    }
    if (group.value == null ||
        (account != null &&
            !members.value!.any((m) => m.profileId == account && m.isActive))) {
      return const GroupUnavailableScreen();
    }
    return child;
  }
}

/// No financial data is shown after membership ends, even from cached rows.
class GroupUnavailableScreen extends StatelessWidget {
  const GroupUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: () => context.go('/')),
      title: const Text('Group unavailable'),
    ),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('This group is no longer available to your account.'),
      ),
    ),
  );
}
