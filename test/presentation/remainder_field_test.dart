import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/presentation/amount_input.dart';
import 'package:opensplit/presentation/widgets/remainder_field.dart';

void main() {
  testWidgets('derived updates do not interrupt text, caret or composition', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? manual;
    var automatic = '100.00';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Column(
                children: [
                  RemainderField(
                    label: 'Amount',
                    memberName: 'Alex',
                    manualText: manual,
                    automaticText: automatic,
                    inputFormatters: [DecimalInputFormatter.amount(null)],
                    onChanged: (text) =>
                        update(() => manual = text.isEmpty ? null : text),
                  ),
                  const TextField(key: ValueKey('other')),
                ],
              );
            },
          ),
        ),
      ),
    );
    final field = find.descendant(
      of: find.byType(RemainderField),
      matching: find.byType(TextField),
    );
    TextEditingController text() => tester.widget<TextField>(field).controller!;
    expect(text().text, '100.00');
    expect(
      tester.getSemantics(field).hint,
      'Shares the remainder when other values change.',
    );
    await tester.tap(field);
    await tester.pump();
    expect(manual, isNull, reason: 'focus alone does not make a value manual');
    update(() => automatic = '90.00');
    await tester.pump();
    expect(text().text, '90.00');
    await tester.enterText(field, '12,');
    text().value = text().value.copyWith(
      selection: const TextSelection.collapsed(offset: 1),
      composing: const TextRange(start: 0, end: 2),
    );
    final typed = text().value;
    update(() => automatic = '140.00');
    await tester.pump();
    expect(text().value, typed);
    expect(manual, '12,');
    expect(
      tester.getSemantics(field).hint,
      'Custom value. Stays fixed when other values change.',
    );
    await tester.enterText(field, '');
    await tester.pump();
    expect(manual, isNull);
    expect(text().text, '', reason: 'the empty field is still being edited');
    expect(find.text('Auto'), findsNothing);
    expect(find.text('Manual'), findsNothing);
    expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
    update(() => automatic = '150.00');
    await tester.pump();
    expect(text().text, '');
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(text().text, '150.00');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('individual and section resets update a focused field', (
    tester,
  ) async {
    String? manual = '120';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return RemainderField(
                label: 'Amount',
                memberName: 'Alex',
                manualText: manual,
                automaticText: '100.00',
                inputFormatters: [DecimalInputFormatter.amount(null)],
                onChanged: (text) =>
                    update(() => manual = text.isEmpty ? null : text),
              );
            },
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    await tester.enterText(field, '150');
    await tester.pump();
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    await tester.tap(find.byTooltip("Let Alex's value adjust"));
    await tester.pump();
    expect(manual, isNull);
    expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, '100.00');
    await tester.enterText(field, '175');
    await tester.pump();
    update(() => manual = null);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '100.00');
    expect(tester.takeException(), isNull);
  });
}
