import 'package:flutter/material.dart';

import '../router.dart';

/// Constrains page content to a readable width.
///
/// Without this every list on the web stretches the full width of whatever
/// monitor it lands on, which for an expense row means a name on the far left,
/// an amount on the far right, and half a metre of nothing between them. A
/// phone layout scaled to 1920px is not a desktop layout.
///
/// The cap is a reading measure rather than a breakpoint: below it, this is
/// exactly the padding the page would have had anyway, so nothing about the
/// phone layout changes.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = 760,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// A top-level destination whose headline is a word, under a Material 3 large
/// top app bar.
///
/// The spec's own use for one: a screen where the headline is the first thing
/// read, set at `headlineMedium` above the content and collapsing to the
/// ordinary bar once somebody scrolls. It gives Account and Settings the type
/// hierarchy the rest of the app has and those two did not — every app bar in
/// here was the small one, so a destination and a drill-down looked alike.
///
/// Deliberately **not** used on the group list, for two reasons that both
/// happen to point the same way. Its title is the brand lockup rather than a
/// word, and a large bar exists to make a headline large — there is no headline
/// there to enlarge. And that bar is drawn a second time in `web/index.html`,
/// whose metrics are pinned against this theme by a test, so a large bar here
/// and a small one there would show up as a jump at exactly the moment the
/// loading skeleton hands over to the engine.
///
/// The bar spans the window while the content keeps [PageBody]'s reading
/// measure, which is why this is a [LayoutBuilder] around a [CustomScrollView]
/// rather than a [PageBody] around one: constraining the whole scroll view
/// would leave the app bar as a 760dp island on a monitor, with the scaffold's
/// surface either side of it.
class DestinationScaffold extends StatelessWidget {
  const DestinationScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.maxWidth = 760,
  });

  final String title;

  /// The page itself. Vertical spacing belongs to these; the horizontal inset
  /// is this widget's, because it is what centres them.
  final List<Widget> slivers;

  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The same 16dp the phone layout would have had anyway, widening into a
      // centring margin once the window is bigger than the measure.
      final side = ((constraints.maxWidth - maxWidth) / 2).clamp(
        16.0,
        double.infinity,
      );

      return Scaffold(
        drawer: AdaptiveNavigation.drawerFor(context),
        body: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: Text(title),
              // Collapses into the small bar and stays there, which is what
              // Material 3 specifies for a large top app bar: the headline is
              // worth the height when you arrive and worth none of it while
              // you are reading, but the bar itself never leaves.
              //
              // Not `floating: true, snap: true`. That asks a header with an
              // expanded height to re-snap on every scroll-up, and the
              // resulting animation schedules a frame indefinitely — the same
              // way an infinite `repeat()` does, and with the same consequence
              // for every pumpAndSettle taken on these two screens.
              pinned: true,
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 32),
              sliver: SliverMainAxisGroup(slivers: slivers),
            ),
          ],
        ),
      );
    },
  );
}
