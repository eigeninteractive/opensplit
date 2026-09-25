/// Where the generated wire types meet local storage, in both directions.
///
/// The only translation between the two, and it exists because a local row is
/// not a server row:
///
/// - it can exist before the server has seen it, so `seq` is nullable here
///   and required on the wire;
/// - one local database holds every group, so rows carry the `groupId` that
///   the server states once per page;
/// - an expense is three tables here and one nested object on the wire;
/// - a calendar date is a `DateTime` here and `yyyy-MM-dd` on the wire.
///
/// Requests are built from the current local row at push time, which is why
/// the outbound half is here too.
library;

import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/calendar_date.dart';
import '../../domain/models/entry.dart';
import '../local/database.dart';

// ------------------------------------------------------------------- inbound

extension GroupFromWire on api.Group {
  Group toRow() => Group(
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

extension MemberFromWire on api.Member {
  Member toRow(String groupId) => Member(
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

extension EntryFromWire on api.Entry {
  Entry toEntry(String groupId) => Entry(
    id: id,
    groupId: groupId,
    kind: kind,
    description: description,
    categoryId: categoryId,
    currency: currency,
    amountMinor: amountMinor,
    entryDate: parseCalendarDate(entryDate),
    splitKind: splitKind,
    payers: [
      for (final payer in payers)
        EntryPayer(memberId: payer.memberId, amountMinor: payer.amountMinor),
    ],
    shares: [
      for (final share in shares)
        EntryShare(
          memberId: share.memberId,
          amountMinor: share.amountMinor,
          weightMicros: share.weightMicros,
        ),
    ],
    fxRate: fxRate?.toDouble(),
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

extension EventFromWire on api.Event {
  GroupEventRow toRow(String groupId) => GroupEventRow(
    id: id,
    groupId: groupId,
    actorId: actorId,
    createdAt: createdAt,
    kind: kind,
    subjectId: subjectId,
    payload: payload,
    seq: seq,
    ordinal: ordinal,
    isProvisional: false,
  );
}

/// A deleted account arrives emptied rather than removed, and renders as
/// nobody, so `deletedAt` has no local column.
extension ProfileFromWire on api.Profile {
  Profile toRow() => Profile(
    id: id,
    displayName: displayName,
    upiVpa: upiVpa,
    updatedAt: updatedAt,
  );
}

extension CurrencyFromWire on api.Currency {
  Currency toRow() =>
      Currency(code: code, exponent: exponent, symbol: symbol, name: name);
}

extension CategoryFromWire on api.Category {
  Category toRow() => Category(id: id, name: name, icon: icon);
}

// ------------------------------------------------------------------ outbound

extension EntryToWire on Entry {
  /// The request that records this entry. [Entry.seq] goes as `baseSeq`: the
  /// version this edit was composed against, null for a row the server has
  /// never seen.
  api.EntryInput toInput() => api.EntryInput(
    id: id,
    kind: kind,
    description: description,
    categoryId: categoryId,
    currency: currency,
    amountMinor: amountMinor,
    entryDate: calendarDate(entryDate),
    splitKind: splitKind,
    fxRate: fxRate,
    fxSource: fxSource,
    notes: notes,
    clientKey: clientKey,
    baseSeq: seq,
    payers: [
      for (final payer in payers)
        api.Payer(memberId: payer.memberId, amountMinor: payer.amountMinor),
    ],
    shares: [
      for (final share in shares)
        api.Share(
          memberId: share.memberId,
          amountMinor: share.amountMinor,
          weightMicros: share.weightMicros,
        ),
    ],
  );
}

extension GroupToWire on Group {
  api.GroupCreate toCreate(Member creator) => api.GroupCreate(
    id: id,
    name: name,
    defaultCurrency: defaultCurrency,
    isDirect: isDirect,
    simplifyDebts: simplifyDebts,
    memberId: creator.id,
    displayName: creator.displayName,
  );

  api.GroupUpdate toUpdate() => api.GroupUpdate(
    name: name,
    simplifyDebts: simplifyDebts,
    archivedAt: archivedAt,
  );
}

extension MemberToWire on Member {
  api.MemberCreate toCreate() =>
      api.MemberCreate(id: id, displayName: displayName, upiVpa: upiVpa);

  api.MemberUpdate toUpdate() => api.MemberUpdate(
    displayName: displayName,
    upiVpa: upiVpa,
    leftAt: leftAt,
  );
}

extension ProfileToWire on Profile {
  api.ProfileUpdate toUpdate() =>
      api.ProfileUpdate(displayName: displayName, upiVpa: upiVpa);
}
