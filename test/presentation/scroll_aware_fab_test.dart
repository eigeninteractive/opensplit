import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/presentation/widgets/scroll_aware_fab.dart';

void main() {
  testWidgets('shrinks to its icon when told to and restores its label', (
    tester,
  ) async {
    final extended = ValueNotifier(true);
    addTearDown(extended.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ScrollAwareFab(
            extended: extended,
            onPressed: () {},
            icon: Icons.add,
            label: 'Add expense',
          ),
        ),
      ),
    );
    FloatingActionButton button() =>
        tester.widget(find.byType(FloatingActionButton));

    expect(button().isExtended, isTrue);
    expect(find.text('Add expense'), findsOneWidget);

    extended.value = false;
    await tester.pumpAndSettle();

    expect(button().isExtended, isFalse);
    expect(find.byTooltip('Add expense'), findsOneWidget);

    extended.value = true;
    await tester.pumpAndSettle();

    expect(button().isExtended, isTrue);
  });
}
