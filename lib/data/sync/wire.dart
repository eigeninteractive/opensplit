import '../../domain/models/entry.dart';
import '../../domain/models/entry_event.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';
import '../../domain/split/splitter.dart';

/// Codecs between domain models and the JSON the server speaks.
///
/// Hand-written rather than generated, and living in `data/` rather than on the
/// models themselves, so that the wire format is free to differ from the domain
/// and to change without dragging the domain along. Field names match the
/// Postgres columns exactly, because that is what PostgREST returns.

Map<String, dynamic> entryToJson(Entry entry) => {
  'id': entry.id,
  'group_id': entry.groupId,
  'kind': entry.kind.name,
  'description': entry.description,
  'category_id': entry.categoryId,
  'currency': entry.currency,
  'amount_minor': entry.amountMinor,
  'entry_date': _dateOnly(entry.entryDate),
  'split_kind': entry.splitKind.name,
  'fx_rate': entry.fxRate,
  'fx_source': entry.fxSource,
  'fx_at': entry.fxAt?.toUtc().toIso8601String(),
  'notes': entry.notes,
  'created_by': entry.createdBy,
  'created_at': entry.createdAt.toUtc().toIso8601String(),
  'updated_at': entry.updatedAt.toUtc().toIso8601String(),
  'deleted_at': entry.deletedAt?.toUtc().toIso8601String(),
  'client_key': entry.clientKey,
  'payers': [
    for (final payer in entry.payers)
      {'member_id': payer.memberId, 'amount_minor': payer.amountMinor},
  ],
  'shares': [
    for (final share in entry.shares)
      {
        'member_id': share.memberId,
        'amount_minor': share.amountMinor,
        'weight': share.weightMicros == null
            ? null
            : share.weightMicros! / 1000000,
      },
  ],
};

