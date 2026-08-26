import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/platform/review_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  var asked = 0;
  var now = DateTime.utc(2026, 8, 26);

  ReviewPrompt build({bool available = true}) => ReviewPrompt(
    prefs,
    isAvailable: () async => available,
    request: () async => asked++,
    clock: () => now,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    asked = 0;
    now = DateTime.utc(2026, 8, 26);
  });

  test('asks the first time', () async {
    expect(await build().isDue(), isTrue);
  });

  test('does not ask when the platform has nothing to show', () async {
    expect(await build(available: false).isDue(), isFalse);
  });

  // Play's quota is enforced silently: over it, requestReview resolves
  // normally and shows nothing at all. Asking again inside the window would
  // therefore spend the one prompt this person gets on a sheet nobody sees,
  // and there is no way to find out that happened.
  test('does not ask again straight away', () async {
    final prompt = build();
    await prompt.ask();
    expect(await prompt.isDue(), isFalse);

    now = now.add(const Duration(days: 119));
    expect(await prompt.isDue(), isFalse);

    now = now.add(const Duration(days: 2));
    expect(await prompt.isDue(), isTrue);
  });

  test('records the attempt even when the request throws', () async {
    final prompt = ReviewPrompt(
      prefs,
      isAvailable: () async => true,
      request: () async => throw StateError('no store'),
      clock: () => now,
    );

    // Swallowed: a review sheet that could not be shown is not the user's
    // problem, and re-asking on their next settle-up would be.
    await prompt.ask();
    expect(
      await prompt.isDue(),
      isFalse,
      reason:
          'a failed attempt still counts, or a broken store means every '
          'settle-up asks again',
    );
  });

  test('the ask goes through to the platform', () async {
    await build().ask();
    expect(asked, 1);
  });
}
