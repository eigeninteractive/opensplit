import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// The group list as it looks before the local database has answered.
///
/// A deliberate copy of the skeleton `web/index.html` paints before the engine
/// has even downloaded — same card, same 40dp avatar, same two bars at the same
/// widths, same breathing animation. That file argues the case at length and
/// the argument is not web-specific: a blank page reads as broken, a spinner
/// reads as slow, and a layout matching what is about to appear reads as
/// loading.
///
/// What it buys here is the handoff. On the web those two skeletons run back to
/// back — the HTML one is removed the moment Flutter paints — and any
/// difference between them would show up as a flicker at exactly the moment the
/// app is trying to look ready. Being the same drawing twice is why the swap is
/// invisible.
///
/// Every metric below is the one in that file, and the comments there say where
/// each came from. The pair are pinned together by a test rather than by good
/// intentions.
class GroupListSkeleton extends StatefulWidget {
  const GroupListSkeleton({super.key, this.cards = 3});

  /// Enough to fill a phone without implying a number. Three is what the web
  /// skeleton draws.
  final int cards;

  @override
  State<GroupListSkeleton> createState() => _GroupListSkeletonState();
}

class _GroupListSkeletonState extends State<GroupListSkeleton>
    with SingleTickerProviderStateMixin {
  /// How many times the bars breathe before coming to rest.
  ///
  /// The CSS this copies says `infinite`, and that is the one line of it not
  /// worth reproducing. A repeating controller schedules a frame forever, which
  /// means any `pumpAndSettle` taken while this is on screen never settles —
  /// and this is the home screen's loading state, so that is most of them. The
  /// same hazard is why `CircularProgressIndicator` cannot be settled either;
  /// the difference is that one is Flutter's to own and this one is ours.
  ///
  /// Bounding it costs nothing real. The pulse is there to say "not frozen"
  /// while a local SQLite read finishes, which takes milliseconds; if it has
  /// breathed five times the read is not coming and the honest signal is the
  /// sync notice, not more motion. So it runs for nine seconds and rests.
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

  /// The title and detail widths, per card, from the `nth-child` rules.
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: widget.cards,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final (title, detail) = _widths[index % _widths.length];
        return _SkeletonCard(
          breathe: _breathe,
          cycles: _cycles,
          // 0.15s apart at 1.8s a cycle.
          phase: still ? 0 : (index % _widths.length) * (0.15 / 1.8),
          animate: !still,
          titleWidth: title,
          detailWidth: detail,
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({
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
    final scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Not a placeholder: there is no version of this row without an
              // avatar, so it is drawn in its final colour.
              CircleAvatar(backgroundColor: scheme.secondaryContainer),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  // A titleMedium line box (24) + 4 + a bodyMedium one (20), so
                  // the card does not resize under the swap.
                  height: 48,
                  child: AnimatedBuilder(
                    animation: breathe,
                    builder: (context, _) {
                      final done = breathe.isCompleted;
                      final t = (breathe.value * cycles + phase) % 1;
                      // 0%,100% -> 1; 50% -> 0.45, eased both ways.
                      final curved = Curves.easeInOut.transform(
                        t < 0.5 ? t * 2 : (1 - t) * 2,
                      );
                      // Rests at full opacity rather than wherever the last
                      // frame happened to land, which for the offset cards is
                      // not 1.
                      final opacity = (animate && !done)
                          ? 1 - (0.55 * curved)
                          : 1.0;

                      return Opacity(
                        opacity: opacity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            _Bar(height: 16, widthFactor: titleWidth),
                            const SizedBox(height: 11),
                            _Bar(height: 12, widthFactor: detailWidth),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.widthFactor});

  final double height;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

/// Previews the skeleton beside what it stands in for.
@Preview(name: 'Group list skeleton', group: 'Empty', size: Size(360, 320))
Widget groupListSkeletonPreview() =>
    const MaterialApp(home: Scaffold(body: GroupListSkeleton()));
