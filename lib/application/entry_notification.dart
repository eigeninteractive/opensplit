import '../data/repositories/drift_currency_repository.dart';
import '../data/repositories/drift_entry_repository.dart';
import '../data/repositories/drift_group_repository.dart';
import '../domain/money_format.dart';
import '../domain/notification_text.dart';

/// Turns an entry that has just landed on this device into notification text.
///
/// Takes its repositories rather than a `Ref` on purpose. It runs in two very
/// different places — the app, with Riverpod holding everything, and the push
/// background isolate, which has no provider container and builds its own
/// dependencies — and the wording of a notification must not depend on which.
/// Passing them in is what lets both call the same function instead of keeping
/// two copies of "what does this expense say".
///
/// Returns null when the entry is not on the device, which happens when a wake
/// arrives for a group this account has since left, or when the sync that was
/// meant to fetch it could not reach the server.
Future<({String title, String body})?> composeEntryNotification({
  required DriftEntryRepository entries,
  required DriftGroupRepository groups,
  required DriftCurrencyRepository currencies,
  required String? myProfileId,
  required String groupId,
  required String entryId,
}) async {
  final entry = await entries.getEntry(entryId);
  if (entry == null) return null;

  final group = await groups.getGroup(groupId);
  final members = await groups.getMembers(groupId);
  final known = await currencies.all();

  String nameOf(String memberId) =>
      members
          .where((m) => m.id == memberId)
          .map((m) => m.displayName)
          .firstOrNull ??
      'Someone';

  final myMemberId = members
      .where((m) => m.profileId == myProfileId)
      .map((m) => m.id)
      .firstOrNull;

  // A column lookup on the recipient's own share row, never a recomputation:
  // the split was resolved once, when the entry was written.
  final myShare =
      entry.shares
          .where((s) => s.memberId == myMemberId)
          .map((s) => s.amountMinor)
          .firstOrNull ??
      0;

  final currency = known.where((c) => c.code == entry.currency).firstOrNull;

  return describeEntry(
    entry: entry,
    groupName: group?.name ?? 'OpenSplit',
    authorName: nameOf(entry.createdBy),
    currency: currency,
    shareMinor: myShare,
    // The screens' formatter, so a banner and the app can never quote
    // different figures.
    format: (minor) => formatMoney(currency, minor),
  );
}

/// The route a notification about [entryId] should open.
///
/// Tapping a notification has to land on the thing it was about, not on the
/// app's front door. Built here so the foreground and background paths cannot
/// produce different links.
String entryNotificationRoute(String groupId, String entryId) =>
    '/g/$groupId/e/$entryId';
