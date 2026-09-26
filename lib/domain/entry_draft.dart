import 'calendar_date.dart';
import 'models/entry.dart';
import 'split/splitter.dart';

/// A user's intent to record an entry, before it has been resolved into
/// balanced payers and shares.
class EntryDraft {
  const EntryDraft({
    required this.groupId,
    required this.currency,
    required this.amountMinor,
    required this.split,
    required this.payerAmounts,
    this.kind = EntryKind.expense,
    this.description = '',
    this.categoryId,
    this.entryDate,
    this.occurredAt,
    this.timeZone,
    this.notes,
    this.fxRate,
    this.fxSource,
  });

  /// A settlement: one person pays another, recorded manually.
  factory EntryDraft.settlement({
    required String groupId,
    required String currency,
    required int amountMinor,
    required String fromMemberId,
    required String toMemberId,
    DateTime? entryDate,
    DateTime? occurredAt,
    String? timeZone,
    String? notes,
  }) {
    if (fromMemberId == toMemberId) {
      throw const SplitException('A settlement needs two different people.');
    }
    return EntryDraft(
      groupId: groupId,
      currency: currency,
      amountMinor: amountMinor,
      kind: EntryKind.settlement,
      split: ExactSplit({toMemberId: amountMinor}),
      payerAmounts: {fromMemberId: amountMinor},
      entryDate: entryDate,
      occurredAt: occurredAt,
      timeZone: timeZone,
      notes: notes,
    );
  }

  final String groupId;
  final EntryKind kind;
  final String description;
  final String? categoryId;
  final String currency;
  final int amountMinor;
  final DateTime? entryDate;

  /// When it happened and where; see [Entry.occurredAt]. The caller keeps
  /// [entryDate] consistent with them.
  final DateTime? occurredAt;
  final String? timeZone;

  /// How the total is divided.
  final SplitSpec split;

  /// Who actually put money down, and how much. Must total [amountMinor].
  final Map<String, int> payerAmounts;

  final String? notes;
  final double? fxRate;
  final String? fxSource;
}

/// Turns a [draft] into a balanced [Entry].
Entry composeEntry(
  EntryDraft draft, {
  required String id,
  required String createdBy,
  required DateTime now,
  String? clientKey,
}) {
  if (draft.amountMinor <= 0) {
    throw const SplitException('An amount is needed.');
  }

  // Seeded with the entry id, so the person who absorbs a rounding leftover
  // varies from expense to expense instead of being the same member every time
  // — and so re-editing this entry reproduces the identical split.
  final shares = draft.split.resolve(draft.amountMinor, seed: id);
  final payers = resolvePayers(
    totalMinor: draft.amountMinor,
    amountsByMemberId: draft.payerAmounts,
  );

  return Entry(
    id: id,
    groupId: draft.groupId,
    kind: draft.kind,
    description: draft.description,
    categoryId: draft.categoryId,
    currency: draft.currency,
    amountMinor: draft.amountMinor,
    entryDate: draft.entryDate ?? calendarDay(now),
    occurredAt: draft.occurredAt,
    timeZone: draft.timeZone,
    splitKind: draft.split.kind,
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
    fxRate: draft.fxRate,
    fxSource: draft.fxSource,
    fxAt: draft.fxRate == null ? null : now,
    notes: draft.notes,
    createdBy: createdBy,
    createdAt: now,
    clientKey: clientKey ?? id,
  );
}
