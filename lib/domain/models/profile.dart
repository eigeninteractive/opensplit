import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';

/// Someone with an account.
///
/// Distinct from a [Member]: a profile is a person across the whole app, while
/// a member is that person's place in one group. Financial rows never reference
/// a profile, which is what lets a group contain people who have no account at
/// all.
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,

    /// Null until somebody chooses one.
    ///
    /// Nullable rather than defaulted, because "nobody has said who this is"
    /// and "this person is called Someone" are different facts and the app has
    /// to act differently on them: the first is a question to ask once, the
    /// second is an answer to respect. A sentinel string cannot tell them
    /// apart, which is how the same name came to be asked for in three places.
    ///
    /// Display sites do not need to handle it: a name is only ever rendered
    /// through [GroupLedger.nameOfMember], which falls back to the member row —
    /// and a member always has a name.
    String? displayName,
    String? avatarUrl,

    /// UPI virtual payment address. Personal rather than group-scoped — you
    /// have one payment identity, not one per group.
    String? upiVpa,

    /// The server's timestamp, and the cursor the profiles pull advances on.
    ///
    /// Null for a row this device wrote and has not pushed yet: the server
    /// sets it, because a device clock deciding what other devices consider
    /// new is how two phones with skewed clocks lose an edit between them.
    DateTime? updatedAt,
  }) = _Profile;
}
