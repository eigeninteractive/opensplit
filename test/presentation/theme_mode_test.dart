import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/presentation/theme_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  Future<ProviderContainer> container() async {
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('follows the platform until told otherwise', () async {
    final c = await container();
    expect(c.read(themeModeProvider), ThemeMode.system);
  });

  test('remembers a choice across a restart', () async {
    final first = await container();
    await first.read(themeModeProvider.notifier).set(ThemeMode.dark);
    expect(first.read(themeModeProvider), ThemeMode.dark);

    // A second container reads the same preferences from scratch, which is
    // what a relaunch does.
    final second = await container();
    expect(second.read(themeModeProvider), ThemeMode.dark);
  });

  test(
    'returns to system by forgetting, not by storing a third value',
    () async {
      final c = await container();
      final notifier = c.read(themeModeProvider.notifier);

      await notifier.set(ThemeMode.light);
      await notifier.set(ThemeMode.system);

      expect(c.read(themeModeProvider), ThemeMode.system);
      // The distinction matters: a stored "system" and a fresh install would be
      // two states meaning the same thing, and only one of them would survive a
      // later change to what the default is.
      expect(
        prefs.getString('theme_mode'),
        isNull,
        reason: 'returning to system should clear the key, not write it',
      );
    },
  );

  test('ignores a stored value it does not recognise', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
    prefs = await SharedPreferences.getInstance();

    final c = await container();
    expect(c.read(themeModeProvider), ThemeMode.system);
  });
}
