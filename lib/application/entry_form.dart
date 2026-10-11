/// The expense editor's state: what has been typed and chosen, and the one
/// way each of those changes.
library;

import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind, SplitKind;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';
import '../domain/calendar_date.dart';
import '../domain/category_guess.dart';
import '../domain/decimal_text.dart';
import '../domain/entry_draft.dart';
import '../domain/fx/fx_quote.dart';
import '../domain/models/entry.dart';
import '../domain/money_format.dart';
import '../domain/split/allocation.dart';
import '../domain/split/remainder.dart';
import '../domain/split/splitter.dart';
import 'ledger_providers.dart';
import 'local_providers.dart';
import 'sync_providers.dart';

part 'entry_form.freezed.dart';
part 'entry_form.g.dart';

/// Everything in the expense editor, exactly as entered.
///
/// Amounts stay the text that was typed: whether that text is an amount
/// depends on the currency, which can change after it was typed. What the
/// form adds up to is derived from this, never stored beside it.
@freezed
abstract class EntryFormState with _$EntryFormState {
  const factory EntryFormState({
    /// The expense as it was when the editor opened; null for a new one.
    /// Saving refuses if it has changed since.
    Entry? editing,

    /// Generated locally before previewing; nothing is stored until Save.
    /// The saved entry uses this identity to keep rounding consistent.
    String? newEntryId,
    required String currencyCode,
    @Default('') String amount,
    @Default('') String description,
    String? categoryId,

    /// Whether the category was picked by hand, or came with the expense
    /// being edited. Until then it follows the description.
    @Default(false) bool categoryChosen,

    /// The day it happened, at UTC midnight.
    required DateTime day,

    /// When on [day] it happened, and the zone it happened in: both or
    /// neither.
    DateTime? occurredAt,
    String? timeZone,
    @Default(SplitKind.equal) SplitKind splitKind,
    @Default(<String>{}) Set<String> participants,

    /// Whole shares per person, for a split by shares. One when unset.
    @Default(<String, int>{}) Map<String, int> shareCounts,

    /// Manual overrides only. An absent member shares the remainder.
    @Default(<String, String>{}) Map<String, String> exactAmounts,
    @Default(<String, String>{}) Map<String, String> percents,
    @Default(<String>{}) Set<String> payers,
    @Default(false) bool severalPayers,

    /// Manual payer overrides. Unedited payers share the remainder.
    @Default(<String, String>{}) Map<String, String> paidAmounts,
    @Default(false) bool saving,
    String? error,
  }) = _EntryFormState;

  const EntryFormState._();

  /// A new expense: everyone splits it and the person adding it paid. The
  /// overwhelmingly common case, so the fast path is two fields and Save.
  factory EntryFormState.blank(GroupLedger ledger, {required DateTime now}) {
    final me = ledger.me?.id ?? ledger.members.firstOrNull?.id;
    return EntryFormState(
      newEntryId: const Uuid().v4(),
      currencyCode: ledger.group.defaultCurrency,
      day: calendarDay(now),
      // It happened now, here, unless the time is taken off.
      occurredAt: now.toUtc(),
      participants: {for (final member in ledger.members) member.id},
      payers: {?me},
    );
  }

  /// [entry] as it stands, to be edited.
  factory EntryFormState.of(Entry entry, Currency? currency) {
    String typed(int minor) => currency?.formatPlain(minor) ?? '';
    return EntryFormState(
      editing: entry,
      currencyCode: entry.row.currency,
      amount: typed(entry.row.amountMinor),
      description: entry.row.description,
      categoryId: entry.row.categoryId,
      categoryChosen: entry.row.categoryId != null,
      day: entry.row.entryDate,
      occurredAt: entry.row.occurredAt,
      timeZone: entry.row.timeZone,
      splitKind: entry.row.splitKind,
      participants: {for (final share in entry.shares) share.memberId},
      shareCounts: {
        for (final share in entry.shares)
          if (entry.row.splitKind == SplitKind.shares)
            if (share.weightMicros case final weight?)
              share.memberId: (weight / weightScale).round(),
      },
      exactAmounts: {
        if (entry.row.splitKind == SplitKind.exact)
          for (final share in entry.shares)
            share.memberId: typed(share.amountMinor),
      },
      percents: {
        if (entry.row.splitKind == SplitKind.percent)
          for (final share in entry.shares)
            share.memberId: switch (share.weightMicros) {
              final weight? => formatPercentMicros(weight),
              null => '',
            },
      },
      payers: {for (final payer in entry.payers) payer.memberId},
      severalPayers: entry.payers.length > 1,
      paidAmounts: {
        if (entry.payers.length > 1)
          for (final payer in entry.payers)
            payer.memberId: typed(payer.amountMinor),
      },
    );
  }

