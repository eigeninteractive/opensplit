import 'dart:convert';

import 'package:opensplit/domain/export/json_export.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/group.dart';
import 'package:opensplit/domain/models/member.dart';
import 'package:opensplit/domain/models/profile.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

void main() {
  final group = Group(
    id: 'g1',
    name: 'Goa trip',
    defaultCurrency: 'INR',
    createdBy: 'priya-account',
    createdAt: DateTime.utc(2026, 6, 1),
  );

  final priya = Member(
    id: 'm-priya',
    groupId: 'g1',
    joinedAt: DateTime.utc(2026, 6, 1),
    profileId: 'priya-account',
    // Deliberately stale: the account renamed itself afterwards, and this is
    // the copy that used to be the source of truth.
    displayName: 'Priya (old)',
  );

  final ravi = Member(
    id: 'm-ravi',
    groupId: 'g1',
    joinedAt: DateTime.utc(2026, 6, 2),
    displayName: 'Ravi',
    upiVpa: 'ravi@bank',
  );

  const profiles = {
    'priya-account': Profile(
      id: 'priya-account',
      displayName: 'Priya S',
      upiVpa: 'priya@upi',
    ),
  };

  String nameOf(Member m) {
    final claimed = profiles[m.profileId]?.displayName ?? '';
    return claimed.isEmpty ? m.displayName : claimed;
  }

  final entry = Entry(
    id: 'e1',
    groupId: 'g1',
    kind: EntryKind.expense,
    description: 'Dinner',
    currency: 'INR',
    amountMinor: 30000,
    entryDate: DateTime.utc(2026, 6, 4),
    splitKind: SplitKind.shares,
    createdBy: 'm-priya',
    createdAt: DateTime.utc(2026, 6, 10),
    updatedAt: DateTime.utc(2026, 6, 12),
    payers: const [EntryPayer(memberId: 'm-priya', amountMinor: 30000)],
    shares: const [
      EntryShare(
        memberId: 'm-priya',
        amountMinor: 20000,
        weightMicros: 2000000,
      ),
      EntryShare(memberId: 'm-ravi', amountMinor: 10000, weightMicros: 1000000),
    ],
  );

  Map<String, dynamic> export({List<EntryEvent> activity = const []}) =>
      jsonDecode(
            groupToJson(
              group: group,
              members: [priya, ravi],
              entries: [entry],
              profiles: profiles,
              nameOf: nameOf,
              activity: activity,
            ),
          )
          as Map<String, dynamic>;

  test('carries a version, so anything reading it can tell what it has', () {
    expect(export()['version'], jsonExportVersion);
  });

  test('names members by their account, and says where the name came from', () {
    final members = export()['members'] as List;
    final claimed = members.first as Map<String, dynamic>;

    expect(
      claimed['name'],
      'Priya S',
      reason:
          'an export naming her by a stale copy in the member row would '
          'disagree with every screen in the app',
    );
    expect(claimed['placeholder_name'], 'Priya (old)');
    expect(claimed['has_account'], isTrue);
    expect(claimed['upi_vpa'], 'priya@upi');
  });

  test('keeps a placeholder as a placeholder', () {
    final unclaimed = (export()['members'] as List)[1] as Map<String, dynamic>;

    expect(unclaimed['name'], 'Ravi');
    expect(unclaimed['has_account'], isFalse);
    expect(
      unclaimed['upi_vpa'],
      'ravi@bank',
      reason:
          'settling with somebody who has no account is exactly when the '
          'handle on the member row is the only one there is',
    );
  });

  test('keeps both the rule and the result of a split', () {
    final shares =
        ((export()['entries'] as List).single as Map<String, dynamic>)['shares']
            as List;

    expect(shares, hasLength(2));
    expect((shares.first as Map)['amount_minor'], 20000);
    expect(
      (shares.first as Map)['weight_micros'],
      2000000,
      reason:
          'amounts alone cannot be re-edited as "2:1"; weights alone let a '
          'later rounding change move money that was already settled',
    );
  });

  test('writes amounts in minor units, exactly as stored', () {
    final row = (export()['entries'] as List).single as Map<String, dynamic>;
    expect(row['amount_minor'], 30000);
    expect(row['currency'], 'INR');
  });

  test('includes the activity log', () {
    final events =
        export(
              activity: [
                EntryEvent(
                  id: 'ev1',
                  entryId: 'e1',
                  groupId: 'g1',
                  actorId: 'm-priya',
                  kind: EntryEventKind.edited,
                  createdAt: DateTime.utc(2026, 6, 12),
                  changes: const [
                    FieldChange(
                      field: 'amount_minor',
                      from: '40000',
                      to: '30000',
                    ),
                  ],
                ),
              ],
            )['activity']
            as List;

    final event = events.single as Map<String, dynamic>;
    expect(event['kind'], 'edited');
    expect(event['actor_id'], 'm-priya');
    expect((event['changes'] as Map)['amount_minor'], {
      'from': '40000',
      'to': '30000',
    });
  });

  test('is valid JSON that round trips', () {
    final text = groupToJson(
      group: group,
      members: [priya, ravi],
      entries: [entry],
      profiles: profiles,
      nameOf: nameOf,
    );
    expect(() => jsonDecode(text), returnsNormally);
    expect(text, contains('\n'), reason: 'indented, because people open it');
  });
}
