import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/application/ledger_providers.dart';
import 'package:opensplit/presentation/theme.dart';
import 'package:opensplit/presentation/widgets/amount_card.dart';

void main() {
  const rupee = Currency(
    code: 'INR',
    name: 'Indian Rupee',
    symbol: '₹',
    exponent: 2,
  );
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('empty amount is discoverable at $brightness / $scale text', (
        tester,
      ) async {
        GoogleFonts.config.allowRuntimeFetching = false;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var value = '';
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currenciesProvider.overrideWith(
                (ref) => Stream.value({'INR': rupee}),
              ),
            ],
            child: MaterialApp(
              theme: buildTheme(brightness),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AmountCard(
                        currency: rupee,
                        currencyCode: 'INR',
                        amount: value,
                        onAmountChanged: (text) => value = text,
                        onCurrencyChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isFalse,
        );
        expect(value, isEmpty, reason: 'the placeholder must not prefill zero');
        expect(find.text('Amount'), findsOneWidget);
        expect(find.text('0.00'), findsOneWidget);
        expect(tester.getSize(find.text('0.00')).height, greaterThan(0));
        await tester.tapAt(tester.getCenter(find.text('0.00')));
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
          reason: 'tapping the visible placeholder focuses the input',
        );
        await tester.enterText(find.byType(TextFormField), '12.50');
        await tester.pump();
        expect(value, '12.50');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
