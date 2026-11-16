import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/presentation/widgets/scroll_aware_fab.dart';

void main() {
  testWidgets('shrinks to its icon while the list is moving', (tester) async {
    final scrolling = ValueNotifier(false);
    addTearDown(scrolling.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ScrollAwareFab(
            scrolling: scrolling,
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

    scrolling.value = true;
    await tester.pumpAndSettle();

    expect(button().isExtended, isFalse);
    expect(find.byTooltip('Add expense'), findsOneWidget);

    scrolling.value = false;
    await tester.pumpAndSettle();

    expect(button().isExtended, isTrue);
  });
}
