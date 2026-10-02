// Renders the screenshots the landing page and the Play listing use, from the
// real screens over demo data:
//
//     flutter test tool/screenshots_test.dart
//
// A widget test rather than a device capture, so anyone can rerun it after a
// UI change and get the same five screens back, with no emulator and no
// account. It sits in tool/ rather than test/ so that `flutter test` does not
// rewrite committed images on every run.
//
// The data goes in through the app's own repositories, so every figure on the
// screens is one the app computed. Dates are relative to today, which is the
// only thing that changes between two runs.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/router_provider.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/harness.dart';

/// Where the images go: served by the site, uploaded to Play by hand.
const _output = 'site/store';

/// A 1080 × 1920 phone, the size Play asks for, at a common Android density.
const _phone = (size: Size(1080, 1920), pixelRatio: 2.625);

/// A laptop-sized browser window, wide enough for the side-by-side layout.
const _desktop = (size: Size(2560, 1600), pixelRatio: 2.0);

void main() {
  testWidgets('screenshots', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // A tap that misses would otherwise only warn, and the picture would
    // quietly show the screen without whatever it was meant to set.
    WidgetController.hitTestWarningShouldBeFatal = true;
    await tester.runAsync(_loadFonts);

    // flutter_test draws every shadow as a solid black outline unless told
    // otherwise, which is right for a golden and wrong for a picture.
    debugDisableShadows = false;
    addTearDown(tester.view.reset);

    final db = (await tester.runAsync(testDatabase))!;
    final trip = (await tester.runAsync(() => _seed(db)))!;

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;

    _resize(tester, _phone);
    final frame = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: frame,
        child: signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
      ),
    );
    final router = ProviderScope.containerOf(
      tester.element(find.byType(OpenSplitApp)),
    ).read(routerProvider);
    Future<void> shoot(String name) => _capture(tester, frame, name);

    await shoot('screenshot-1-groups');

    router.go('/g/$trip');
    await shoot('screenshot-2-expenses');

    await tester.tap(find.text('Balances'));
    await shoot('screenshot-3-balances');

    router.go('/g/$trip/add');
    await _settle(tester);
    await _fillExpense(tester);
    await shoot('screenshot-4-add-expense');

    router.go('/g/$trip/insights');
    await shoot('screenshot-5-insights');

    _resize(tester, _desktop);
    router.go('/g/$trip');
    await shoot('web-app');

    await tester.runAsync(db.close);
    debugDisableShadows = true;
  });
}

void _resize(WidgetTester tester, ({Size size, double pixelRatio}) device) {
  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = device.pixelRatio;
}

/// Lets streams from the database reach the screen.
///
/// Drift answers on real time, which a widget test's fake clock never
/// advances, so each step yields to it before pumping a frame.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey frame, String name) async {
  await _settle(tester);
  final boundary = frame.currentContext!.findRenderObject()!;
  await tester.runAsync(() async {
    final image = await (boundary as RenderRepaintBoundary).toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_output/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Types an expense into the editor, stopping short of saving it.
Future<void> _fillExpense(WidgetTester tester) async {
  Finder field(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(TextField))
      .first;

  await tester.enterText(field('What was it?'), 'Sunset sail on the Tagus');
  await tester.enterText(field('How much?'), '180');
  await tester.tap(find.text('Uncategorised'));
  await _settle(tester);
  final category = find.text('Activities & outings');
  await tester.scrollUntilVisible(
    category,
    200,
    scrollable: find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    ),
  );
  await _settle(tester);
  await tester.tap(category);
  await _settle(tester);
  FocusManager.instance.primaryFocus?.unfocus();
}

/// Loads every font the app bundles, and a fallback for the glyphs they lack.
///
/// A test renders with nothing but the fonts it is given. On a phone, a
/// character Instrument Sans does not have — the `≈` on an estimate, the `₹`
/// — comes from the system font; here it would be a box. google_fonts names
/// the family's bare name as the fallback for its styles, so the SDK's copy of
/// Roboto, Android's system font, is registered under that name to stand in
/// for the system.
Future<void> _loadFonts() async {
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }

  final roboto = Directory(
    '${Platform.environment['FLUTTER_ROOT']}'
    '/bin/cache/artifacts/material_fonts',
  );
  final fallback = FontLoader('InstrumentSans');
  for (final weight in ['Regular', 'Medium']) {
    final file = File('${roboto.path}/Roboto-$weight.ttf');
    fallback.addFont(file.readAsBytes().then(ByteData.sublistView));
  }
  await fallback.load();
}