  bool get isEditing => editing != null;

  /// Identity shared by preview rounding and the eventual write.
  String? get allocationSeed => editing?.id ?? newEntryId;

  /// The total in [currency], once what was typed reads as one.
  int? totalIn(Currency currency) {
    final total = currency.parseToMinor(amount);
    return total != null && total > 0 ? total : null;
  }

  int shareCountOf(String memberId) => shareCounts[memberId] ?? 1;

  /// What each person owes, from the same rule and seed used when saving.
  Map<String, int>? preview(Currency currency) {
    final total = totalIn(currency);
    if (total == null || participants.isEmpty) return null;
    final spec = _split(currency);
    if (spec == null) return null;
    try {
      return {
        for (final share in spec.resolve(total, seed: allocationSeed))
          share.memberId: share.amountMinor,
      };
    } on SplitException {
      return null;
    }
  }

  /// Selected participants' amounts, preserving manual overrides.
  RemainderAllocation? exactAllocation(Currency currency) =>
      _moneyAllocation(currency, participants, exactAmounts);

  /// Selected participants' percentages, which must total exactly 100.
  RemainderAllocation percentAllocation() => RemainderAllocation(
    total: PercentSplit.fullPercentMicros,
    memberIds: participants,
    overrides: {
      for (final entry in percents.entries)
        entry.key: parsePercentMicros(entry.value),
    },
    seed: allocationSeed,
  );

  /// Selected payers' amounts, using the same remainder calculation.
  RemainderAllocation? paidAllocation(Currency currency) =>
      _moneyAllocation(currency, payers, paidAmounts);

  RemainderAllocation? _moneyAllocation(
    Currency currency,
    Set<String> members,
    Map<String, String> overrides,
  ) {
    final total = totalIn(currency);
    if (total == null) return null;
    return RemainderAllocation(
      total: total,
      memberIds: members,
      overrides: {
        for (final entry in overrides.entries)
          entry.key: currency.parseToMinor(entry.value),
      },
      seed: allocationSeed,
    );
  }

  /// An actionable split error, also displayed beside the split inputs.
  String? splitError(Currency currency) => switch (splitKind) {
    SplitKind.exact => allocationError(exactAllocation(currency), currency),
    SplitKind.percent => allocationError(
      percentAllocation(),
      currency,
      percent: true,
    ),
    SplitKind.equal || SplitKind.shares =>
      participants.isEmpty ? 'Choose at least one participant.' : null,
    SplitKind.unknownDefaultOpenApi => 'This split method is not supported.',
  };

  /// An actionable payer error, including zero amounts that cannot be paid.
  String? paidError(Currency currency) {
    if (!severalPayers) {
      return payers.isEmpty ? 'Choose who paid.' : null;
    }
    final allocation = paidAllocation(currency);
    final error = allocationError(allocation, currency, paying: true);
    if (error != null) return error;
    if (allocation?.values.values.any((amount) => amount <= 0) ?? false) {
      return 'Each selected payer must pay more than zero. '
          'Remove a payer or adjust the amounts.';
    }
    return null;
  }

  /// Describes why an allocation cannot yet be recorded.
  static String? allocationError(
    RemainderAllocation? allocation,
    Currency currency, {
    bool percent = false,
    bool paying = false,
  }) {
    if (allocation == null) return null;
    String shown(int value) => percent
        ? '${formatPercentMicros(value.abs())}%'
        : formatMoney(currency, value.abs());
    return switch (allocation.problem) {
      RemainderProblem.noMembers =>
        paying ? 'Choose who paid.' : 'Choose at least one participant.',
      RemainderProblem.invalidOverrides =>
        percent
            ? 'Enter a valid percentage or clear this value.'
            : 'Enter a valid amount or clear this value.',
      RemainderProblem.overallocated =>
        '${shown(allocation.remaining)} over ${percent ? '100%' : 'the total'}. '
            'Reduce a value or divide evenly.',
      RemainderProblem.unallocated =>
        '${shown(allocation.remaining)} left to assign. '
            'Adjust a value or clear one to share the rest.',
      null => null,
    };
  }

