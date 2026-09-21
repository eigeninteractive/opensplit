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
/// All three destinations use it, including the group list, whose headline is
/// the brand lockup rather than a word — [BrandLockup] takes its size from the
/// text style in force, so it grows and shrinks with the bar instead of sitting
/// at one size while the word beside it moves.
///
/// The loading skeleton in `web/index.html` draws the same bar. That is a
/// consequence of this decision rather than a constraint on it: the app decides
/// what the screen is, and the skeleton is redrawn to match. A test pins the
/// two together so they cannot drift silently.
///
/// The bar spans the window while the content keeps [PageBody]'s reading
/// measure, which is why this is a [LayoutBuilder] around a [CustomScrollView]
/// rather than a [PageBody] around one: constraining the whole scroll view
/// would leave the app bar as a 760dp island on a monitor, with the scaffold's
/// surface either side of it.
class DestinationScaffold extends StatelessWidget {
  const DestinationScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.slivers,
    this.actions,
    this.floatingActionButton,
    this.wrap,
    this.maxWidth = 760,
  }) : assert(
         title != null || titleWidget != null,
         'a destination needs a headline',
       );

  /// The headline, for the two destinations whose headline is a word.
  final String? title;

  /// The headline, for the one whose headline is a drawing.
  final Widget? titleWidget;

  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// Wraps the scroll view, for the destination that pulls to sync.
  ///
  /// A [RefreshIndicator] has to be an ancestor of the scrollable it listens
  /// to, so it cannot be one of [slivers] and cannot go outside the Scaffold
  /// either — the app bar would be inside the gesture. This is the one hook
  /// that lets the group list put it in the only place it works.
  final Widget Function(Widget scrollView)? wrap;

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

      final view = CustomScrollView(
        // Always scrollable, so a pull-to-sync gesture exists on a list too
        // short to scroll — which is exactly the list a new device shows.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar.large(
            title: titleWidget ?? Text(title!),
            actions: actions,
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
      );

      return Scaffold(
        drawer: AdaptiveNavigation.drawerFor(context),
        floatingActionButton: floatingActionButton,
        body: wrap == null ? view : wrap!(view),
      );
    },
  );
}
