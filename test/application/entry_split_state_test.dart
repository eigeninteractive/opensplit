import 'package:opensplit/application/entry_form.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/money_format.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit_api/opensplit_api.dart' show SplitKind;
import 'package:test/test.dart';

void main() {
  const inr = Currency(code: 'INR', exponent: 2, symbol: '₹', name: 'Rupee');
  const jpy = Currency(code: 'JPY', exponent: 0, symbol: '¥', name: 'Yen');
  const kwd = Currency(code: 'KWD', exponent: 3, name: 'Dinar');
  final day = DateTime.utc(2026, 10, 11);
  EntryFormState form({SplitKind kind = SplitKind.exact}) => EntryFormState(
    newEntryId: 'expense-rounding-seed',
    currencyCode: 'INR',
    amount: '300',
    day: day,
    participants: {'alex', 'sam', 'pat'},
    payers: {'alex'},
    splitKind: kind,
  );

  EntryDraft draft(EntryFormState state, [Currency currency = inr]) =>
      (state.check(currency, groupId: 'g1') as DraftReady).draft;

  test('new exact splits are ready without typing each share', () {
    final state = form();
    expect(state.exactAmounts, isEmpty);
    expect(state.preview(inr), {'alex': 10000, 'sam': 10000, 'pat': 10000});
    expect(draft(state).split, isA<ExactSplit>());
  });

  test('manual amounts stay fixed through total and selection changes', () {
    final state = form().copyWith(exactAmounts: {'alex': '120', 'sam': '80'});
    expect(state.preview(inr), {'alex': 12000, 'sam': 8000, 'pat': 10000});
    expect(state.copyWith(amount: '400').preview(inr), {
      'alex': 12000,
      'sam': 8000,
      'pat': 20000,
    });
    expect(state.copyWith(participants: {'alex', 'pat'}).preview(inr), {
      'alex': 12000,
      'pat': 18000,
    });
    expect(state.exactAmounts, {'alex': '120', 'sam': '80'});
  });

  test('percentages divide 100 and keep each manual percentage', () {
    expect(
      form(kind: SplitKind.percent).preview(inr)!.values,
      everyElement(10000),
    );
    final state = form(
      kind: SplitKind.percent,
    ).copyWith(percents: {'alex': '40'});
    expect(state.percentAllocation().values, {
      'alex': 40000000,
      'sam': 30000000,
      'pat': 30000000,
    });
    expect(state.preview(inr), {'alex': 12000, 'sam': 9000, 'pat': 9000});
    expect(state.copyWith(amount: '600').preview(inr), {
      'alex': 24000,
      'sam': 18000,
      'pat': 18000,
    });
    final precise = state.copyWith(percents: {'alex': '23,456789'});
    expect(precise.percentAllocation().values['alex'], 23456789);
    expect(draft(precise).split.resolve(30000), hasLength(3));
  });

  test('method drafts remain independent and shares remain ratios', () {
    final state = form().copyWith(
      exactAmounts: {'alex': '120'},
      percents: {'sam': '50'},
      shareCounts: {'pat': 2},
    );
    expect(state.copyWith(splitKind: SplitKind.percent).preview(inr), {
      'alex': 7500,
      'sam': 15000,
      'pat': 7500,
    });
    expect(state.copyWith(splitKind: SplitKind.shares).preview(inr), {
      'alex': 7500,
      'sam': 7500,
      'pat': 15000,
    });
    expect(state.copyWith(splitKind: SplitKind.equal).preview(inr), {
      'alex': 10000,
      'sam': 10000,
      'pat': 10000,
    });
    expect(state.preview(inr), {'alex': 12000, 'sam': 9000, 'pat': 9000});
  });

  test(
    'invalid and overallocated drafts never silently change manual values',
    () {
      for (final (overrides, expected) in [
        ({'alex': '.'}, contains('valid amount')),
        ({'alex': '400'}, contains('over the total')),
        (
          {'alex': '100', 'sam': '50', 'pat': '100'},
          contains('left to assign'),
        ),
      ]) {
        final state = form().copyWith(exactAmounts: overrides);
        expect(state.check(inr, groupId: 'g1'), isA<DraftIncomplete>());
        expect(state.splitError(inr), expected);
        expect(state.preview(inr), isNull);
        expect(state.exactAmounts, overrides);
      }
      final percent = form(
        kind: SplitKind.percent,
      ).copyWith(percents: {'alex': '101'});
      expect(percent.splitError(inr), contains('1% over 100%'));
      expect(percent.preview(inr), isNull);
    },
  );

  test(
    'zero shares are valid but selected payers must pay positive amounts',
    () {
      final state = form().copyWith(exactAmounts: {'alex': '0'});
      expect(draft(state).split.resolve(30000).first.amountMinor, 0);
      final paid = state.copyWith(
        severalPayers: true,
        payers: {'alex', 'sam'},
        paidAmounts: {'alex': '300'},
      );
      expect(paid.paidError(inr), contains('more than zero'));
      expect(paid.check(inr, groupId: 'g1'), isA<DraftIncomplete>());
      expect(
        paid.copyWith(paidAmounts: {'alex': '100'}).paidAllocation(inr)!.values,
        {'alex': 10000, 'sam': 20000},
      );
    },
  );

  test('currency precision is respected without converting manual inputs', () {
    for (final currency in [inr, jpy, kwd]) {
      final state = form().copyWith(
        currencyCode: currency.code,
        amount: '10',
        exactAmounts: {'alex': '4'},
      );
      expect(state.preview(currency), {
        'alex': 4 * currency.minorPerMajor,
        'sam': 3 * currency.minorPerMajor,
        'pat': 3 * currency.minorPerMajor,
      });
    }
    final precise = form().copyWith(exactAmounts: {'alex': '12.34'});
    expect(
      precise.copyWith(currencyCode: 'JPY').splitError(jpy),
      contains('valid amount'),
    );
    expect(precise.exactAmounts['alex'], '12.34');
  });

  for (final kind in [
    SplitKind.equal,
    SplitKind.exact,
    SplitKind.percent,
    SplitKind.shares,
  ]) {
    test('$kind preview and saved rounding agree for indivisible totals', () {
      final state = form(kind: kind).copyWith(amount: '0.05');
      final saved = composeEntry(
        draft(state),
        id: state.newEntryId!,
        createdBy: 'alex',
        now: day,
      );
      expect({
        for (final share in saved.shares) share.memberId: share.amountMinor,
      }, state.preview(inr));
      final reopened = EntryFormState.of(saved, inr);
      expect(reopened.preview(inr), state.preview(inr));
      if (kind == SplitKind.exact) expect(reopened.exactAmounts.length, 3);
      if (kind == SplitKind.percent) expect(reopened.percents.length, 3);
      final again = composeEntry(
        draft(reopened),
        id: saved.id,
        createdBy: 'alex',
        now: day,
      );
      expect(again.shares, saved.shares);
    });
  }

  test(
    'reopened amount splits and payer amounts stay fixed until released',
    () {
      final state = form().copyWith(
        exactAmounts: {'alex': '120', 'sam': '80'},
        severalPayers: true,
        payers: {'alex', 'sam'},
        paidAmounts: {'alex': '200'},
      );
      final saved = composeEntry(
        draft(state),
        id: state.newEntryId!,
        createdBy: 'alex',
        now: day,
      );
      final reopened = EntryFormState.of(saved, inr);
      expect(reopened.exactAllocation(inr)!.automatic, isEmpty);
      expect(reopened.paidAllocation(inr)!.automatic, isEmpty);
      final changed = reopened.copyWith(amount: '350');
      expect(changed.splitError(inr), contains('50.00 left to assign'));
      expect(changed.paidError(inr), contains('50.00 left to assign'));
      expect(changed.exactAmounts, reopened.exactAmounts);
      expect(
        changed
            .copyWith(exactAmounts: {'alex': '120', 'sam': '80'})
            .preview(inr)!
            .values,
        contains(15000),
      );
    },
  );

  test(
    'switching an existing equal split does not import weights as percentages',
    () {
      final state = form(kind: SplitKind.equal);
      final saved = composeEntry(
        draft(state),
        id: 'existing',
        createdBy: 'alex',
        now: day,
      );
      final reopened = EntryFormState.of(saved, inr);
      expect(reopened.exactAmounts, isEmpty);
      expect(reopened.percents, isEmpty);
      expect(reopened.paidAmounts, isEmpty);
      expect(
        reopened.copyWith(splitKind: SplitKind.percent).splitError(inr),
        isNull,
      );
    },
  );
}
