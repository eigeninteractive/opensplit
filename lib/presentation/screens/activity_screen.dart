import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:opensplit_api/opensplit_api.dart' show EventKind;

import '../../application/ledger_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../domain/activity/activity_text.dart';
import '../../domain/calendar_date.dart';
import '../../domain/models/entry_event.dart';
import '../../domain/models/group_event.dart';
import '../navigation.dart';
import '../widgets/avatar_view.dart';
import '../widgets/day_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_body.dart';
import '../widgets/segmented_list.dart';
import '../widgets/sync_status_notice.dart';

/// What has happened to this group's expenses, and who did it.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(groupActivityProvider(groupId)).value;
    final ledger = ref.watch(groupLedgerProvider(groupId));

    // Only worth saying when there is somewhere for a line to be going.
    final syncs = ref.watch(syncEngineProvider) != null;
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final categoryNames = {
      for (final category
          in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id: category.name,
    };

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/g/$groupId')),
        title: const Text('Activity'),
      ),
      body: PageBody(
        child: switch (events) {
          null => const SavedDataLoading(label: 'Loading activity'),
          [] => const _Empty(),
          _ => _Feed(
            events: events,
            lineFor: (event) {
              final currencyCode = switch (event) {
                EntryChanged(:final snapshot?) => snapshot.currency,
                _ => ledger?.group.defaultCurrency,
              };
              final entry = event is EntryChanged
                  ? ledger?.entries
                        .where((e) => e.id == event.entryId)
                        .firstOrNull
                  : null;
              return _Line(
                event: event,
                ledger: ledger,
                categoryNames: categoryNames,
                pending: syncs && event.isProvisional,
                description: entry?.row.description,
                currency: currencies[currencyCode],
                // Only while there is still an expense to open.
                onTap: entry == null
                    ? null
                    : () => context.push('/g/$groupId/e/${entry.id}'),
              );
            },
          ),
        },
      ),
    );
  }
}

/// The record, newest first, a day at a time: the same headers and
/// connected rows as the group's expenses.
class _Feed extends StatelessWidget {
  const _Feed({required this.events, required this.lineFor});

  final List<GroupEvent> events;
  final Widget Function(GroupEvent event) lineFor;

  @override
  Widget build(BuildContext context) {
    // Events arrive newest first, so a day's run is contiguous.
    final rows = <Object>[];
    final days = <List<GroupEvent>>[];
    for (final event in events) {
      final day = calendarDay(event.createdAt.toLocal());
      if (days.isEmpty ||
          calendarDay(days.last.first.createdAt.toLocal()) != day) {
        days.add([]);
        rows.add(day);
      }
      days.last.add(event);
      rows.add((event: event, day: days.last));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: rows.length,
      itemBuilder: (context, index) => switch (rows[index]) {
        final DateTime day => DayHeader(day: day),
        (event: final GroupEvent event, day: final List<GroupEvent> day) =>
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Segment(
              index: day.indexOf(event),
              count: day.length,
              child: lineFor(event),
            ),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// One line of the record.
class _Line extends StatelessWidget {
  const _Line({
    required this.event,
    required this.ledger,
    required this.categoryNames,
    required this.pending,
    required this.description,
    required this.currency,
    required this.onTap,
  });

  final GroupEvent event;
  final GroupLedger? ledger;
  final Map<String, String> categoryNames;
  final VoidCallback? onTap;

  /// This device's own account of a change the server has not confirmed.
  final bool pending;

  /// The expense's description, for an entry line. Null for every other kind.
  final String? description;

  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actor = ledger?.nameOfActor(event.actorId) ?? 'Someone';
    final memberNames = ledger?.memberNames ?? const <String, String>{};

    // Whoever the line is about: the person who arrived or left, and
    // otherwise the person who made the change.
    final who = ledger?.memberById(switch (event) {
      MemberChanged(
        kind: EventKind.memberJoined || EventKind.memberLeft,
        :final memberId,
      ) =>
        memberId,
      _ => event.actorId ?? '',
    });

    final (icon, title) = switch (event) {
      EntryChanged(:final kind, :final snapshot) => (
        _entryIcon(kind),
        describeEntryEvent(
          actor: actor,
          kind: kind,
          snapshot: snapshot,
          fallbackDescription: description,
          memberNames: memberNames,
        ),
      ),

      // The actor is left out of a join on purpose.
      MemberChanged(kind: EventKind.memberJoined, :final displayName) => (
        Icons.person_add_alt,
        '$displayName joined',
      ),
      MemberChanged(kind: EventKind.memberAdded, :final displayName) => (
        Icons.person_outline,
        '$actor added $displayName',
      ),
      MemberChanged(kind: EventKind.memberLeft, :final displayName) => (
        Icons.person_remove_outlined,
        '$displayName left',
      ),
      MemberChanged(:final displayName, :final previousName) => (
        Icons.badge_outlined,
        previousName == null
            ? '$actor renamed $displayName'
            : '$actor renamed $previousName to $displayName',
      ),

      GroupChanged(:final name) => (
        Icons.drive_file_rename_outline,
        '$actor renamed the group to $name',
      ),
      LinkChanged(kind: EventKind.linkCreated) => (
        Icons.link,
        '$actor created an invite link',
      ),
      LinkChanged() => (Icons.link_off, '$actor revoked the invite link'),
    };

    final details = switch (event) {
      EntryChanged(:final changes) when changes.isNotEmpty => [
        for (final change in changes)
          describeChange(
            change,
            currency: currency,
            memberNames: memberNames,
            categoryNames: categoryNames,
          ),
      ],
      EntryChanged(:final snapshot) => [
        ?describeEntrySummary(
          snapshot,
          currency: currency,
          memberNames: memberNames,
        ),
      ],
      _ => const <String>[],
    };

    return ListTile(
      onTap: onTap,
      leading: who == null || ledger == null
          ? CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: Icon(icon),
            )
          : MemberAvatar(ledger: ledger!, member: who),
      title: Text('$title${pending ? ' — not synced yet' : ''}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final detail in details) Text(detail),
          Text(
            DateFormat.jm().format(event.createdAt.toLocal()),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: details.isNotEmpty,
      // The kind of change at a glance, now that the avatar says who.
      trailing: who == null
          ? null
          : Icon(icon, size: 20, color: scheme.onSurfaceVariant),
    );
  }

  static IconData _entryIcon(EntryEventKind kind) => switch (kind) {
    EntryEventKind.created => Icons.add_circle_outline,
    EntryEventKind.edited => Icons.edit_outlined,
    EntryEventKind.deleted => Icons.remove_circle_outline,
    EntryEventKind.restored => Icons.restore,
  };
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.history,
    title: 'Nothing has happened here yet',
    message: 'Expense changes and who made them appear here.',
  );
}
