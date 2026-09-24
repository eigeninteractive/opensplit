import '../../domain/models/category.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import '../../domain/models/group.dart';
import '../../domain/models/group_event.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';

/// What kind of "no" the server said.
///
/// Read off the refusal rather than inferred from a status code, which is a
/// change of kind rather than of spelling. The obvious rule — 409 is a
/// conflict a person resolves, every other 4xx is permanent — is not true of
/// this API: six refusals are a truthful 409, because the request genuinely
/// conflicts with the resource's current state, and only one of them is worth
/// composing again. A device reading the number would spin on its outbox.
enum RejectionKind {
  /// Worth another attempt later: a dropped connection, a timeout, a restart.
  transient,

  /// Refused identically forever — a violated invariant, a denied permission.
  /// Retrying only wedges everything queued behind it.
  permanent,

  /// Composed against a version of the row that somebody has since changed.
  ///
  /// The third kind, and it had to be added rather than folded into one of the
  /// other two. Retrying is pointless, because the same stale base is refused
  /// the same way forever. But it is not permanent either: a person can look
  /// at both versions and say which they meant. It is the one rejection whose
  /// resolution is a decision rather than a wait.
  stale,
}

/// Raised when the server rejects a write.
class RemoteRejected implements Exception {
  const RemoteRejected(
    this.message, {
    this.kind = RejectionKind.transient,
    this.code,
  });

  final String message;
  final RejectionKind kind;

  /// The server's own word for what it refused, when it gave one.
  ///
  /// Carried so a screen can say something specific — "that place has already
  /// been claimed" rather than "conflict" — without the client re-deriving it
  /// from a status and a message.
  final String? code;

  @override
  String toString() =>
      'RemoteRejected($kind${code == null ? '' : ' $code'}): $message';
}

/// Who this device is signed in as, and which groups to ask.
///
/// The one question no group can answer about itself. Everything else here is
/// addressed by a group id the caller already holds; this is where a second
/// device or a reinstall finds out those ids exist at all.
class RemoteBootstrap {
  const RemoteBootstrap({
    required this.profileId,
    required this.displayName,
    required this.upiVpa,
    required this.isAnonymous,
    required this.groupIds,
  });

  final String profileId;
  final String? displayName;
  final String? upiVpa;
  final bool isAnonymous;

  /// Groups this account is still in. A group left is a group not listed.
  final List<String> groupIds;
}

/// One page of one group's history.
///
/// One request and one integer, where there used to be four requests and four
/// `(timestamp, id)` keyset cursors per group per sync. The group's Durable
/// Object is its only writer, so it can hand out a strictly increasing number,
/// and everything in a page is ordered by it.
///
/// A page is cut only between sequence numbers, never inside one. Every row
/// written by one change shares a number, so a device sees a whole change or
/// none of it and can never hold an expense whose shares have not arrived.
class GroupChanges {
  const GroupChanges({
    required this.groupId,
    required this.seq,
    required this.hasMore,
    required this.purgedAt,
    required this.group,
    required this.members,
    required this.entries,
    required this.events,
  });

  /// Which group this page describes, as the server states it.
  ///
  /// Taken from the response rather than from the request that produced it,
  /// which is what makes a page answering for the wrong group detectable
  /// instead of silently merged into the right one's tables.
  final String groupId;

  /// Send this back as `since` next time. Unchanged when nothing moved.
  final int seq;

  final bool hasMore;

  /// Set once, on the page that carries the end of the group.
  ///
  /// A group archived, a year silent and settled is collected, and everything
  /// about it is deleted. A device reading this drops its local copy — which
  /// it can only do if somebody tells it.
  final DateTime? purgedAt;

  /// Null when the group's own row has not changed since the cursor.
  final Group? group;

  final List<Member> members;
  final List<Entry> entries;
  final List<GroupEventRow> events;
}

/// The entire surface the client needs from a server.
///
/// Deliberately small, and deliberately free of business logic: the server
/// stores facts and enforces the rules only it can — who is a member, whether
/// an expense balances, whether somebody else has moved the money since. Every
/// other calculation in this app happens on the device.
abstract interface class RemoteLedgerApi {
  /// Who I am and which groups to ask. See [RemoteBootstrap].
  Future<RemoteBootstrap> bootstrap();

  /// Everything that changed in one group after [since].
  ///
  /// Includes soft-deleted expenses and members who have left. Both are
  /// changes like any other: filter them out and a deleted expense lives
  /// forever on every device that had already synced it.
  Future<GroupChanges> pullChanges({
    required String groupId,
    required int since,
    required int limit,
  });

  /// Writes an expense with its payers and shares in one call.
  ///
  /// Idempotent on `clientKey`: a retry after a dropped connection produces no
  /// duplicate. Returns the stored expense carrying the server's sequence
  /// number, which the caller adopts as the base for the next edit.
  ///
  /// [Entry.seq] on the argument is the version this edit was composed
  /// against, and is null for a row this device invented. Throws
  /// [RemoteRejected] with [RejectionKind.stale] when that base has moved
  /// *and* applying the write would move money — a stale base on its own is
  /// not refused, because two people fixing a typo should not have to
  /// arbitrate.
  Future<Entry> pushEntry(Entry entry);