  /// The expense this form describes in [groupId], or what is still missing
  /// from it.
  DraftCheck check(
    Currency currency, {
    required String groupId,
    FxQuote? fx,
    String? deviceZone,
  }) {
    if (editing?.row.kind == EntryKind.settlement) {
      return const DraftIncomplete('Use the payment editor for this payment.');
    }
    final total = totalIn(currency);
    if (total == null) {
      return DraftIncomplete(
        currency.exponent == 0
            ? 'Enter a whole amount.'
            : 'Enter an amount with at most ${currency.exponent} decimal '
                  'places.',
      );
    }
    final splitProblem = splitError(currency);
    if (splitProblem != null) return DraftIncomplete(splitProblem);
    final split = _split(currency);
    if (split == null) {
      return const DraftIncomplete(
        'Check the split — some amounts are missing.',
      );
    }
    try {
      split.resolve(total, seed: allocationSeed);
    } on SplitException catch (error) {
      return DraftIncomplete(error.message);
    }
    final paidProblem = paidError(currency);
    if (paidProblem != null) return DraftIncomplete(paidProblem);
    final paid = _paid(currency, total);
    if (paid == null) {
      return const DraftIncomplete(
        'Check who paid — some amounts are missing.',
      );
    }

    // A time with no zone yet (a new expense) is this device's. Saving never
    // waits to learn which that is: with no zone known, only the day is kept.
    final zone = timeZone ?? deviceZone;
    final moment = occurredAt;
    final timed = moment != null && zone != null;
    return DraftReady(
      EntryDraft(
        groupId: groupId,
        currency: currency.code,
        amountMinor: total,
        description: description.trim(),
        categoryId: categoryId,
        split: split,
        payerAmounts: paid,
        entryDate: day,
        occurredAt: timed ? moment : null,
        timeZone: timed ? zone : null,
        // A fact about the transaction, captured once.
        fxRate: fx?.rate,
        fxSource: fx == null ? null : '${fx.source}@${calendarDate(fx.date)}',
      ),
    );
  }

  SplitSpec? _split(Currency currency) {
    final ids = participants.toList();
    if (ids.isEmpty) return null;

    return switch (splitKind) {
      SplitKind.equal => EqualSplit(ids),
      SplitKind.shares => SharesSplit({
        for (final id in ids) id: shareCountOf(id),
      }),
      SplitKind.exact => switch (exactAllocation(currency)) {
        final allocation? when allocation.isBalanced => ExactSplit(
          allocation.values,
        ),
        _ => null,
      },
      SplitKind.percent => switch (percentAllocation()) {
        final allocation when allocation.isBalanced => PercentSplit(
          allocation.values,
        ),
        _ => null,
      },
      // A split rule from a newer server: saving would have to guess it.
      SplitKind.unknownDefaultOpenApi => null,
    };
  }

  Map<String, int>? _paid(Currency currency, int total) {
    if (!severalPayers) {
      final only = payers.firstOrNull;
      return only == null ? null : {only: total};
    }
    final allocation = paidAllocation(currency);
    return allocation != null &&
            allocation.isBalanced &&
            allocation.values.values.every((amount) => amount > 0)
        ? allocation.values
        : null;
  }
}

/// The expense editor for one group: a new expense, or [entryId] being
/// edited.
///
/// Seeded once, as soon as the group and the currencies have arrived. It
/// listens to them rather than watching, so a sync landing while the editor
/// is open never resets what has been typed; saving is what checks the
/// expense has not moved underneath it.
@riverpod
class EntryForm extends _$EntryForm {
  /// Dates and currencies a rate has already been asked for.
  final _ratesAsked = <String>{};

