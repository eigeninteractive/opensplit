import 'dart:convert';

import '../models/entry.dart';
import '../models/group_event.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/profile.dart';

/// The version stamped into every export.
///
/// Present from the first release rather than added when it is first needed:
/// a file with no version is one nothing can ever safely read, because there is
/// no way to tell it apart from a future shape that happens to share keys.
const jsonExportVersion = 1;

/// A complete, self-contained copy of one group.
///
/// The counterpart to the CSV, not a second format of it. CSV is for a person
/// with a spreadsheet: flat, one row per expense, lossy about anything that is
/// not a row. This is for getting the group back — every member including the
/// ones who never claimed an account, every payer and share with its original
/// weight, the fx snapshot each entry was recorded against, and the activity
/// log. Enough to reconstruct the ledger exactly, or to hand to anything that
/// wants to read it without asking the server.
///
/// Names are resolved and written out alongside the ids. An archive whose
/// member ids mean nothing without a running copy of this app is not much of an
/// archive.
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
          // Both are kept. `name` is what to show; these two say where it came
          // from, which is the difference between a person who has an account
          // and a placeholder somebody typed.
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
          // Minor units, deliberately. This file is for machines, and a
          // rendered "₹400.00" would have to be parsed back through a currency
          // table to be usable — losing exactness on the way for the currencies
          // where it matters most.
          'amount_minor': entry.amountMinor,
          'date': entry.entryDate.toIso8601String().split('T').first,
          'split_kind': entry.splitKind.name,
          'notes': entry.notes,
          // What a unit of this currency was worth on the day, as recorded then
          // and never re-fetched. Without it a converted total cannot be
          // reproduced from this file.
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
                //
                // Written as the stored integer, scaled by a million, rather
                // than as a decimal. That is the exact value; rendering it as
                // 0.333333 would make the file disagree with the ledger it came
                // from in the third place.
                'weight_micros': share.weightMicros,
              },
          ],
          'created_by': entry.createdBy,
          'created_at': entry.createdAt.toIso8601String(),
          'updated_at': entry.updatedAt.toIso8601String(),
          'deleted_at': entry.deletedAt?.toIso8601String(),
        },
    ],
    // The whole record, not just the expense half of it.
    //
    // It used to carry entry events alone, because those were the only ones
    // there were. An export that promises "everything you can take with you"
    // and silently drops who joined and when is a smaller promise than the one
    // this project makes.
    'activity': [for (final event in activity) _eventToJson(event)],
  };

  // Indented, because the first thing anybody does with an exported file is
  // open it.
  return const JsonEncoder.withIndent('  ').convert(export);
}

/// One line of the record, as JSON.
///
/// `kind` is the server's own spelling in every case, so a reader of the file
/// and a reader of the database are looking at the same vocabulary. The entry
/// kinds are the exception and are qualified -- `entry.created` rather than a
/// bare `created` -- because "created" on its own does not say created what.
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
        'kind': kind.wireName,
        'member_id': memberId,
        'display_name': displayName,
        'previous_name': ?previousName,
      },
    GroupChanged(:final kind, :final name, :final previousName) => {
      ...common,
      'kind': kind.wireName,
      'name': name,
      'previous_name': ?previousName,
    },
    LinkChanged(:final kind) => {...common, 'kind': kind.wireName},
  };
}
