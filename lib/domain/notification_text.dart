import 'package:opensplit_api/opensplit_api.dart' show EntryKind, EventKind;

import '../data/local/database.dart';
import 'models/entry.dart';
import 'models/entry_event.dart';
import 'money_format.dart';

/// Builds the text for a local notification about an entry.
({String title, String body}) describeEntry({
  required Entry entry,
  required String groupName,
  required String actorName,
  required EntryEventKind kind,
  required Currency? currency,
  required int shareMinor,
  String? payerName,
  String? recipientName,
  String Function(int minor)? format,
}) {
  String money(int minor) =>
      format != null ? format(minor) : formatMoney(currency, minor);

  final total = money(entry.row.amountMinor);

  if (entry.row.kind == EntryKind.settlement) {
    return (
      title: groupName,
      body: switch (kind) {
        EntryEventKind.created =>
          'Payment recorded from ${payerName ?? "someone"} to ${recipientName ?? "another member"} ($total).',
        EntryEventKind.edited =>
          '$actorName changed a settlement — '
              'now $total.',
        EntryEventKind.deleted => '$actorName deleted a settlement of $total.',
        EntryEventKind.restored =>
          '$actorName restored a settlement of '
              '$total.',
      },
    );
  }

  final what = entry.row.description.trim().isEmpty
      ? 'an expense'
      : entry.row.description.trim();

  // Being told about an expense you are not part of is still worth knowing,
  // but claiming a share of zero reads as a bug.
  final yours = shareMinor > 0 ? ' Your share: ${money(shareMinor)}.' : '';

  return (
    title: groupName,
    body: switch (kind) {
      EntryEventKind.created => '$actorName added $what — $total.$yours',
      EntryEventKind.edited => '$actorName edited $what — now $total.$yours',
      // No share on a deletion: what somebody owes for an expense that is gone
      // is nothing, and quoting the old figure invites reading it as a charge.
      EntryEventKind.deleted => '$actorName deleted $what — $total.',
      EntryEventKind.restored => '$actorName restored $what — $total.$yours',
    },
  );
}

/// The text for a notification asking the reader to pay somebody back.
///
/// [amount] is already formatted, symbol included.
({String title, String body}) describeReminder({
  required String groupName,
  required String creditorName,
  required String amount,
}) => (
  title: groupName,
  body: '$creditorName sent a reminder: you owe them $amount.',
);

/// The text for a notification about somebody arriving or leaving.
({String title, String body})? describeMemberEvent({
  required String groupName,
  required String memberName,
  required EventKind kind,
}) => switch (kind) {
  EventKind.memberJoined => (
    title: groupName,
    body: '$memberName joined the group.',
  ),
  // No actor named, deliberately.
  EventKind.memberLeft => (
    title: groupName,
    body: '$memberName is no longer in the group.',
  ),
  _ => null,
};
