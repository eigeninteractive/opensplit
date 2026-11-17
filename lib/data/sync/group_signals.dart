import 'package:opensplit_api/opensplit_api.dart' as api;

import 'api_client.dart';

/// What an account tells a group's server outside the ledger: a nudge to
/// somebody who owes it, and how far it has read. Throws [ApiFailure].
class GroupSignals {
  GroupSignals(api.OpensplitApi client) : _groups = client.getGroupsApi();

  final api.GroupsApi _groups;

  /// Asks the server to notify [memberId] that they owe the caller in
  /// [currency]. The answer says whether it went, was sent already today,
  /// or had no device to go to.
  Future<api.Reminder> remind({
    required String groupId,
    required String memberId,
    required String currency,
  }) => fetch(
    _groups.remind(
      groupId: groupId,
      reminderInput: api.ReminderInput(memberId: memberId, currency: currency),
    ),
  );

  /// Records that this account has looked at the group's activity up to
  /// [seenAt], and returns where the account stands, which is later when
  /// another of its devices has read further.
  Future<DateTime> markSeen(String groupId, DateTime seenAt) async {
    final seen = await fetch(
      _groups.putSeen(
        groupId: groupId,
        seenInput: api.SeenInput(seenAt: seenAt.toUtc()),
      ),
    );
    return seen.seenAt;
  }
}
