import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/presentation/theme.dart';
import 'package:opensplit/presentation/widgets/balance_arrow.dart';

Future<void> _pump(WidgetTester tester, Widget child, {Brightness? mode}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(mode ?? Brightness.light),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('BalanceArrow', () {
    testWidgets('points up when you are owed', (tester) async {
      await _pump(tester, const BalanceArrow(balanceMinor: 5000));
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });

    testWidgets('points down when you owe', (tester) async {
      await _pump(tester, const BalanceArrow(balanceMinor: -5000));
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });

    testWidgets('is absent when settled', (tester) async {
      // An arrow beside a zero would be claiming a direction that does not
      // exist.
      await _pump(tester, const BalanceArrow(balanceMinor: 0));
      expect(find.byType(Icon), findsNothing);
    });

    // One test per brightness rather than a loop: MaterialApp animates between
    // themes, so re-pumping the same tree with a new one leaves the colour
    // mid-transition and the second assertion reads a blend of the two.
    for (final brightness in Brightness.values) {
      testWidgets('takes its colour from the $brightness theme', (
        tester,
      ) async {
        await _pump(
          tester,
          const BalanceArrow(balanceMinor: 5000),
          mode: brightness,
        );
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(
          icon.color,
          buildTheme(brightness).extension<BalanceColors>()!.credit,
        );
      });
    }
  });

  group('BalanceAmount', () {
    testWidgets('reads out the direction in words for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const BalanceAmount(
          balanceMinor: -5000,
          text: '₹50.00',
          semanticsLabel: 'you owe ₹50.00',
        ),
      );

      // The rendered string is the amount; what is announced says which way it
      // goes, because neither the colour nor the arrow reaches a screen reader.
      expect(find.text('₹50.00'), findsOneWidget);
      expect(find.bySemanticsLabel('you owe ₹50.00'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('shows an arrow beside the amount', (tester) async {
      await _pump(
        tester,
        const BalanceAmount(
          balanceMinor: 5000,
          text: '₹50.00',
          semanticsLabel: 'you are owed ₹50.00',
        ),
      );
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.text('₹50.00'), findsOneWidget);
    });

    testWidgets('a settled amount gets neither arrow nor colour', (
      tester,
    ) async {
      await _pump(
        tester,
        const BalanceAmount(
          balanceMinor: 0,
          text: '₹0.00',
          semanticsLabel: 'settled up',
        ),
      );
      expect(find.byType(Icon), findsNothing);
      final text = tester.widget<Text>(find.text('₹0.00'));
      expect(
        text.style?.color,
        buildTheme(Brightness.light).colorScheme.onSurfaceVariant,
      );
    });
  });
}
