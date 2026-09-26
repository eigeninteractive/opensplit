import 'package:opensplit_api/opensplit_api.dart' as api;

import '../calendar_date.dart';
import 'entry.dart';

/// The after-image the server records for [entry], computed on the device.
api.EntrySnapshot snapshotOf(Entry entry) => api.EntrySnapshot(
  kind: entry.kind,
  description: entry.description,
  currency: entry.currency,
  amountMinor: entry.amountMinor,
  entryDate: calendarDate(entry.entryDate),
  splitKind: entry.splitKind,
  categoryId: entry.categoryId,
  notes: entry.notes,
  deletedAt: entry.deletedAt?.toUtc(),
  payers: _sorted([
    for (final payer in entry.payers)
      api.MoneyRow(memberId: payer.memberId, amountMinor: payer.amountMinor),
  ]),
  shares: _sorted([
    for (final share in entry.shares)
      api.MoneyRow(memberId: share.memberId, amountMinor: share.amountMinor),
  ]),
);

List<api.MoneyRow> _sorted(List<api.MoneyRow> rows) =>
    rows..sort((a, b) => a.memberId.compareTo(b.memberId));
