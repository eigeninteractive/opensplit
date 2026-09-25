import 'models/currency.dart';
import 'models/entry_event.dart';
import 'models/entry.dart';
import 'models/group_event.dart';
import 'money_format.dart';

/// Builds the text for a local notification about an entry.
///
/// Lives in the domain, beside the split arithmetic, and is used by the same
/// build that renders the screen. That is the entire reason notifications are
/// posted locally rather than formatted on a server: a server-side formatter
/// would need its own implementation of currency exponents, rounding and each
/// recipient's share, and the two would drift apart without anyone noticing
/// until a banner and the app disagreed about what someone owed.
///
/// [shareMinor] is read straight off the recipient's `entry_shares` row — a
/// column lookup, not a recomputation.
///
/// [kind] is what happened, not what the expense is. Notifications used to fire
/// only for creations and so could hardcode "added"; they now fire for every
/// recorded change, and a banner that says somebody added an expense they
/// actually deleted is worse than no banner.
///
/// [actorName] is who made THIS change, which on an edit is usually not whoever
/// created the expense. That distinction is the reason the notification is
/// worth sending at all: "Priya edited your Groceries" is the message, and
/// naming the author instead would tell Ravi that Ravi had done it.
({String title, String body}) describeEntry({
  required Entry entry,
  required String groupName,
  required String actorName,
  required EntryEventKind kind,
  required Currency? currency,
  required int shareMinor,
  String Function(int minor)? format,
}) {
  String money(int minor) =>
      format != null ? format(minor) : formatMoney(currency, minor);

  final total = money(entry.amountMinor);

  if (entry.kind == EntryKind.settlement) {
    return (
      title: groupName,
      body: switch (kind) {
        EntryEventKind.created => '$actorName recorded paying $total.',
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

  final what = entry.description.trim().isEmpty
      ? 'an expense'
      : entry.description.trim();

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

/// The text for a notification about somebody arriving or leaving.
///
/// Composed on the device like every other banner in this app, from the member
/// row that has just synced. The server sent an id and a kind; the wording is
/// ours, and so is the decision not to send one.
///
/// Returns null for the kinds that belong in the feed rather than on a lock
/// screen. The SQL trigger already refuses to fan those out, so reaching this
/// branch means a server ahead of this build sent something new — in which case
/// saying nothing is the right answer, not guessing at a sentence for it.
({String title, String body})? describeMemberEvent({
  required String groupName,
  required String memberName,
  required EventKind kind,
}) => switch (kind) {
  EventKind.memberJoined => (
    title: groupName,
    body: '$memberName joined the group.',
  ),
  // No actor named, deliberately. Leaving is usually your own doing, and a
  // banner that says somebody removed somebody else invites a reading of the
  // group's politics that the record on the activity screen can give properly.
  EventKind.memberLeft => (
    title: groupName,
    body: '$memberName is no longer in the group.',
  ),
  _ => null,
};