  @override
  FutureOr<EntryFormState> build(String groupId, {String? entryId}) {
    final seeded = Completer<EntryFormState>();
    EntryFormState? ready;
    void seed() {
      if (seeded.isCompleted) return;
      final ledger = ref.read(groupLedgerProvider(groupId));
      final currencies = ref.read(currenciesProvider).value;
      if (ledger == null || currencies == null) return;

      if (entryId == null) {
        ready = EntryFormState.blank(ledger, now: DateTime.now());
        seeded.complete(ready);
        return;
      }
      final entry = ledger.entries.where((e) => e.id == entryId).firstOrNull;
      if (entry != null) {
        ready = EntryFormState.of(entry, currencies[entry.row.currency]);
        seeded.complete(ready);
      }
    }

    ref.listen(groupLedgerProvider(groupId), (_, _) => seed());
    ref.listen(currenciesProvider, (_, _) => seed());
    seed();
    // Saved local data needs no loading frame. This also lets route Heroes
    // connect to the actual fields as soon as the editor is mounted.
    if (ready case final form?) {
      unawaited(_askForRateIfMissing(form));
      return form;
    }
    return seeded.future.then((form) {
      unawaited(_askForRateIfMissing(form));
      return form;
    });
  }

  EntryFormState get _form => state.requireValue;

  void _change(EntryFormState Function(EntryFormState form) change) {
    if (_form.saving) return;
    state = AsyncData(change(_form).copyWith(error: null));
  }

  void setAmount(String text) => _change((form) => form.copyWith(amount: text));

  /// The category follows the description until one is picked. A guess that
  /// stops matching is taken back, so typing "Uber" and then correcting it to
  /// "Usha's gift" doesn't leave the expense a taxi ride.
  void setDescription(String text) => _change((form) {
    if (form.categoryChosen) return form.copyWith(description: text);
    final icon = guessCategoryIcon(text);
    final categories = ref.read(categoriesProvider).value ?? const [];
    return form.copyWith(
      description: text,
      categoryId: categories.where((c) => c.icon == icon).firstOrNull?.id,
    );
  });

  void chooseCategory(String? id) =>
      _change((form) => form.copyWith(categoryId: id, categoryChosen: true));

  void chooseCurrency(String code) {
    _change((form) => form.copyWith(currencyCode: code));
    unawaited(_askForRateIfMissing(_form));
  }

  /// Another day: the time no longer applies, since it is not known.
  void chooseDay(DateTime day) {
    final picked = calendarDay(day);
    if (picked == _form.day) return;
    _change(
      (form) => form.copyWith(day: picked, occurredAt: null, timeZone: null),
    );
    unawaited(_askForRateIfMissing(_form));
  }

  /// A time picked on this device's clock happened in this device's [zone].
  void chooseTime({
    required int hour,
    required int minute,
    required String zone,
  }) => _change((form) {
    final day = form.day;
    return form.copyWith(
      occurredAt: DateTime(day.year, day.month, day.day, hour, minute).toUtc(),
      timeZone: zone,
    );
  });

  void clearTime() =>
      _change((form) => form.copyWith(occurredAt: null, timeZone: null));

  void chooseSplitKind(SplitKind kind) =>
      _change((form) => form.copyWith(splitKind: kind));

  void setInSplit(String memberId, {required bool included}) => _change(
    (form) => form.copyWith(
      participants: included
          ? {...form.participants, memberId}
          : ({...form.participants}..remove(memberId)),
    ),
  );

  /// One more or one fewer share for [memberId], never below none.
  void nudgeShares(String memberId, int by) => _change(
    (form) => form.copyWith(
      shareCounts: {
        ...form.shareCounts,
        memberId: (form.shareCountOf(memberId) + by).clamp(0, 1 << 30),
      },
    ),
  );

  void setExactAmount(String memberId, String text) => _change(
    (form) => form.copyWith(
      exactAmounts: _override(form.exactAmounts, memberId, text),
    ),
  );

  void setPercent(String memberId, String text) => _change(
    (form) => form.copyWith(percents: _override(form.percents, memberId, text)),
  );

  /// Releases all overrides of the current amounts or percentage method.
  void resetSplit() => _change(
    (form) => switch (form.splitKind) {
      SplitKind.exact => form.copyWith(exactAmounts: {}),
      SplitKind.percent => form.copyWith(percents: {}),
      _ => form,
    },
  );

