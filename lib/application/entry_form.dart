/// The expense editor's state: what has been typed and chosen, and the one
/// way each of those changes.
library;

import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:opensplit_api/opensplit_api.dart' show SplitKind;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/local/database.dart';
import '../domain/calendar_date.dart';
import '../domain/category_guess.dart';
import '../domain/decimal_text.dart';
import '../domain/entry_draft.dart';
import '../domain/fx/fx_quote.dart';
import '../domain/models/entry.dart';
import '../domain/money_format.dart';
import '../domain/split/allocation.dart';
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

    /// Typed per person, for a split by amounts or percentages.
    @Default(<String, String>{}) Map<String, String> exactAmounts,
    @Default(<String, String>{}) Map<String, String> percents,
    @Default(<String>{}) Set<String> payers,
    @Default(false) bool severalPayers,

    /// Typed per payer, when several people paid.
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
          if (share.weightMicros case final weight?)
            share.memberId: (weight / weightScale).round(),
      },
      exactAmounts: {
        for (final share in entry.shares)
          share.memberId: typed(share.amountMinor),
      },
      percents: {
        for (final share in entry.shares)
          if (share.weightMicros case final weight?)
            share.memberId: formatPercentMicros(weight),
      },
      payers: {for (final payer in entry.payers) payer.memberId},
      severalPayers: entry.payers.length > 1,
      paidAmounts: {
        for (final payer in entry.payers)
          payer.memberId: typed(payer.amountMinor),
      },
    );
  }

  bool get isEditing => editing != null;

  /// The total in [currency], once what was typed reads as one.
  int? totalIn(Currency currency) {
    final total = currency.parseToMinor(amount);
    return total != null && total > 0 ? total : null;
  }

  int shareCountOf(String memberId) => shareCounts[memberId] ?? 1;

  /// What each person ends up owing, for splits that can be worked out before
  /// anything else is typed. Null for the rest, or until there is a total.
  Map<String, int>? preview(Currency currency) {
    final total = totalIn(currency);
    if (total == null || participants.isEmpty) return null;
    final spec = switch (splitKind) {
      SplitKind.equal => EqualSplit(participants.toList()),
      SplitKind.shares => SharesSplit({
        for (final id in participants) id: shareCountOf(id),
      }),
      _ => null,
    };
    if (spec == null) return null;
    try {
      return {
        for (final share in spec.resolve(total))
          share.memberId: share.amountMinor,
      };
    } on SplitException {
      return null;
    }
  }

  /// The expense this form describes in [groupId], or what is still missing
  /// from it.
  DraftCheck check(
    Currency currency, {
    required String groupId,
    FxQuote? fx,
    String? deviceZone,
  }) {
    final total = totalIn(currency);
    if (total == null) {
      return DraftIncomplete(
        currency.exponent == 0
            ? 'Enter a whole amount.'
            : 'Enter an amount with at most ${currency.exponent} decimal '
                  'places.',
      );
    }
    final split = _split(currency);
    if (split == null) {
      return const DraftIncomplete(
        'Check the split — some amounts are missing.',
      );
    }
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

    Map<String, int>? each(
      int? Function(String text) parse,
      Map<String, String> typed,
    ) {
      final values = <String, int>{};
      for (final id in ids) {
        final value = parse(typed[id] ?? '');
        if (value == null) return null;
        values[id] = value;
      }
      return values;
    }

    return switch (splitKind) {
      SplitKind.equal => EqualSplit(ids),
      SplitKind.shares => SharesSplit({
        for (final id in ids) id: shareCountOf(id),
      }),
      SplitKind.exact => switch (each(currency.parseToMinor, exactAmounts)) {
        final amounts? => ExactSplit(amounts),
        null => null,
      },
      SplitKind.percent => switch (each(parsePercentMicros, percents)) {
        final percents? => PercentSplit(percents),
        null => null,
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
    final amounts = <String, int>{};
    for (final id in payers) {
      final amount = currency.parseToMinor(paidAmounts[id] ?? '');
      if (amount == null || amount <= 0) return null;
      amounts[id] = amount;
    }
    return amounts.isEmpty ? null : amounts;
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
  Future<EntryFormState> build(String groupId, {String? entryId}) {
    final seeded = Completer<EntryFormState>();
    void seed() {
      if (seeded.isCompleted) return;
      final ledger = ref.read(groupLedgerProvider(groupId));
      final currencies = ref.read(currenciesProvider).value;
      if (ledger == null || currencies == null) return;

      if (entryId == null) {
        seeded.complete(EntryFormState.blank(ledger, now: DateTime.now()));
        return;
      }
      final entry = ledger.entries.where((e) => e.id == entryId).firstOrNull;
      if (entry != null) {
        seeded.complete(
          EntryFormState.of(entry, currencies[entry.row.currency]),
        );
      }
    }

    ref.listen(groupLedgerProvider(groupId), (_, _) => seed());
    ref.listen(currenciesProvider, (_, _) => seed());
    seed();
    return seeded.future.then((form) {
      unawaited(_askForRateIfMissing(form));
      return form;
    });
  }

  EntryFormState get _form => state.requireValue;

  void _change(EntryFormState Function(EntryFormState form) change) =>
      state = AsyncData(change(_form).copyWith(error: null));

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
    (form) =>
        form.copyWith(exactAmounts: {...form.exactAmounts, memberId: text}),
  );

  void setPercent(String memberId, String text) => _change(
    (form) => form.copyWith(percents: {...form.percents, memberId: text}),
  );

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
    (form) => form.copyWith(paidAmounts: {...form.paidAmounts, memberId: text}),
  );

  /// Saves the expense, and says whether it was saved. When it was not, the
  /// state says why.
  Future<bool> save() async {
    final ledger = ref.read(groupLedgerProvider(groupId));
    final form = _form;
    final currency = ref.read(currenciesProvider).value?[form.currencyCode];
    if (ledger == null || currency == null || form.saving) return false;

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

    state = AsyncData(form.copyWith(saving: true, error: null));
    final repository = ref.read(entryRepositoryProvider);
    try {
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
    if (editing == null) return false;
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
