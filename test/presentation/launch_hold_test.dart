import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/presentation/launch_hold.dart';

void main() {
  tearDown(LaunchHold.reset);

  testWidgets('holds the first frame until saved data replaces placeholders', (
    tester,
  ) async {
    final loaded = ValueNotifier(false);
    addTearDown(loaded.dispose);

    LaunchHold.begin(limit: const Duration(seconds: 5));
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: loaded,
        builder: (context, isLoaded, _) => isLoaded
            ? const Text('Saved home group', textDirection: TextDirection.ltr)
            : const LaunchPlaceholder(child: SizedBox()),
      ),
    );
    await tester.pump();
    expect(LaunchHold.isHolding, isTrue);

    loaded.value = true;
    await tester.pump();
    await tester.pump();
    expect(LaunchHold.isHolding, isFalse);
  });

  testWidgets('releases a screen with nothing to wait for', (tester) async {
    LaunchHold.begin(limit: const Duration(seconds: 5));
    await tester.pumpWidget(
      const Text('Welcome', textDirection: TextDirection.ltr),
    );
    await tester.pump();
    expect(LaunchHold.isHolding, isFalse);
  });

  testWidgets('gives up at the limit rather than holding the splash', (
    tester,
  ) async {
    LaunchHold.begin(limit: const Duration(milliseconds: 800));
    await tester.pumpWidget(const LaunchPlaceholder(child: SizedBox()));
    await tester.pump(const Duration(milliseconds: 799));
    expect(LaunchHold.isHolding, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(LaunchHold.isHolding, isFalse);
  });
}
