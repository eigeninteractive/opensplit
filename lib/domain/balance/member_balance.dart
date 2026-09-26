import 'package:freezed_annotation/freezed_annotation.dart';

part 'member_balance.freezed.dart';

/// One member's net position in one currency.
@freezed
abstract class MemberBalance with _$MemberBalance {
  const factory MemberBalance({
    required String memberId,
    required String currency,

    /// Positive: this member is owed money. Negative: they owe it.
    required int balanceMinor,
  }) = _MemberBalance;

  const MemberBalance._();

  bool get isOwed => balanceMinor > 0;
  bool get owes => balanceMinor < 0;
}
