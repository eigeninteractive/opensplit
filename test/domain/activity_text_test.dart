import 'package:test/test.dart';
import 'package:opensplit/domain/activity/activity_text.dart';
import 'package:opensplit/domain/models/currency.dart';
import 'package:opensplit/domain/models/entry_event.dart';

void main() {
  const rupee = Currency(code: 'INR', exponent: 2, symbol: '₹', name: 'Rupee');
  const yen = Currency(code: 'JPY', exponent: 0, symbol: '¥', name: 'Yen');

  group('describeChange', () {
    test('renders an amount in what the group actually said out loud', () {
      final line = describeChange(
        const FieldChange(field: 'amount_minor', from: '40000', to: '30000'),
        currency: rupee,
      );

      // The whole reason this function exists. The column holds minor units,
      // so an unrendered diff says "from 40000 to 30000" for what everybody
      // involved remembers as ₹400 and ₹300.
      expect(line, 'the amount, from ₹400.00 to ₹300.00');
    });

    test('respects a currency with no minor unit', () {
      final line = describeChange(
        const FieldChange(field: 'amount_minor', from: '4000', to: '3000'),
        currency: yen,
      );
      expect(line, 'the amount, from ¥4000 to ¥3000');
    });

    test('pads the fractional part rather than dropping a leading zero', () {
      final line = describeChange(
        const FieldChange(field: 'amount_minor', from: '105', to: '100'),
        currency: rupee,
      );
      // 105 minor units is ₹1.05, not ₹1.5.
      expect(line, 'the amount, from ₹1.05 to ₹1.00');
    });

    test('says how a split changed in words, not enum names', () {
      final line = describeChange(
        const FieldChange(field: 'split_kind', from: 'equal', to: 'shares'),
      );
      expect(line, 'how it splits, from equally to by shares');
    });

    test('reports a cleared field as cleared, not as empty', () {
      final line = describeChange(
        const FieldChange(field: 'notes', from: 'split with Ravi', to: null),
      );
      expect(line, 'the notes, cleared');
    });

    test('reports a field being set for the first time', () {
      final line = describeChange(
        const FieldChange(field: 'notes', from: null, to: 'paid in cash'),
      );
      expect(line, 'the notes, set to paid in cash');
    });

    test('renders a field it has never heard of instead of hiding it', () {
      // A column added to the server's diff later must show up as a clumsy
      // line rather than silently vanishing from the record.
      final line = describeChange(
        const FieldChange(field: 'receipt_url', from: 'a', to: 'b'),
      );
      expect(line, 'receipt url, from a to b');
    });

    test('falls back to the raw amount when the currency is unknown', () {
      final line = describeChange(
        const FieldChange(field: 'amount_minor', from: '40000', to: '30000'),
      );
      expect(line, 'the amount, from 40000 to 30000');
    });

    // The lines the whole redesign exists to make possible. A bill re-split
    // without its total moving changes no number a reader would think to
    // check, so this sentence is the only place the money shows up.
    test('names whose share moved, and by how much', () {
      final line = describeChange(
        const FieldChange(field: 'share:m1', from: '20000', to: '30000'),
        currency: rupee,
        memberNames: const {'m1': 'Ravi'},
      );
      expect(line, "Ravi's share, from ₹200.00 to ₹300.00");
    });

    test('reads somebody joining a split as a share being set', () {
      final line = describeChange(
        const FieldChange(field: 'share:m2', from: null, to: '20000'),
        currency: rupee,
        memberNames: const {'m2': 'Priya'},
      );
      expect(line, "Priya's share, set to ₹200.00");
    });

    test('says who put the money down when that changes', () {
      final line = describeChange(
        const FieldChange(field: 'paid:m1', from: '40000', to: null),
        currency: rupee,
        memberNames: const {'m1': 'Ravi'},
      );
      expect(line, 'what Ravi paid, cleared');
    });

    test('still says something useful with no names to hand', () {
      // Never silently absent: these are the lines that say who gained and
      // who lost, so a missing name costs elegance and not the record.
      final line = describeChange(
        const FieldChange(field: 'share:m1', from: '20000', to: '30000'),
        currency: rupee,
      );
      expect(line, "someone's share, from ₹200.00 to ₹300.00");
    });
  });

  group('describeKind', () {
    test('has a sentence for every kind', () {
      // Exhaustive by construction: a new kind added to the enum without a
      // sentence here fails to compile in describeKind's switch.
      for (final kind in EntryEventKind.values) {
        expect(describeKind(kind), isNotEmpty);
      }
    });
  });
}