  Map<String, String> _override(
    Map<String, String> previous,
    String id,
    String text,
  ) => text.trim().isEmpty
      ? ({...previous}..remove(id))
      : {...previous, id: text};

  /// The one person who paid it all.
  void choosePayer(String memberId) =>
      _change((form) => form.copyWith(payers: {memberId}));

  void setPaying(String memberId, {required bool paying}) => _change(
    (form) => form.copyWith(
      payers: paying
          ? {...form.payers, memberId}
          : ({...form.payers}..remove(memberId)),
    ),
  );

  /// Back to one payer keeps the first of several.
  void setSeveralPayers(bool several) => _change(
    (form) => form.copyWith(
      severalPayers: several,
      payers: several ? form.payers : {?form.payers.firstOrNull},
    ),
  );

  void setPaidAmount(String memberId, String text) => _change(
    (form) =>
        form.copyWith(paidAmounts: _override(form.paidAmounts, memberId, text)),
  );

  /// Releases all manual payer amounts in this draft.
  void resetPaid() => _change((form) => form.copyWith(paidAmounts: {}));

  /// Saves the expense, and says whether it was saved. When it was not, the
  /// state says why.
  Future<bool> save() async {
    final ledger = ref.read(groupLedgerProvider(groupId));
    final form = _form;
    final currency = ref.read(currenciesProvider).value?[form.currencyCode];
    if (ledger == null || currency == null || form.saving) return false;
    state = AsyncData(form.copyWith(saving: true, error: null));
    try {
      final fx = await _quote(form, ledger.group.defaultCurrency);
      if (!ref.mounted) return false;
      final check = form.check(
        currency,
        groupId: groupId,
        fx: fx,
        deviceZone: ref.read(deviceZoneProvider).value,
      );
      final EntryDraft draft;
      switch (check) {
        case DraftIncomplete(:final reason):
          state = AsyncData(form.copyWith(error: reason));
          return false;
        case DraftReady(draft: final ready):
          draft = ready;
      }

      final repository = ref.read(entryRepositoryProvider);
      if (form.editing case final editing?) {
        // Who is editing, which need not be who created it: that difference
        // is most of what makes a feed line worth reading.
        await repository.update(
          editing.id,
          draft,
          actorId: ledger.me?.id,
          expected: editing,
        );
      } else {
        await repository.create(
          draft,
          id: form.newEntryId,
          createdBy: ledger.me?.id ?? draft.payerAmounts.keys.first,
        );
      }
      return true;
    } on SplitException catch (error) {
      // The domain refused it, so nothing was written. Its messages are
      // written for people, so they are shown as they are.
      _fail(error.message);
      return false;
    } catch (error) {
      _fail('$error');
      return false;
    }
  }

  /// Deletes the expense being edited, and says whether it was deleted.
  Future<bool> delete() async {
    final editing = _form.editing;
    if (editing == null || _form.saving) return false;
    state = AsyncData(_form.copyWith(saving: true, error: null));
    try {
      await ref
          .read(entryRepositoryProvider)
          .delete(
            editing.id,
            actorId: ref.read(groupLedgerProvider(groupId))?.me?.id,
            expected: editing,
          );
      return true;
    } catch (error) {
      _fail('$error');
      return false;
    }
  }

  void _fail(String reason) {
    if (ref.mounted) {
      state = AsyncData(_form.copyWith(saving: false, error: reason));
    }
  }

  /// The rate on the expense's own day, not today's.
  Future<FxQuote?> _quote(EntryFormState form, String target) async =>
      form.currencyCode == target
      ? null
      : ref
            .read(fxRepositoryProvider)
            .quote(base: form.currencyCode, quote: target, asOf: form.day);

  /// Nothing on this device prices this day, so the server is asked. The rate
  /// lands on a later sync, and the expense saves without one meanwhile.
  Future<void> _askForRateIfMissing(EntryFormState form) async {
    final target = ref
        .read(groupLedgerProvider(groupId))
        ?.group
        .defaultCurrency;
    if (target == null || form.currencyCode == target) return;
    if (await _quote(form, target) != null) return;
    if (!_ratesAsked.add('${calendarDate(form.day)}|${form.currencyCode}')) {
      return;
    }
    await ref
        .read(syncEngineProvider)
        ?.shared
        .requestBackfill(form.day, form.currencyCode);
  }
}
