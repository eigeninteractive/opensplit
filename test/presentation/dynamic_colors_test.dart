import 'dart:typed_data';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/preferences_providers.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/dynamic_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
    () => messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, null),
  );

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final result = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(result.dispose);
    return result;
  }

  test('unavailable platform colours leave the brand theme usable', () async {
    messenger.setMockMethodCallHandler(
      DynamicColorPlugin.channel,
      (_) async => null,
    );
    final scope = await container();
    expect(await scope.read(wallpaperSchemesProvider.future), isNull);
    expect(scope.read(activeWallpaperSchemesProvider), isNull);
  });

  test('the native Android palette reaches both active themes', () async {
    // Android supplies five palettes of thirteen tones, not a seed colour.
    // Distinct tones let this catch accidentally reseeding the native palette.
    final tones = [0, 26, 51, 77, 102, 128, 153, 179, 204, 230, 242, 252, 255];
    final colours = [
      for (var palette = 0; palette < 5; palette++)
        for (final tone in tones) 0xFF000000 | tone << 16 | tone << 8 | tone,
    ];
    final calls = <String>[];
    messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, (
      call,
    ) async {
      calls.add(call.method);
      // Kotlin returns an IntArray, encoded as Int32List by the channel.
      return Int32List.fromList(colours);
    });
    final scope = await container();
    final schemes = await scope.read(wallpaperSchemesProvider.future);
    expect(schemes?.light.primary, Color(colours[4]));
    expect(schemes?.dark.primary, Color(colours[8]));
    expect(scope.read(activeWallpaperSchemesProvider), schemes);
    expect(calls, ['getCorePalette']);
  });

  test('a palette failure still permits a supported system accent', () async {
    messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, (
      call,
    ) async {
      if (call.method == 'getCorePalette') {
        throw PlatformException(code: 'unavailable');
      }
      return 0xFF006B5F;
    });
    final scope = await container();
    final schemes = await scope.read(wallpaperSchemesProvider.future);
    expect(schemes?.light.brightness, Brightness.light);
    expect(schemes?.dark.brightness, Brightness.dark);
    expect(
      schemes?.light.primary,
      ColorScheme.fromSeed(seedColor: const Color(0xFF006B5F)).primary,
    );
  });

  test('turning off wallpaper colours survives a relaunch', () async {
    messenger.setMockMethodCallHandler(
      DynamicColorPlugin.channel,
      (call) async => call.method == 'getCorePalette' ? null : 0xFF006B5F,
    );
    final first = await container();
    await first.read(wallpaperSchemesProvider.future);
    await first.read(wallpaperColorsProvider.notifier).set(enabled: false);
    expect(first.read(activeWallpaperSchemesProvider), isNull);

    final second = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          first.read(sharedPreferencesProvider),
        ),
      ],
    );
    addTearDown(second.dispose);
    expect(second.read(wallpaperColorsProvider), isFalse);
    await second.read(wallpaperColorsProvider.notifier).set(enabled: true);
    await second.read(wallpaperSchemesProvider.future);
    expect(second.read(activeWallpaperSchemesProvider), isNotNull);
  });

  testWidgets('returning from device settings refreshes the active palette', (
    tester,
  ) async {
    var accent = 0xFF006B5F;
    messenger.setMockMethodCallHandler(
      DynamicColorPlugin.channel,
      (call) async => call.method == 'getCorePalette' ? null : accent,
    );
    final db = await testDatabase();
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    Future<void> settle() async {
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await settle();
    Color active() => Theme.of(
      tester.element(find.byType(Scaffold).first),
    ).colorScheme.primary;
    final before = active();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    accent = 0xFFB04030;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle();
    expect(active(), isNot(before));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
