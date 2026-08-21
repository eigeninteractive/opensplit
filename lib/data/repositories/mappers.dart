import '../../domain/balance/member_balance.dart';
import '../../domain/models/category.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
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
    updatedAt: updatedAt,
  );
}

extension MemberRowMapper on MemberRow {
  Member toDomain() => Member(
    id: id,
    groupId: groupId,
    profileId: profileId,
    displayName: displayName,
    role: role,
    joinedAt: joinedAt,
    leftAt: leftAt,
    upiVpa: upiVpa,
    updatedAt: updatedAt,
  );
}

extension CurrencyRowMapper on CurrencyRow {
  Currency toDomain() =>
      Currency(code: code, exponent: exponent, symbol: symbol, name: name);
}

extension CategoryRowMapper on CategoryRow {
  Category toDomain() =>
      Category(id: id, groupId: groupId, name: name, icon: icon);
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
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    clientKey: clientKey,
    algoVersion: algoVersion,
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
