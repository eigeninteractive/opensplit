import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/domain/activity/activity_text.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:test/test.dart';

void main() {
  const rupee = Currency(code: 'INR', exponent: 2, symbol: '₹', name: 'Rupee');
  const yen = Currency(code: 'JPY', exponent: 0, symbol: '¥', name: 'Yen');

  group('describeChange', () {
    test('renders an amount in what the group actually said out loud', () {
      final line = describeChange(
        const FieldChange(field: 'amount_minor', from: '40000', to: '30000'),
        currency: rupee,
      );

      // The whole reason this function exists.
      expect(line, 'Amount changed from ₹400.00 to ₹300.00');
    });

    test('respects a currency with no minor unit', () {
      final line = describeChange(
        const FieldChange(field: 'amount_minor', from: '4000', to: '3000'),
        currency: yen,
      );
      expect(line, 'Amount changed from ¥4,000 to ¥3,000');
    });

    test('pads the fractional part rather than dropping a leading zero', () {
      final line = describeChange(
        const FieldChange(field: 'amount_minor', from: '105', to: '100'),
        currency: rupee,
      );
      // 105 minor units is ₹1.05, not ₹1.5.
      expect(line, 'Amount changed from ₹1.05 to ₹1.00');
    });

    test('says how a split changed in words, not enum names', () {
      final line = describeChange(
        const FieldChange(field: 'split_kind', from: 'equal', to: 'shares'),
      );
      expect(line, 'Split changed from equal to shares');
    });

    test('reports a cleared field as cleared, not as empty', () {
      final line = describeChange(
        const FieldChange(field: 'notes', from: 'split with Ravi', to: null),
      );
      expect(line, 'Notes cleared');
    });

    test('reports a field being set for the first time', () {
      final line = describeChange(
        const FieldChange(field: 'notes', from: null, to: 'paid in cash'),
      );
      expect(line, 'Notes set to paid in cash');
    });

    test('renders a field it has never heard of instead of hiding it', () {
      // A column added to the server's diff later must show up as a clumsy
      // line rather than silently vanishing from the record.
      final line = describeChange(
        const FieldChange(field: 'receipt_url', from: 'a', to: 'b'),
      );
      expect(line, 'Receipt url changed from a to b');
    });

    test('falls back to the raw amount when the currency is unknown', () {
      final line = describeChange(
        const FieldChange(field: 'amount_minor', from: '40000', to: '30000'),
      );
      expect(line, 'Amount changed from 40000 to 30000');
    });

    // The lines the whole redesign exists to make possible.
    test('names whose share moved, and by how much', () {
      final line = describeChange(
        const FieldChange(field: 'share:m1', from: '20000', to: '30000'),
        currency: rupee,
        memberNames: const {'m1': 'Ravi'},
      );
      expect(line, "Ravi's share changed from ₹200.00 to ₹300.00");
    });

    test('reads somebody joining a split as a share being set', () {
      final line = describeChange(
        const FieldChange(field: 'share:m2', from: null, to: '20000'),
        currency: rupee,
        memberNames: const {'m2': 'Priya'},
      );
      expect(line, "Priya's share set to ₹200.00");
    });

    test('says who put the money down when that changes', () {
      final line = describeChange(
        const FieldChange(field: 'paid:m1', from: '40000', to: null),
        currency: rupee,
        memberNames: const {'m1': 'Ravi'},
      );
      expect(line, 'Amount Ravi paid cleared');
    });

    test('still says something useful with no names to hand', () {
      // Never silently absent: these are the lines that say who gained and
      // who lost, so a missing name costs elegance and not the record.
      final line = describeChange(
        const FieldChange(field: 'share:m1', from: '20000', to: '30000'),
        currency: rupee,
      );
      expect(line, "Someone's share changed from ₹200.00 to ₹300.00");
    });

    test('names the category it moved between', () {
      final line = describeChange(
        const FieldChange(field: 'category_id', from: 'c1', to: 'c2'),
        categoryNames: const {'c1': 'Fuel & parking', 'c2': 'Taxi'},
      );
      expect(line, 'Category changed from Fuel & parking to Taxi');
    });

    test('says a category changed even without the names to hand', () {
      final line = describeChange(
        const FieldChange(field: 'category_id', from: 'c1', to: 'c2'),
      );
      expect(line, 'Category changed');
    });

    test('writes a date the way a person would', () {
      final line = describeChange(
        const FieldChange(
          field: 'entry_date',
          from: '2026-11-08',
          to: '2026-10-24',
        ),
      );
      expect(line, 'Date changed from Nov 8, 2026 to Oct 24, 2026');
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

    test('names what it is about instead of saying "this"', () {
      expect(describeKind(EntryEventKind.created), 'added this expense');
      expect(
        describeKind(EntryEventKind.created, isPayment: true),
        'recorded this payment',
      );
    });
  });

  group('describeEntryEvent', () {
    api.EntrySnapshot snapshot({
      api.EntryKind kind = api.EntryKind.expense,
      String description = 'Fuel',
    }) => api.EntrySnapshot(
      kind: kind,
      description: description,
      currency: 'INR',
      amountMinor: 80000,
      entryDate: '2026-10-24',
      splitKind: api.SplitKind.equal,
      categoryId: null,
      notes: null,
      deletedAt: null,
      payers: [api.MoneyRow(memberId: 'm1', amountMinor: 80000)],
      shares: [api.MoneyRow(memberId: 'm2', amountMinor: 80000)],
    );
    const names = {'m1': 'Brinda', 'm2': 'Seenu'};

    test('quotes the expense by its description', () {
      expect(
        describeEntryEvent(
          actor: 'Seenu',
          kind: EntryEventKind.edited,
          snapshot: snapshot(),
        ),
        'Seenu edited “Fuel”',
      );
    });

    test('never reads "added this an expense"', () {
      expect(
        describeEntryEvent(
          actor: 'Seenu',
          kind: EntryEventKind.created,
          snapshot: snapshot(description: ''),
        ),
        'Seenu added an expense',
      );
    });

    test('says who paid whom for a payment', () {
      expect(
        describeEntryEvent(
          actor: 'Seenu',
          kind: EntryEventKind.created,
          snapshot: snapshot(kind: api.EntryKind.settlement, description: ''),
          memberNames: names,
        ),
        'Seenu recorded a payment from Brinda to Seenu',
      );
    });

    test('summarises what an expense came to and who paid', () {
      expect(
        describeEntrySummary(snapshot(), currency: rupee, memberNames: names),
        '₹800.00 · paid by Brinda',
      );
    });
  });
}
