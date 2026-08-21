import 'package:freezed_annotation/freezed_annotation.dart';

part 'member_balance.freezed.dart';

/// One member's net position in one currency.
///
/// Always per currency, never collapsed. A trip group can legitimately hold a
/// ₹500 balance and a €20 balance at the same time, and adding them together
/// requires picking an exchange rate — which silently assigns the FX risk to
/// whoever the rounding favours. Conversion is a display choice made at the
/// last moment, never part of the model.
@freezed
abstract class MemberBalance with _$MemberBalance {
  const factory MemberBalance({
    required String memberId,
    required String currency,

    /// Positive: this member is owed money. Negative: they owe it.
    ///
    /// Per group per currency, these sum to exactly zero. Always. If they ever
    /// do not, something is wrong with the fold and not with the data.
    required int balanceMinor,
  }) = _MemberBalance;

  const MemberBalance._();

  bool get isOwed => balanceMinor > 0;
  bool get owes => balanceMinor < 0;
}