  /// Soft-deletes an expense composed against [baseSeq].
  ///
  /// Deleting always moves money — every payer and share leaves the live
  /// balance — so unlike a prose edit this must carry the exact version the
  /// device last saw, and a missing one is a refusal rather than a licence. A
  /// retry is idempotent once the server holds the tombstone.
  Future<Entry> deleteEntry({
    required String groupId,
    required String entryId,
    required int baseSeq,
  });

  /// Puts a deleted expense back. The counterpart of [deleteEntry], and the
  /// reason the activity feed's `restored` kind is reachable at all.
  Future<Entry> restoreEntry({
    required String groupId,
    required String entryId,
    required int baseSeq,
  });

  /// Creates the group and its creator's member row in one call.
  ///
  /// Both, because that is what removes the bootstrap problem: gating member
  /// writes on membership is unsatisfiable for the first member. Idempotent
  /// for the account that made it, so a retry whose response was lost returns
  /// the same group rather than refusing.
  Future<Group> createGroup(Group group, {required Member creator});

  /// Renames, archives, or changes a setting. Returns the stored row so the
  /// caller can adopt the server's sequence number.
  Future<Group> updateGroup(Group group);

  /// Adds somebody who has never opened the app.
  Future<Member> addMember(Member member);

  /// Changes a name, a payment handle, or whether somebody is still here.
  Future<Member> updateMember(Member member);

  /// Every profile belonging to somebody you share a group with, plus your own.
  ///
  /// The one feed still cursored on a timestamp, and honestly so: profiles
  /// live in a database several requests write concurrently, so there is
  /// nothing there that can issue a sequence number.
  Future<ProfilePage> pullProfiles({
    DateTime? since,
    String? sinceId,
    required int limit,
  });

  /// Exactly these profiles, cursor or no cursor.
  ///
  /// The one thing [pullProfiles] structurally cannot do. A cursor orders
  /// changes within what you can already see; it cannot surface a row that only
  /// just became visible to you. When somebody claims a placeholder, their
  /// account may have been named years ago — the row is old, the cursor is past
  /// it, and no incremental pull will ever mention it again.
  ///
  /// The member change is the signal that visibility moved, so the sync asks
  /// for those profiles by name.
  Future<List<Profile>> pullProfilesByIds(List<String> ids);

  /// Writes your own name and payment handle. The server refuses any other row.
  Future<Profile> pushProfile(Profile profile);

  /// Every currency and category the server knows about.
  ///
  /// Whole rather than paged, which is proportionate rather than lazy: there
  /// are a couple of dozen rows between them and they change about never.
  ///
  /// One call for both, because the server answers both from one response —
  /// they are the same kind of thing, they change together, and they are the
  /// two lists a device cannot create a group without. Two calls to one cached
  /// route was the shape of the tables they used to be, not of the data.
  Future<ReferenceData> pullReference();

  /// Exchange rates published on or after [since] (`yyyy-MM-dd`).
  ///
  /// Immutable once published — a rate for a past date never changes — so the
  /// client keeps a high-water mark and only asks for what came after it.
  Future<List<RemoteFxRate>> pullFxRates({required String since});

  /// Asks the server to fetch rates for a currency on a date it has never
  /// needed before. Fire and forget; the rate arrives on a later sync.
  Future<void> requestFxBackfill({
    required DateTime asOf,
    required String currency,
  });
}

/// The currencies and categories a device needs before it can do anything.
///
/// Not a page and not cursored: it is the whole of both lists, every time. They
/// are a few dozen rows that change about never, and a device that has not
/// learned what a currency is cannot create a group at all — so an incremental
/// feed would be machinery in front of an answer that fits in one response.
class ReferenceData {
  const ReferenceData({required this.currencies, required this.categories});

  const ReferenceData.empty()
    : currencies = const <Currency>[],
      categories = const <Category>[];

  final List<Currency> currencies;
  final List<Category> categories;
}

/// One page of the profile feed, with the keyset cursor it ended at.
class ProfilePage {
  const ProfilePage({
    required this.rows,
    required this.cursor,
    required this.cursorId,
    required this.hasMore,
  });

  const ProfilePage.empty()
    : rows = const <Profile>[],
      cursor = null,
      cursorId = null,
      hasMore = false;

  final List<Profile> rows;

  /// Where the feed stands after [rows], or null when [rows] is empty.
  final DateTime? cursor;
  final String? cursorId;
  final bool hasMore;
}

/// One published rate, against USD.
class RemoteFxRate {
  const RemoteFxRate({
    required this.asOf,
    required this.currency,
    required this.rate,
    required this.source,
  });

  /// Publication date, `yyyy-MM-dd`.
  final String asOf;
  final String currency;

  /// Units of [currency] per one USD.
  final double rate;
  final String source;
}
