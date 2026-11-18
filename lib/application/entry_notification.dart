import 'package:opensplit_api/opensplit_api.dart' show PushData, PushKind;

import '../data/repositories/drift_activity_repository.dart';
import '../data/repositories/drift_currency_repository.dart';
import '../data/repositories/drift_entry_repository.dart';
import '../data/repositories/drift_group_repository.dart';
import '../data/repositories/drift_profile_repository.dart';
import '../domain/balance/suggested_transfers.dart';
import '../domain/member_identity.dart';
import '../domain/models/group_event.dart';
import '../domain/money_format.dart';
import '../domain/notification_text.dart';

/// Turns an event that has just landed on this device into notification text.
Future<({String title, String body})?> composeEventNotification({
  required DriftEntryRepository entries,
  required DriftGroupRepository groups,
  required DriftProfileRepository profiles,
  required DriftCurrencyRepository currencies,
  required DriftActivityRepository activity,
  required String? myProfileId,

  /// What the wake said this was about. Used to decide whether to look at
  /// all; the wording comes from the record on this device, which is the copy
  /// that has actually been synced.
  required PushData push,
}) async {
  final PushData(:groupId, :kind, :subjectId) = push;
  if (!_worthABanner.contains(kind)) return null;

  final group = await groups.getGroup(groupId);
  final members = await groups.getMembers(groupId);
  final knownProfiles = await profiles.all();
  final known = await currencies.all();

  String nameOf(String memberId) {
    final member = members.where((m) => m.id == memberId).firstOrNull;
    if (member == null) return 'Someone';
    return memberDisplayName(member, knownProfiles[member.profileId]);
  }

  final myMemberId = members
      .where((m) => m.profileId == myProfileId)
      .map((m) => m.id)
      .firstOrNull;

  // Somebody asking to be paid. Not an event, so there is no record to
  // read: the amount is whatever this device's ledger says is owed now, and
  // a debt that has since been settled is not worth a banner.
  if (kind == PushKind.reminder) {
    if (group == null) return null;
    final owed =
        suggestedTransfers(
          await entries.getEntries(groupId),
          simplified: group.simplifyDebts,
        ).where(
          (transfer) =>
              transfer.fromMemberId == myMemberId &&
              transfer.toMemberId == subjectId &&
              transfer.currency == push.currency,
        );
    final transfer = owed.firstOrNull;
    if (transfer == null) return null;
    return describeReminder(
      groupName: group.name,
      creditorName: nameOf(subjectId),
      amount: formatMoney(
        known.where((c) => c.code == transfer.currency).firstOrNull,
        transfer.amountMinor,
      ),
    );
  }

  // What happened, and who did it -- read off the record rather than inferred
  // from the row it describes.
  final change = await activity.latestFor(subjectId);
  if (change == null) return null;

  // Somebody arriving or leaving.
  if (change is MemberChanged) {
    return describeMemberEvent(
      groupName: group?.name ?? 'OpenSplit',
      memberName: nameOf(change.memberId),
      kind: change.kind,
    );
  }

  // Nothing else is worth a banner. The server does not send the other kinds
  // at all, so this is the belt to its braces.
  if (change is! EntryChanged) return null;

  final entry = await entries.getEntry(subjectId);
  if (entry == null) return null;

  // A column lookup on the recipient's own share row, never a recomputation:
  // the split was resolved once, when the entry was written.
  final myShare =
      entry.shares
          .where((s) => s.memberId == myMemberId)
          .map((s) => s.amountMinor)
          .firstOrNull ??
      0;

  final currency = known.where((c) => c.code == entry.row.currency).firstOrNull;

  return describeEntry(
    entry: entry,
    groupName: group?.name ?? 'OpenSplit',
    actorName: change.actorId == null ? 'Someone' : nameOf(change.actorId!),
    kind: change.kind,
    currency: currency,
    shareMinor: myShare,
    // The screens' formatter, so a banner and the app can never quote
    // different figures.
    format: (minor) => formatMoney(currency, minor),
  );
}

/// The kinds that produce a banner at all.
const _worthABanner = {
  PushKind.entry,
  PushKind.memberJoined,
  PushKind.memberLeft,
  PushKind.reminder,
};

/// The group route a notification should open.
String groupNotificationRoute(String groupId) => '/g/$groupId';
