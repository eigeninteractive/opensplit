import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// The group list as it looks before the local database has answered.
///
/// Built out of the same widgets as the real list — `Card.outlined` wrapping a
/// `ListTile` with an avatar and two lines — rather than out of measurements
/// copied from it. That is the whole design of this file. A skeleton exists to
/// make the swap invisible, and the only way to be sure a placeholder is
/// exactly as tall as the thing replacing it is for the two to be laid out by
/// the same code. The previous version reproduced the tile as a Row with hand
/// derived padding, which was right on the day it was written and would drift
/// the first time a density, a text scale or a type ramp moved underneath it.
///
/// `web/index.html` draws a third copy, in CSS, before the engine has even
/// downloaded. It cannot share widgets, so it is held to the same geometry by a
/// test that renders this widget, measures a card, and asserts the stylesheet
/// carries that number — see `theme_test.dart`. The app decides the shape; the
/// stylesheet follows it.
class GroupListSkeleton extends StatefulWidget {
  const GroupListSkeleton({super.key, this.cards = 3});

  /// Enough to fill a phone without implying a number.
  final int cards;

  @override
  State<GroupListSkeleton> createState() => _GroupListSkeletonState();
}

class _GroupListSkeletonState extends State<GroupListSkeleton>
    with SingleTickerProviderStateMixin {
  /// How many times the bars breathe before coming to rest.
  ///
  /// The CSS this mirrors says `infinite`, and that is the one line of it not
  /// worth reproducing. A repeating controller schedules a frame forever, which
  /// means any `pumpAndSettle` taken while this is on screen never settles —
  /// and this is the home screen's loading state, so that is most of them. The
  /// same hazard is why `CircularProgressIndicator` cannot be settled either;
  /// the difference is that one is Flutter's to own and this one is ours.
  ///
  /// Bounding it costs nothing real. The pulse is there to say "not frozen"
  /// while a local SQLite read finishes, which takes milliseconds; if it has
  /// breathed five times the read is not coming and the honest signal is the
  /// sync notice, not more motion.
  static const _cycles = 5;

  /// One controller for every bar on screen rather than one per card. The
  /// per-card offset is applied to the value, not to the clock, which is what
  /// CSS `animation-delay` does and costs two tickers fewer.
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800 * _cycles),
  )..forward();

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  /// The title and detail widths, per card.
  ///
  /// Varied because three identical cards read as a graphic rather than as
  /// content arriving. Repeated modulo the count, so a longer list keeps the
  /// same texture.
  static const _widths = <(double, double)>[
    (0.62, 0.40),
    (0.44, 0.56),
    (0.55, 0.40),
  ];

  @override
  Widget build(BuildContext context) {
    // Honoured for the same reason the CSS honours it: a pulse that cannot be
    // turned off is exactly the kind of motion this setting exists to stop.
    final still = MediaQuery.disableAnimationsOf(context);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
      sliver: SliverList.separated(
        itemCount: widget.cards,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final (title, detail) = _widths[index % _widths.length];
          return SkeletonGroupCard(
            breathe: _breathe,
            cycles: _cycles,
            // 0.15s apart at 1.8s a cycle.
            phase: still ? 0 : (index % _widths.length) * (0.15 / 1.8),
            animate: !still,
            titleWidth: title,
            detailWidth: detail,
          );
        },
      ),
    );
  }
}

/// One card of the skeleton.
///
/// Public only so a test can render one and measure it; nothing else should
/// build this directly.
class SkeletonGroupCard extends StatelessWidget {
  const SkeletonGroupCard({
    super.key,
    required this.breathe,
    required this.cycles,
    required this.phase,
    required this.animate,
    required this.titleWidth,
    required this.detailWidth,
  });

  final Animation<double> breathe;
  final int cycles;
  final double phase;
  final bool animate;
  final double titleWidth;
  final double detailWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ExcludeSemantics(
      child: Card.outlined(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          // Not a placeholder: there is no version of this row without an
          // avatar, so it is drawn in its final colour.
          leading: CircleAvatar(backgroundColor: scheme.secondaryContainer),
          title: _Line(
            style: theme.textTheme.titleMedium,
            barHeight: 16,
            widthFactor: titleWidth,
            breathe: breathe,
            cycles: cycles,
            phase: phase,
            animate: animate,
          ),
          subtitle: _Line(
            style: theme.textTheme.bodyMedium,
            barHeight: 12,
            widthFactor: detailWidth,
            breathe: breathe,
            cycles: cycles,
            phase: phase,
            animate: animate,
          ),
        ),
      ),
    );
  }
}

/// A bar standing in for a line of text.
///
/// The slot's height comes from a real, invisible [Text] set in the style the
/// line will actually use, rather than from a number read off the type scale.
/// That is what keeps the card exactly as tall as the one replacing it —
/// including at a large system font size, which a hardcoded height would
/// ignore, and through any later change to the app's type ramp.
class _Line extends StatelessWidget {
  const _Line({
    required this.style,
    required this.barHeight,
    required this.widthFactor,
    required this.breathe,
    required this.cycles,
    required this.phase,
    required this.animate,
  });

  final TextStyle? style;
  final double barHeight;
  final double widthFactor;
  final Animation<double> breathe;
  final int cycles;
  final double phase;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Reserves the line box. Never painted, never read aloud.
        Opacity(opacity: 0, child: Text('​', style: style)),
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: breathe,
              builder: (context, child) {
                final done = breathe.isCompleted;
                final t = (breathe.value * cycles + phase) % 1;
                // 0%,100% -> 1; 50% -> 0.45, eased both ways.
                final curved = Curves.easeInOut.transform(
                  t < 0.5 ? t * 2 : (1 - t) * 2,
                );
                // Rests at full opacity rather than wherever the last frame
                // happened to land, which for the offset cards is not 1.
                final opacity = (animate && !done) ? 1 - (0.55 * curved) : 1.0;
                return Opacity(opacity: opacity, child: child);
              },
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Previews the skeleton beside what it stands in for.
@Preview(name: 'Group list skeleton', group: 'Empty', size: Size(360, 320))
Widget groupListSkeletonPreview() => const MaterialApp(
  home: Scaffold(body: CustomScrollView(slivers: [GroupListSkeleton()])),
);
