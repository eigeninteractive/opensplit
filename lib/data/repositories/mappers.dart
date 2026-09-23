import 'dart:convert';

import '../../domain/balance/member_balance.dart';
import '../../domain/models/category.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import '../../domain/models/group_event.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';
import '../local/database.dart';

/// Translations between Drift row classes and domain models.
///
/// Kept in one place so the domain never sees a generated row type, and so a
/// change of storage engine touches this file rather than every screen.
extension GroupRowMapper on GroupRow {
  Group toDomain() => Group(
    id: id,
    name: name,
    defaultCurrency: defaultCurrency,
    isDirect: isDirect,
    simplifyDebts: simplifyDebts,
    createdBy: createdBy,
    createdAt: createdAt,
    archivedAt: archivedAt,
    seq: seq,
  );
}

extension MemberRowMapper on MemberRow {
  Member toDomain() => Member(
    id: id,
    groupId: groupId,
    profileId: profileId,
    displayName: displayName,
    joinedAt: joinedAt,
    leftAt: leftAt,
    upiVpa: upiVpa,
    seq: seq,
  );
}

extension ProfileRowMapper on ProfileRow {
  Profile toDomain() => Profile(
    id: id,
    displayName: displayName,
    avatarUrl: avatarUrl,
    upiVpa: upiVpa,
    updatedAt: updatedAt,
  );
}

extension CurrencyRowMapper on CurrencyRow {
  Currency toDomain() =>
      Currency(code: code, exponent: exponent, symbol: symbol, name: name);
}

extension CategoryRowMapper on CategoryRow {
  Category toDomain() => Category(id: id, name: name, icon: icon);
}

extension EntryRowMapper on EntryRow {
  /// Rebuilds a full entry. Payers and shares are passed in rather than looked
  /// up, because an entry without them is not a valid domain object and this
  /// keeps the mapper free of database access.
  Entry toDomain({
    required List<EntryPayerRow> payers,
    required List<EntryShareRow> shares,
  }) => Entry(
    id: id,
    groupId: groupId,
    kind: kind,
    description: description,
    categoryId: categoryId,
    currency: currency,
    amountMinor: amountMinor,
    entryDate: entryDate,
    splitKind: splitKind,
    payers: [
      for (final p in payers)
        EntryPayer(memberId: p.memberId, amountMinor: p.amountMinor),
    ],
    shares: [
      for (final s in shares)
        EntryShare(
          memberId: s.memberId,
          amountMinor: s.amountMinor,
          weightMicros: s.weightMicros,
        ),
    ],
    fxRate: fxRate,
    fxSource: fxSource,
    fxAt: fxAt,
    notes: notes,
    createdBy: createdBy,
    createdAt: createdAt,
    seq: seq,
    deletedAt: deletedAt,
    clientKey: clientKey,
  );
}

extension MemberBalanceLookup on List<MemberBalance> {
  /// This member's balance in [currency], or zero if they are settled.
  ///
  /// The fold omits members who net to zero, matching the server view. Callers
  /// rendering a roster need "settled", not "missing".
  int minorFor(String memberId, String currency) {
    for (final balance in this) {
      if (balance.memberId == memberId && balance.currency == currency) {
        return balance.balanceMinor;
      }
    }
    return 0;
  }
}

extension GroupEventRowMapper on GroupEventRowData {
  /// Null for a kind this build has never heard of.
  ///
  /// The row is stored regardless -- the local column is text rather than a
  /// Drift enum precisely so an unknown kind cannot fail a sync -- and it is
  /// here, on the way out, that it simply declines to become a feed line.
  GroupEventRow? toDomain() {
    final parsed = GroupEventKind.parse(kind);
    if (parsed == null) return null;

    return GroupEventRow(
      id: id,
      groupId: groupId,
      actorId: actorId,
      createdAt: createdAt,
      kind: parsed,
      subjectId: subjectId,
      payload: Map<String, Object?>.from(
        jsonDecode(payload) as Map? ?? const {},
      ),
      seq: seq,
      ordinal: ordinal,
      isProvisional: isProvisional,
    );
  }
}
