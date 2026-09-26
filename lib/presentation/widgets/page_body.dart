import 'package:flutter/material.dart';

import '../router.dart';

/// Constrains page content to a readable width.
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
            // worth the height when you arrive and worth none of it while you
            // are reading, but the bar itself never leaves.
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
