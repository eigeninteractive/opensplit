import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind;

import '../../application/ledger_providers.dart';
import '../../data/local/database.dart';
import '../../domain/avatar.dart';
import '../theme.dart';
import 'avatar_view.dart';
import 'category_icon.dart';

/// A group's cover: its hue, patterned with what it spends on.
///
/// Drawn rather than stored. The icons are the group's most frequent
/// categories, so a trip fills with flights and dinners and a flat with bills
/// and groceries, and the picture follows the group as it goes on. Before
/// anything is spent it uses the group's own avatar. The layout is seeded by
/// the group's id, so the same group looks the same on every device. Both the
/// list card and header crop the same fixed composition, including in flight.
class GroupCover extends ConsumerWidget {
  const GroupCover({super.key, required this.ledger, this.patternFade = 0});

  final GroupLedger ledger;

  /// Softens the pattern under list text: zero in the header, one in a row.
  final double patternFade;

  /// How many of the most frequent categories make up the pattern.
  static const _motifs = 5;
  static const _artworkSize = Size(640, 192);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ledger.group;
    final avatar = group.avatar;
    final scheme = AvatarPalette.of(context).forAvatar(avatar, group.id);
    final categories = <String, Category>{
      for (final category
          in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id: category,
    };

    final motifs = <Widget Function(double size)>[
      for (final icon in _frequentIcons(categories))
        (size) => Icon(icon, size: size),
    ];
    if (motifs.isEmpty) {
      motifs.add(switch (avatar) {
        EmojiAvatar(:final emoji) => (size) => Text(
          emoji,
          style: TextStyle(fontSize: size * 0.8),
        ),
        IconAvatar(:final icon) => (size) => Icon(
          avatarIconData(icon),
          size: size,
        ),
        InitialsAvatar() ||
        PhotoAvatar() => (size) => Icon(Icons.receipt_long_rounded, size: size),
      });
    }

    return ExcludeSemantics(
      child: ColoredBox(
        color: scheme.primaryContainer,
        child: IconTheme.merge(
          data: IconThemeData(
            color: scheme.onPrimaryContainer.withValues(alpha: 0.18),
          ),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 1 - 0.65 * patternFade),
                Colors.black.withValues(alpha: 1 - 0.65 * patternFade),
                Colors.black.withValues(alpha: 1 - 0.2 * patternFade),
              ],
              stops: const [0, 0.6, 1],
            ).createShader(bounds),
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox.fromSize(
                  size: _artworkSize,
                  child: Stack(
                    children: _pattern(_artworkSize, motifs, group.id),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The icons of the categories this group records most often, most
  /// frequent first.
  List<IconData> _frequentIcons(Map<String, Category> categories) {
    final counts = <String, int>{};
    for (final entry in ledger.entries) {
      if (entry.row.kind != EntryKind.expense) continue;
      final category = entry.row.categoryId;
      if (category == null) continue;
      counts.update(category, (n) => n + 1, ifAbsent: () => 1);
    }
    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final frequency = counts[b]!.compareTo(counts[a]!);
        return frequency == 0 ? a.compareTo(b) : frequency;
      });
    return [
      for (final id in ranked.take(_motifs))
        if (categories[id] case final category?) categoryIcon(category.icon),
    ];
  }

  /// A staggered grid with each motif nudged, turned and sized by a generator
  /// seeded from [seed].
  static List<Widget> _pattern(
    Size size,
    List<Widget Function(double size)> motifs,
    String seed,
  ) {
    const cell = 80.0;
    final random = Random(stableHash(seed));
    final columns = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;
    return [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          _placed(
            random,
            motifs,
            Offset(
              column * cell + (row.isOdd ? cell / 2 : 0) - cell / 2,
              row * cell - cell / 4,
            ),
          ),
    ];
  }

  static Widget _placed(
    Random random,
    List<Widget Function(double size)> motifs,
    Offset origin,
  ) {
    final size = 32.0 + random.nextInt(3) * 8;
    final motif = motifs[random.nextInt(motifs.length)];
    return Positioned(
      left: origin.dx + random.nextDouble() * 16,
      top: origin.dy + random.nextDouble() * 16,
      child: Transform.rotate(
        angle: (random.nextDouble() - 0.5) * 0.6,
        child: motif(size),
      ),
    );
  }
}

/// Shares the entire cover, with its thumbnail corners opening into the header.
class GroupCoverHero extends StatelessWidget {
  const GroupCoverHero({
    super.key,
    required this.ledger,
    this.borderRadius = BorderRadius.zero,
    this.patternFade = 0,
  });

  final GroupLedger ledger;
  final BorderRadius borderRadius;
  final double patternFade;

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: ('group-cover', ledger.group.id),
      transitionOnUserGestures: true,
      flightShuttleBuilder: (context, animation, direction, from, to) {
        final source = (from.widget as Hero).child as ClipRRect;
        final destination = (to.widget as Hero).child as ClipRRect;
        final sourceCover = source.child! as GroupCover;
        final destinationCover = destination.child! as GroupCover;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final progress = direction == HeroFlightDirection.push
                ? animation.value
                : 1 - animation.value;
            return ClipRRect(
              borderRadius: BorderRadiusGeometry.lerp(
                source.borderRadius,
                destination.borderRadius,
                progress,
              )!,
              child: GroupCover(
                ledger: destinationCover.ledger,
                patternFade:
                    sourceCover.patternFade +
                    (destinationCover.patternFade - sourceCover.patternFade) *
                        progress,
              ),
            );
          },
        );
      },
      child: ClipRRect(
        borderRadius: borderRadius,
        child: GroupCover(ledger: ledger, patternFade: patternFade),
      ),
    ),
  );
}
