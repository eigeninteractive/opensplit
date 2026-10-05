/// Settle up's state: who pays whom, how much, and where the money goes.
library;

import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/local/database.dart';
import '../domain/calendar_date.dart';
import '../domain/entry_draft.dart';
import '../domain/money_format.dart';
import 'ledger_providers.dart';
import 'local_providers.dart';

part 'settlement_form.freezed.dart';
part 'settlement_form.g.dart';

/// A UPI ID somebody typed, and the person it was typed for.
typedef TypedHandle = ({String payeeId, String handle});

/// Everything on the settle up screen, exactly as entered.
@freezed
abstract class SettlementFormState with _$SettlementFormState {
  const factory SettlementFormState({
    String? fromId,
    String? toId,
    required String currencyCode,
    @Default('') String amount,

    /// A UPI ID typed over the payee's own. It is only ever read back for
    /// the payee it was typed for, so choosing somebody else can never hand
    /// a payment app the last person's handle.
    TypedHandle? typedHandle,
    @Default(false) bool saving,
    String? error,
  }) = _SettlementFormState;

  const SettlementFormState._();

  /// Where the money goes: whatever was typed for this payee, or else the
  /// handle the group knows them by.
  String? handleIn(GroupLedger ledger) {
    final to = toId;
    if (to == null) return null;
    if (typedHandle case (
      payeeId: final payee,
      :final handle,
    ) when payee == to) {
      return handle;
    }
    return knownHandleIn(ledger);
  }

  /// The payee's handle as the group knows it.
  String? knownHandleIn(GroupLedger ledger) {
    final payee = toId == null ? null : ledger.memberById(toId!);
    return payee == null ? null : ledger.upiOf(payee);
  }

  /// The payment this form describes in [groupId], made [at] in [zone], or
  /// what is still missing from it.
  DraftCheck check(
    Currency currency, {
    required String groupId,
    required DateTime at,
    String? zone,
  }) {
    final (from, to) = (fromId, toId);
    if (from == null || to == null || from == to) {
      return const DraftIncomplete('Choose who is paying whom.');
    }
    final amountMinor = currency.parseToMinor(amount);
    if (amountMinor == null) {
      return DraftIncomplete(
        currency.exponent == 0
            ? 'Enter a whole amount.'
            : 'Enter an amount with at most ${currency.exponent} decimal '
                  'places.',
      );
    }
    if (amountMinor <= 0) {
      return const DraftIncomplete('Enter an amount greater than zero.');
    }
    return DraftReady(
      EntryDraft.settlement(
        groupId: groupId,
        currency: currency.code,
        amountMinor: amountMinor,
        fromMemberId: from,
        toMemberId: to,
        entryDate: calendarDay(at),
        // With no zone known yet, only the day is kept.
        occurredAt: zone == null ? null : at.toUtc(),
        timeZone: zone,
      ),
    );
  }
}

/// Settling up in one group, optionally prefilled with a suggested payment.
///
/// Seeded once, as soon as the group and the currencies have arrived, and
/// listened to rather than watched after that, as the expense editor is.
@riverpod
class SettlementForm extends _$SettlementForm {
  @override
  Future<SettlementFormState> build(
    String groupId, {
    String? fromId,
    String? toId,
    int? amountMinor,
    String? currency,
  }) {
    final seeded = Completer<SettlementFormState>();
    void seed() {
      if (seeded.isCompleted) return;
      final ledger = ref.read(groupLedgerProvider(groupId));
      final currencies = ref.read(currenciesProvider).value;
      if (ledger == null || currencies == null) return;

      final from = fromId ?? ledger.me?.id;
      final code = currency ?? ledger.group.defaultCurrency;
      final amount = amountMinor;
      seeded.complete(
        SettlementFormState(
          fromId: from,
          toId: toId == from ? null : toId,
          currencyCode: code,
          amount: amount == null
              ? ''
              : currencies[code]?.formatPlain(amount) ?? '',
        ),
      );
    }

    ref.listen(groupLedgerProvider(groupId), (_, _) => seed());
    ref.listen(currenciesProvider, (_, _) => seed());
    seed();
    return seeded.future;
  }

  SettlementFormState get _form => state.requireValue;

  void _change(SettlementFormState Function(SettlementFormState form) change) =>
      state = AsyncData(change(_form).copyWith(error: null));

  /// Paying yourself is not a payment, so choosing the payee as the payer
  /// leaves nobody being paid.
  void choosePayer(String? id) => _change(
    (form) => form.copyWith(
      fromId: id,
      toId: id != null && id == form.toId ? null : form.toId,
    ),
  );

  void choosePayee(String? id) => _change((form) => form.copyWith(toId: id));

  void chooseCurrency(String code) =>
      _change((form) => form.copyWith(currencyCode: code));

  void setAmount(String text) => _change((form) => form.copyWith(amount: text));

  /// A UPI ID typed for whoever is being paid now.
  void setHandle(String text) => _change((form) {
    final to = form.toId;
    return to == null
        ? form
        : form.copyWith(typedHandle: (payeeId: to, handle: text));
  });

  /// Records the payment, and says whether it was recorded. When it was not,
  /// the state says why.
  Future<bool> record() async {
    final form = _form;
    final ledger = ref.read(groupLedgerProvider(groupId));
    final currency = ref.read(currenciesProvider).value?[form.currencyCode];
    if (ledger == null || currency == null || form.saving) return false;

    // Paid now, here. Saving never waits to learn where "here" is.
    final check = form.check(
      currency,
      groupId: groupId,
      at: DateTime.now(),
      zone: ref.read(deviceZoneProvider).value,
    );
    final EntryDraft draft;
    switch (check) {
      case DraftIncomplete(:final reason):
        state = AsyncData(form.copyWith(error: reason));
        return false;
      case DraftReady(draft: final ready):
        draft = ready;
    }

    state = AsyncData(form.copyWith(saving: true, error: null));
    try {
      await ref
          .read(entryRepositoryProvider)
          .create(
            draft,
            createdBy: ledger.me?.id ?? draft.payerAmounts.keys.first,
          );
      return true;
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(_form.copyWith(saving: false, error: '$error'));
      }
      return false;
    }
  }
}
