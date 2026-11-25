import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/presentation/widgets/google_sign_in_button.dart';

void main() {
  for (final (brightness, variant, fill, foreground) in [
    (Brightness.light, 'light', Colors.white, const Color(0xFF1F1F1F)),
    (Brightness.dark, 'dark', const Color(0xFF131314), const Color(0xFFE3E3E3)),
  ]) {
    testWidgets('uses the Google artwork for $variant at large text sizes', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SizedBox(
                  width: 240,
                  child: GoogleSignInButton(onPressed: () => presses++),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/google_sign_in/google-sign-in-$variant.png',
      );
      expect(tester.getSize(find.byType(Image)), const Size(20, 20));
      final button = find.widgetWithText(
        OutlinedButton,
        'Continue with Google',
      );
      final style = tester.widget<OutlinedButton>(button).style!;
      expect(style.backgroundColor!.resolve({}), fill);
      expect(style.foregroundColor!.resolve({}), foreground);
      await tester.tap(button);
      expect(presses, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
