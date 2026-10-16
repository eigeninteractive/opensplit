import 'dart:math' as math;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/ledger_providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/theme.dart';
import 'package:opensplit/presentation/widgets/group_cover.dart';
import 'package:opensplit_api/opensplit_api.dart' show AvatarKind, CoverKind;

import '../fixtures/android_wallpaper.dart';

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + .05) / (math.min(first, second) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, null),
  );

  for (final wallpaper in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'group text over artwork: $brightness / wallpaper $wallpaper',
        (tester) async {
          messenger.setMockMethodCallHandler(
            DynamicColorPlugin.channel,
            (_) async => tealAndroidWallpaper(),
          );
          final palette = await DynamicColorPlugin.getCorePalette();
          final theme = buildTheme(
            brightness,
            wallpaper ? palette!.toColorScheme(brightness: brightness) : null,
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                categoriesProvider.overrideWith((ref) => Stream.value([])),
              ],
              child: MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: SizedBox(
                    height: 160,
                    child: GroupCover(ledger: _ledger, patternFade: 1),
                  ),
                ),
              ),
            ),
          );
          final cover = find.byType(GroupCover);
          final surface = tester
              .widget<ColoredBox>(
                find.descendant(of: cover, matching: find.byType(ColoredBox)),
              )
              .color;
          final opacity = tester
              .widget<Opacity>(
                find.descendant(of: cover, matching: find.byType(Opacity)),
              )
              .opacity;
          final colors = theme.extension<BalanceColors>()!;
          // Black/white bound every motif colour, including multicolour emoji.
          // Text can wrap across any part of the artwork at large font sizes.
          for (final motif in [Colors.black, Colors.white]) {
            final background = Color.alphaBlend(
              motif.withValues(alpha: opacity),
              surface,
            );
            for (final text in [
              theme.colorScheme.onSurface,
              theme.colorScheme.onSurfaceVariant,
              colors.credit,
              colors.debit,
            ]) {
              expect(_contrast(text, background), greaterThanOrEqualTo(4.5));
            }
          }
          expect(
            _contrast(surface, theme.colorScheme.surface),
            greaterThan(1.1),
          );
        },
      );
    }
  }
}

final _ledger = GroupLedger(
  group: Group(
    id: 'group',
    name: 'Trip',
    defaultCurrency: 'INR',
    createdAt: DateTime.utc(2026),
    avatarKind: AvatarKind.initials,
    coverKind: CoverKind.generated,
    isDirect: false,
    simplifyDebts: true,
  ),
  members: const [],
  pastMembers: const [],
  entries: const [],
  balances: const [],
  transfers: const [],
  me: null,
  profiles: const {},
  brokenEntries: const [],
);
