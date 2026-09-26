import 'dart:convert';

import '../calendar_date.dart';
import '../models/entry.dart';
import '../models/group_event.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/profile.dart';

/// The version stamped into every export.
const jsonExportVersion = 1;

/// A complete, self-contained copy of one group.
String groupToJson({
  required Group group,
  required List<Member> members,
  required List<Entry> entries,
  required Map<String, Profile> profiles,
  required String Function(Member) nameOf,
  List<GroupEvent> activity = const [],
  Map<String, String> categoryNames = const {},
}) {
  final export = {
    'version': jsonExportVersion,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'group': {
      'id': group.id,
      'name': group.name,
      'default_currency': group.defaultCurrency,
      'simplify_debts': group.simplifyDebts,
      'created_at': group.createdAt.toIso8601String(),
      'archived_at': group.archivedAt?.toIso8601String(),
    },
    'members': [
      for (final member in members)
        {
          'id': member.id,
          'name': nameOf(member),
          // Both are kept.
          'placeholder_name': member.displayName,
          'has_account': member.profileId != null,
          'upi_vpa': profiles[member.profileId]?.upiVpa ?? member.upiVpa,
          'joined_at': member.joinedAt.toIso8601String(),
          'left_at': member.leftAt?.toIso8601String(),
        },
    ],
    'entries': [
      for (final entry in entries)
        {
          'id': entry.id,
          'kind': entry.kind.name,
          'description': entry.description,
          'category': categoryNames[entry.categoryId],
          'category_id': entry.categoryId,
          'currency': entry.currency,
          // Minor units, deliberately.
          'amount_minor': entry.amountMinor,
          'date': calendarDate(entry.entryDate),
          // When and where it happened, when known: an instant in UTC and
          // the IANA zone to read it in.
          'occurred_at': entry.occurredAt?.toIso8601String(),
          'time_zone': entry.timeZone,
          'split_kind': entry.splitKind.name,
          'notes': entry.notes,
          // What a unit of this currency was worth on the day, as recorded then
          // and never re-fetched.
          'fx': entry.fxRate == null
              ? null
              : {
                  'rate': entry.fxRate.toString(),
                  'source': entry.fxSource,
                  'at': entry.fxAt?.toIso8601String(),
                },
          'payers': [
            for (final payer in entry.payers)
              {'member_id': payer.memberId, 'amount_minor': payer.amountMinor},
          ],
          'shares': [
            for (final share in entry.shares)
              {
                'member_id': share.memberId,
                'amount_minor': share.amountMinor,
                // The rule as well as the result: an export holding only the
                // amounts cannot be re-edited as "2:1:1", and one holding only
                // the rule would let a later rounding change move money that
                // has already been settled.
                'weight_micros': share.weightMicros,
              },
          ],
          'created_by': entry.createdBy,
          'created_at': entry.createdAt.toIso8601String(),
          'deleted_at': entry.deletedAt?.toIso8601String(),
        },
    ],
    // The whole record: who joined and when, not only the expenses.
    'activity': [for (final event in activity) _eventToJson(event)],
  };

  // Indented, because the first thing anybody does with an exported file is
  // open it.
  return const JsonEncoder.withIndent('  ').convert(export);
}

/// One line of the record, as JSON.
Map<String, Object?> _eventToJson(GroupEvent event) {
  final common = {
    'id': event.id,
    'actor_id': event.actorId,
    'at': event.createdAt.toIso8601String(),
  };

  return switch (event) {
    EntryChanged(:final entryId, :final kind, :final changes) => {
      ...common,
      'kind': 'entry.${kind.name}',
      'entry_id': entryId,
      'changes': {
        for (final change in changes)
          change.field: {'from': change.from, 'to': change.to},
      },
    },
    MemberChanged(
      :final memberId,
      :final kind,
      :final displayName,
      :final previousName,
    ) =>
      {
        ...common,
        'kind': kind.value,
        'member_id': memberId,
        'display_name': displayName,
        'previous_name': ?previousName,
      },
    GroupChanged(:final kind, :final name, :final previousName) => {
      ...common,
      'kind': kind.value,
      'name': name,
      'previous_name': ?previousName,
    },
    LinkChanged(:final kind) => {...common, 'kind': kind.value},
  };
}
