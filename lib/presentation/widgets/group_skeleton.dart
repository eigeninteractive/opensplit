import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// The group list as it looks before the local database has answered.
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
