/// Where the generated wire types meet local storage, in both directions.
library;

import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/calendar_date.dart';
import '../../domain/models/entry.dart';
import '../local/database.dart';

extension GroupFromWire on api.Group {
  Group toRow() => Group(
    id: id,
    name: name,
    defaultCurrency: defaultCurrency,
    isDirect: isDirect,
    simplifyDebts: simplifyDebts,
    avatarKind: avatarKind,
    avatarColor: avatarColor,
    avatarEmoji: avatarEmoji,
    avatarIcon: avatarIcon,
    avatarPhoto: avatarPhoto,
    coverKind: coverKind,
    coverPhoto: coverPhoto,
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
    EntryRow(
      id: id,
      groupId: groupId,
      kind: kind,
      description: description,
      categoryId: categoryId,
      currency: currency,
      amountMinor: amountMinor,
      entryDate: parseCalendarDate(entryDate),
      occurredAt: occurredAt,
      timeZone: timeZone,
      splitKind: splitKind,
      fxRate: fxRate?.toDouble(),
      fxSource: fxSource,
      fxAt: fxAt,
      notes: notes,
      createdBy: createdBy,
      createdAt: createdAt,
      seq: seq,
      deletedAt: deletedAt,
    ),
    payers: payers,
    shares: shares,
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
    entry: entry,
    member: member,
    group: group,
    link: link,
    seq: seq,
    ordinal: ordinal,
    isProvisional: false,
  );
}

/// A deleted account arrives emptied and renders as nobody, so `deletedAt`
/// has no local column.
extension ProfileFromWire on api.Profile {
  Profile toRow() => Profile(
    id: id,
    displayName: displayName,
    upiVpa: upiVpa,
    avatarKind: avatarKind,
    avatarColor: avatarColor,
    avatarEmoji: avatarEmoji,
    avatarIcon: avatarIcon,
    avatarPhoto: avatarPhoto,
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

extension EntryToWire on Entry {
  /// [EntryRow.seq] goes as `baseSeq`: the version this edit was composed
  /// against, null for a row the server has never seen.
  api.EntryInput toInput() => api.EntryInput(
    kind: row.kind,
    description: row.description,
    categoryId: row.categoryId,
    currency: row.currency,
    amountMinor: row.amountMinor,
    entryDate: calendarDate(row.entryDate),
    occurredAt: row.occurredAt?.toUtc(),
    timeZone: row.timeZone,
    splitKind: row.splitKind,
    fxRate: row.fxRate,
    fxSource: row.fxSource,
    notes: row.notes,
    deletedAt: row.deletedAt?.toUtc(),
    baseSeq: row.seq,
    payers: payers,
    shares: shares,
  );
}

extension GroupToWire on Group {
  /// The server reads [creator] only when this creates the group.
  api.GroupInput toInput(Member creator) => api.GroupInput(
    name: name,
    defaultCurrency: defaultCurrency,
    isDirect: isDirect,
    simplifyDebts: simplifyDebts,
    archivedAt: archivedAt?.toUtc(),
    avatarKind: avatarKind,
    avatarColor: avatarColor,
    avatarEmoji: avatarEmoji,
    avatarIcon: avatarIcon,
    avatarPhoto: avatarPhoto,
    coverKind: coverKind,
    coverPhoto: coverPhoto,
    creatorId: creator.id,
    creatorName: creator.displayName,
  );
}

extension MemberToWire on Member {
  api.MemberInput toInput() => api.MemberInput(
    displayName: displayName,
    upiVpa: upiVpa,
    leftAt: leftAt?.toUtc(),
  );
}

extension ProfileToWire on Profile {
  api.ProfileUpdate toUpdate() => api.ProfileUpdate(
    displayName: displayName,
    upiVpa: upiVpa,
    avatarKind: avatarKind,
    avatarColor: avatarColor,
    avatarEmoji: avatarEmoji,
    avatarIcon: avatarIcon,
    avatarPhoto: avatarPhoto,
  );
}
