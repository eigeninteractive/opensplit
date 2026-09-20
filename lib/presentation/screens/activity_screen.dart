import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/activity/activity_text.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry_event.dart';
import '../../domain/models/group_event.dart';
import '../navigation.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_body.dart';

/// What has happened to this group's expenses, and who did it.
///
/// The reason editing in place is safe. Without this, correcting ₹400 to ₹300
/// two days later silently moves somebody else's balance with nothing anywhere
/// to say why or who — which is a trust problem rather than a data one, and the
/// kind that surfaces as an argument rather than a bug report.
///
/// Rendered from the local database like every other screen, from snapshots the
/// server wrote: each records what an expense looked like after a change, and
/// the lines below are the difference between consecutive ones.
///
/// Two properties matter here and they pull in opposite directions. The record
/// has to be trustworthy, so no client writes it — the table has no insert,
/// update or delete grant, and a trigger is its only writer. And the feed has
/// to work with no network, because the one screen whose job is to say what
/// happened must not be the one screen that needs a server to do it. So the
/// device also writes a provisional snapshot as it saves, marked as such on
/// screen and discarded the moment the server's account of the same expense
/// arrives.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(groupActivityProvider(groupId)).value;
    final ledger = ref.watch(groupLedgerProvider(groupId));

    // Only worth saying when there is somewhere for a line to be going. A
    // build with no backend at all -- a guest, a local-only install -- never
    // syncs anything, so marking every line "not synced yet" would be noise
    // that never resolves rather than information.
    final syncs = ref.watch(syncEngineProvider) != null;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/g/$groupId')),
        title: const Text('Activity'),
      ),
      body: PageBody(
        child: switch (events) {
          null => const Center(child: CircularProgressIndicator()),
          [] => const _Empty(),
          _ => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: events.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = events[index];
              return _Line(
                event: event,
                actor: ledger?.nameOfActor(event.actorId) ?? 'Someone',
                memberNames: ledger?.memberNames ?? const {},
                pending: syncs && event.isProvisional,
                description: event is EntryChanged
                    ? ledger?.entries
                          .where((e) => e.id == event.entryId)
                          .firstOrNull
                          ?.description
                    : null,
                currency: ledger == null
                    ? null
                    : ref
                          .watch(currenciesProvider)
                          .value?[ledger.group.defaultCurrency],
              );
            },
          ),
        },
      ),
    );
  }
}

/// One line of the record.
///
/// The switch over [GroupEvent] is exhaustive, which is the point of the type
/// being sealed: a new kind cannot be added to the feed without this file
/// failing to compile until somebody has written the sentence for it. The old
/// version of this widget could only ever say something about an expense, and
/// there was nowhere for "Priya joined" to go.
class _Line extends StatelessWidget {
  const _Line({
    required this.event,
    required this.actor,
    required this.memberNames,
    required this.pending,
    required this.description,
    required this.currency,
  });

  final GroupEvent event;
  final String actor;
  final Map<String, String> memberNames;

  /// This device's own account of a change the server has not confirmed.
  final bool pending;

  /// The expense's description, for an entry line. Null for every other kind.
  final String? description;

  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, title) = switch (event) {
      EntryChanged(:final kind) => (
        _entryIcon(kind),
        '$actor ${describeKind(kind)} ${_what()}',
      ),

      // The actor is left out of a join on purpose. Nobody does it to you --
      // you arrive -- and naming whoever happened to hold the session would
      // often name the person who sent the link rather than the person who
      // walked through it.
      MemberChanged(kind: GroupEventKind.memberJoined, :final displayName) => (
        Icons.person_add_alt,
        '$displayName joined',
      ),
      MemberChanged(kind: GroupEventKind.memberAdded, :final displayName) => (
        Icons.person_outline,
        '$actor added $displayName',
      ),
      MemberChanged(kind: GroupEventKind.memberLeft, :final displayName) => (
        Icons.person_remove_outlined,
        '$displayName left',
      ),
      MemberChanged(:final displayName, :final previousName) => (
        Icons.badge_outlined,
        previousName == null
            ? '$actor renamed $displayName'
            : '$actor renamed $previousName to $displayName',
      ),

      GroupChanged(kind: GroupEventKind.groupRenamed, :final name) => (
        Icons.drive_file_rename_outline,
        '$actor renamed the group to $name',
      ),
      GroupChanged(kind: GroupEventKind.groupArchived) => (
        Icons.inventory_2_outlined,
        '$actor archived the group',
      ),
      GroupChanged() => (Icons.unarchive_outlined, '$actor restored the group'),

      LinkChanged(kind: GroupEventKind.linkCreated) => (
        Icons.link,
        '$actor created an invite link',
      ),
      LinkChanged() => (Icons.link_off, '$actor revoked the invite link'),
    };

    final changes = switch (event) {
      EntryChanged(:final changes) => changes,
      _ => const <FieldChange>[],
    };

    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text('$title${pending ? ' — not synced yet' : ''}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final change in changes)
            Text(
              describeChange(
                change,
                currency: currency,
                memberNames: memberNames,
              ),
              style: theme.textTheme.bodySmall,
            ),
          Text(
            _when(event.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: changes.isNotEmpty,
    );
  }

  String _what() => (description?.trim().isNotEmpty ?? false)
      ? '“${description!.trim()}”'
      : 'an expense';

  static IconData _entryIcon(EntryEventKind kind) => switch (kind) {
    EntryEventKind.created => Icons.add_circle_outline,
    EntryEventKind.edited => Icons.edit_outlined,
    EntryEventKind.deleted => Icons.remove_circle_outline,
    EntryEventKind.restored => Icons.restore,
  };

  /// Relative for the recent past, absolute once "3 days ago" stops being the
  /// more useful of the two.
  static String _when(DateTime at) {
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inHours < 1) return '${ago.inMinutes} min ago';
    if (ago.inDays < 1) return '${ago.inHours}h ago';
    if (ago.inDays < 7) return '${ago.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.history,
    title: 'Nothing has happened here yet',
    message:
        'Every expense added, edited or deleted in this group shows up '
        'here, with who did it.',
  );
}