/// Four groups in three currencies, the first of them a trip with two.
///
/// Returns the trip's id. Groups list newest first, so it is created last.
Future<String> _seed(AppDatabase db) async {
  final groups = DriftGroupRepository(db);
  final entries = DriftEntryRepository(db);
  final today = DateTime.now();

  Future<({String group, List<String> members})> group(
    String name,
    String currency,
    List<String> others,
  ) async {
    final created = await groups.createGroup(
      name: name,
      defaultCurrency: currency,
      creatorDisplayName: 'Ana',
      creatorProfileId: testAccountId,
    );
    final id = created.group.id;
    return (
      group: id,
      members: [
        created.creator.id,
        for (final other in others)
          (await groups.addMember(id, displayName: other)).id,
      ],
    );
  }

  Future<void> spend(
    String groupId,
    String description,
    String category,
    String currency,
    int amountMinor, {
    required String paidBy,
    required List<String> splitBetween,
    required int daysAgo,
    double? fxRate,
  }) async {
    final date = today.subtract(Duration(days: daysAgo));
    await entries.create(
      EntryDraft(
        groupId: groupId,
        currency: currency,
        amountMinor: amountMinor,
        description: description,
        categoryId: category,
        entryDate: date,
        split: EqualSplit(splitBetween),
        payerAmounts: {paidBy: amountMinor},
        fxRate: fxRate,
        fxSource: fxRate == null ? null : 'ecb',
      ),
      createdBy: paidBy,
      now: date,
    );
  }

  final football = await group('Sunday football', 'GBP', [
    'Tom',
    'Kofi',
    'Wei',
    'Dan',
    'Luis',
    'Sara',
  ]);
  final [ana, tom, ...] = football.members;
  await spend(
    football.group,
    'Pitch hire',
    _Category.outings,
    'GBP',
    8400,
    paidBy: tom,
    splitBetween: football.members,
    daysAgo: 20,
  );
  await entries.create(
    EntryDraft.settlement(
      groupId: football.group,
      currency: 'GBP',
      amountMinor: 1200,
      fromMemberId: ana,
      toMemberId: tom,
      entryDate: today.subtract(const Duration(days: 18)),
    ),
    createdBy: ana,
  );

  final goa = await group('Goa with family', 'INR', ['Mum', 'Ravi']);
  await spend(
    goa.group,
    'Villa in Assagao',
    _Category.accommodation,
    'INR',
    1860000,
    paidBy: goa.members[0],
    splitBetween: goa.members,
    daysAgo: 12,
  );
  await spend(
    goa.group,
    'Seafood in Baga',
    _Category.restaurants,
    'INR',
    342000,
    paidBy: goa.members[2],
    splitBetween: goa.members,
    daysAgo: 11,
  );

  final flat = await group('Flat 4B', 'GBP', ['Priya', 'Jonah']);
  final [me, priya, jonah] = flat.members;
  for (final (description, category, amount, payer, days) in [
    ('Energy bill', _Category.utilities, 18642, priya, 9),
    ('Broadband', _Category.internet, 3600, me, 6),
    ('Big shop', _Category.groceries, 6427, jonah, 3),
  ]) {
    await spend(
      flat.group,
      description,
      category,
      'GBP',
      amount,
      paidBy: payer,
      splitBetween: flat.members,
      daysAgo: days,
    );
  }

  final lisbon = await group('Lisbon trip', 'EUR', ['Maya', 'Arjun', 'Léa']);
  final [you, maya, arjun, lea] = lisbon.members;
  final everyone = lisbon.members;
  await spend(
    lisbon.group,
    'Flights from Gatwick',
    _Category.flights,
    'GBP',
    41280,
    // Arjun booked them, so the trip owes you euros while you owe him pounds:
    // the group list shows both directions, each on its own line.
    paidBy: arjun,
    splitBetween: everyone,
    daysAgo: 6,
    fxRate: 1.1712,
  );
  for (final (description, category, amount, payer, people, days) in [
    ('Apartment in Alfama', _Category.accommodation, 64000, you, everyone, 5),
    ('Tram 28 passes', _Category.transit, 2400, lea, everyone, 4),
    (
      'Dinner at Taberna da Rua',
      _Category.restaurants,
      9640,
      maya,
      everyone,
      3,
    ),
    ('Gulbenkian tickets', _Category.outings, 3600, lea, [you, maya, lea], 2),
    ('Fado night', _Category.outings, 8800, maya, everyone, 1),
    ('Pastéis de nata', _Category.restaurants, 1240, arjun, everyone, 0),
  ]) {
    await spend(
      lisbon.group,
      description,
      category,
      'EUR',
      amount,
      paidBy: payer,
      splitBetween: people,
      daysAgo: days,
    );
  }
  return lisbon.group;
}

/// Category ids from the server's reference data.
abstract final class _Category {
  static const restaurants = 'e7b1844c-76a3-4d2b-bd81-56a74e11f943';
  static const groceries = 'afe84b91-6ac5-4ec2-9290-bd18cb8a7605';
  static const accommodation = '1f289d21-ff2f-4382-a4f8-31d6366583fa';
  static const flights = '8a682d2e-53f2-4d7f-9217-16e360c3eaa5';
  static const transit = 'dff02d03-31fa-476d-b6d4-67c9322c3b50';
  static const outings = 'f5676a7a-6c8b-4ac9-bf09-ccc982885153';
  static const utilities = 'cfb5c503-c424-41d4-a285-a51ab44f0a28';
  static const internet = '669596e4-88f5-4a66-97d0-a6f5857cc6b0';
}
