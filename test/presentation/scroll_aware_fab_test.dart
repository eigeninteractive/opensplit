import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/presentation/widgets/scroll_aware_fab.dart';

void main() {
  testWidgets('animates the width in both directions and keeps one action', (
    tester,
  ) async {
    final extended = ValueNotifier(true);
    addTearDown(extended.dispose);
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ScrollAwareFab(
            extended: extended,
            onPressed: () => presses++,
            icon: Icons.add,
            label: 'Add expense',
          ),
        ),
      ),
    );
    final button = find.byType(FloatingActionButton);
    Rect bounds() => tester.getRect(button);

    expect(find.text('Add expense'), findsOneWidget);
    final expanded = bounds();

    extended.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final collapsing = bounds();
    await tester.pumpAndSettle();
    final collapsed = bounds();
    expect(collapsing.width, lessThan(expanded.width));
    expect(collapsing.width, greaterThan(collapsed.width));
    expect(collapsing.right, closeTo(expanded.right, 0.01));
    expect(collapsed.width, collapsed.height);
    expect(tester.getCenter(find.byIcon(Icons.add)), collapsed.center);
    expect(find.byTooltip('Add expense'), findsOneWidget);
    await tester.tap(button);
    expect(presses, 1);

    extended.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final expanding = bounds();
    expect(expanding.width, greaterThan(collapsed.width));
    expect(expanding.width, lessThan(expanded.width));
    await tester.pumpAndSettle();
    expect(bounds(), expanded);
  });
}
