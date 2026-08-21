import 'models/currency.dart';
import 'models/entry.dart';
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
({String title, String body}) describeEntry({
  required Entry entry,
  required String groupName,
  required String authorName,
  required Currency? currency,
  required int shareMinor,
  String Function(int minor)? format,
}) {
  String money(int minor) =>
      format != null ? format(minor) : formatMoney(currency, minor);

  if (entry.kind == EntryKind.settlement) {
    final payee = entry.shares.isEmpty ? null : entry.shares.first.memberId;
    return (
      title: groupName,
      body: payee == null
          ? '$authorName recorded a settlement of ${money(entry.amountMinor)}.'
          : '$authorName recorded paying ${money(entry.amountMinor)}.',
    );
  }

  final what = entry.description.trim().isEmpty
      ? 'an expense'
      : entry.description.trim();

  return (
    title: groupName,
    body: shareMinor > 0
        ? '$authorName added $what — ${money(entry.amountMinor)}. '
              'Your share: ${money(shareMinor)}.'
        // Being told about an expense you are not part of is still worth
        // knowing, but claiming a share of zero reads as a bug.
        : '$authorName added $what — ${money(entry.amountMinor)}.',
  );
}