Entry entryFromJson(Map<String, dynamic> json) => Entry(
  id: json['id'] as String,
  groupId: json['group_id'] as String,
  kind: EntryKind.values.byName(json['kind'] as String),
  description: (json['description'] as String?) ?? '',
  categoryId: json['category_id'] as String?,
  currency: json['currency'] as String,
  amountMinor: (json['amount_minor'] as num).toInt(),
  entryDate: DateTime.parse(json['entry_date'] as String),
  splitKind: SplitKind.values.byName(json['split_kind'] as String),
  fxRate: (json['fx_rate'] as num?)?.toDouble(),
  fxSource: json['fx_source'] as String?,
  fxAt: _parseOrNull(json['fx_at']),
  notes: json['notes'] as String?,
  createdBy: json['created_by'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  deletedAt: _parseOrNull(json['deleted_at']),
  clientKey: json['client_key'] as String?,
  payers: [
    for (final payer in (json['payers'] as List? ?? const []))
      EntryPayer(
        memberId: (payer as Map)['member_id'] as String,
        amountMinor: (payer['amount_minor'] as num).toInt(),
      ),
  ],
  shares: [
    for (final share in (json['shares'] as List? ?? const []))
      EntryShare(
        memberId: (share as Map)['member_id'] as String,
        amountMinor: (share['amount_minor'] as num).toInt(),
        // `weight` is numeric(24,6) on the server; the client holds it as
        // integer micros so that split arithmetic never touches a float.
        weightMicros: share['weight'] == null
            ? null
            : ((share['weight'] as num) * 1000000).round(),
      ),
  ],
);

Map<String, dynamic> groupToJson(Group group) => {
  'id': group.id,
  'name': group.name,
  'default_currency': group.defaultCurrency,
  'is_direct': group.isDirect,
  'simplify_debts': group.simplifyDebts,
  'created_by': group.createdBy,
  'created_at': group.createdAt.toUtc().toIso8601String(),
  'archived_at': group.archivedAt?.toUtc().toIso8601String(),
  // updated_at is deliberately absent. The server stamps it with now() on
  // write, so sending a device clock could only corrupt the comparison it
  // exists to make.
};

Group groupFromJson(Map<String, dynamic> json) => Group(
  id: json['id'] as String,
  name: json['name'] as String,
  defaultCurrency: json['default_currency'] as String,
  isDirect: (json['is_direct'] as bool?) ?? false,
  simplifyDebts: (json['simplify_debts'] as bool?) ?? true,
  createdBy: json['created_by'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  archivedAt: _parseOrNull(json['archived_at']),
  updatedAt: _parseOrNull(json['updated_at']),
);

Map<String, dynamic> memberToJson(Member member) => {
  'id': member.id,
  'group_id': member.groupId,
  // Omitted entirely when this device does not know of an account for this
  // member, rather than sent as null.
  //
  // PostgREST builds the upsert's SET list from the keys present, so an absent
  // key leaves the stored value alone while a null overwrites it. That matters
  // for exactly one column and exactly one race: someone claims their invite,
  // and before this device has pulled the claim it pushes an unrelated edit to
  // the same row — a rename, a UPI handle. Sending profile_id: null there would
  // blank the claim and un-join the person who had just joined. Absent on an
  // INSERT is the same as null, so the placeholder case still works.
  if (member.profileId != null) 'profile_id': member.profileId,
  'display_name': member.displayName,
  'role': member.role.name,
  'joined_at': member.joinedAt.toUtc().toIso8601String(),
  'left_at': member.leftAt?.toUtc().toIso8601String(),
  'upi_vpa': member.upiVpa,
};

Member memberFromJson(Map<String, dynamic> json) => Member(
  id: json['id'] as String,
  groupId: json['group_id'] as String,
  profileId: json['profile_id'] as String?,
  displayName: json['display_name'] as String,
  role: MemberRole.values.byName((json['role'] as String?) ?? 'member'),
  joinedAt: DateTime.parse(json['joined_at'] as String),
  leftAt: _parseOrNull(json['left_at']),
  upiVpa: json['upi_vpa'] as String?,
  updatedAt: _parseOrNull(json['updated_at']),
);

DateTime? _parseOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// `entry_date` is a Postgres `date`, with no time and no zone.
String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Profiles
// ---------------------------------------------------------------------------

/// Only the two fields a person owns.
///
/// `id` is sent so the upsert knows which row, and the server's own policy
/// pins it to auth.uid() anyway. `created_at` and `updated_at` are the
/// server's to set: a client clock has no business deciding the cursor other
/// devices sync against.
Map<String, dynamic> profileToJson(Profile profile) => {
  'id': profile.id,
  'display_name': profile.displayName,
  'upi_vpa': profile.upiVpa,
};

Profile profileFromJson(Map<String, dynamic> json) => Profile(
  id: json['id'] as String,
  displayName: json['display_name'] as String,
  avatarUrl: json['avatar_url'] as String?,
  upiVpa: json['upi_vpa'] as String?,
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------

/// One-way: the server writes these, the client only reads them.
///
/// There is deliberately no `entryEventToJson`. The table has no insert policy
/// and no INSERT grant, so a client that tried would be refused twice over —
/// and a serialiser sitting here would suggest otherwise to whoever read this
/// file next.
EntryEvent entryEventFromJson(Map<String, dynamic> json) => EntryEvent(
  id: json['id'] as String,
  entryId: json['entry_id'] as String,
  groupId: json['group_id'] as String,
  actorId: json['actor_id'] as String,
  kind: EntryEventKind.values.byName(json['kind'] as String),
  createdAt: DateTime.parse(json['created_at'] as String),
  changes: changesFromJson(json['changes']),
);

/// Turns the trigger's diff object into a flat list.
///
/// Shaped `{"amount_minor": {"from": 40000, "to": 30000}}` on the wire, which
/// is convenient for Postgres to build and awkward to render. Unknown keys are
/// carried through rather than dropped: a column added to the diff later should
/// appear in the feed as an unfamiliar row, not vanish.
List<FieldChange> changesFromJson(Object? raw) {
  if (raw is! Map) return const [];
  final changes = <FieldChange>[
    for (final entry in raw.entries)
      if (entry.value is Map)
        FieldChange(
          field: entry.key as String,
          from: (entry.value as Map)['from']?.toString(),
          to: (entry.value as Map)['to']?.toString(),
        ),
  ];
  // Stable order, so the same edit reads the same way on every device.
  changes.sort((a, b) => a.field.compareTo(b.field));
  return changes;
}
