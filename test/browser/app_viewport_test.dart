@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/presentation/theme.dart';
import 'package:opensplit/presentation/widgets/app_viewport.dart';
import 'package:web/web.dart' as web;

void main() {
  testWidgets('routes and sheets share the safe viewport', (tester) async {
    final view = tester.view;
    view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600)
      ..padding = const FakeViewPadding(
        left: 44,
        top: 32,
        right: 24,
        bottom: 16,
      )
      ..viewPadding = view.padding;
    addTearDown(view.reset);

    const body = Key('body');
    const sheet = Key('sheet');
    late BuildContext pageContext;
    await tester.pumpWidget(
      _app(
        ThemeMode.light,
        Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox.expand(key: body));
          },
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(body)),
      const Rect.fromLTRB(44, 32, 776, 584),
    );
    expect(MediaQuery.paddingOf(pageContext), EdgeInsets.zero);

    final dismissal = showModalBottomSheet<void>(
      context: pageContext,
      builder: (context) => const SizedBox(height: 100, key: sheet),
    );
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byKey(sheet)).dy, 584);
    Navigator.pop(pageContext);
    await tester.pumpAndSettle();
    await dismissal;

    view
      ..padding = const FakeViewPadding(left: 44, top: 32, right: 24)
      ..viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    expect(MediaQuery.viewInsetsOf(pageContext).bottom, 240);
    expect(tester.getBottomLeft(find.byKey(body)).dy, 360);
  });

  testWidgets('browser chrome follows the selected theme', (tester) async {
    final meta = web.document.createElement('meta') as web.HTMLMetaElement
      ..id = 'app-theme-color'
      ..name = 'theme-color'
      ..setAttribute('media', '(prefers-color-scheme: light)');
    web.document.head!.append(meta);
    final root = web.document.documentElement as web.HTMLElement;
    final originalStyle = root.getAttribute('style');
    addTearDown(() {
      meta.remove();
      if (originalStyle == null) {
        root.removeAttribute('style');
      } else {
        root.setAttribute('style', originalStyle);
      }
    });

    await tester.pumpWidget(_app(ThemeMode.dark, const Scaffold()));
    expect(meta.content, '#121318');
    expect(meta.hasAttribute('media'), isFalse);
    expect(root.style.getPropertyValue('--surface'), '#121318');
    expect(root.style.getPropertyValue('color-scheme'), 'dark');

    await tester.pumpWidget(_app(ThemeMode.light, const Scaffold()));
    expect(meta.content, '#fbf8ff');
    expect(root.style.getPropertyValue('--surface'), '#fbf8ff');
    expect(root.style.getPropertyValue('color-scheme'), 'light');
  });
}

Widget _app(ThemeMode mode, Widget home) => MaterialApp(
  theme: buildTheme(Brightness.light),
  darkTheme: buildTheme(Brightness.dark),
  themeMode: mode,
  themeAnimationStyle: AnimationStyle.noAnimation,
  builder: (context, child) => AppViewport(child: child!),
  home: home,
);
