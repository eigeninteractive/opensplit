import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The OpenSplit mark: a ring with one diagonal cut through it.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 24, this.color, this.semanticsLabel});

  /// Both the width and the height. The mark is square and stays on its own
  /// 48-unit grid, so it scales without hinting.
  final double size;

  /// Defaults to [ColorScheme.primary], the role the brand violet becomes.
  final Color? color;

  /// What a screen reader should announce, if anything.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.primary;

    final mark = SvgPicture.asset(
      'assets/brand/mark-mono.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
    );

    if (semanticsLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticsLabel, image: true, child: mark);
  }
}

/// The mark and the app's name, side by side.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  /// How much bigger the mark's box is than the type beside it.
  static const double _boxPerFontSize = (34.5 / 30) / 0.72;

  /// Clear space between the ring and the word, on the same measurement.
  static const double _gapPerBox = 10.25 / 48;

  @override
  Widget build(BuildContext context) {
    // Taken from the text style in force rather than a named theme style: a
    // large app bar animates its title between two sizes, and DefaultTextStyle
    // is what AppBar and FlexibleSpaceBar set and animate, so the ring scales
    // with the word beside it.
    final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 22;
    final size =
        MediaQuery.textScalerOf(context).scale(fontSize) * _boxPerFontSize;

    // Scaled to fit rather than allowed to wrap, and that is the one thing this
    // widget cannot compromise on: a lockup is a mark and a word read as a
    // single object, and "Open" above "Split" beside a ring is not the
    // designer's drawing, it is two things that happen to be adjacent.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(size: size),
          SizedBox(width: size * _gapPerBox),
          const Text('OpenSplit', maxLines: 1, softWrap: false),
        ],
      ),
    );
  }
}

/// The mark, the name and a line of explanation, stacked — what an arrival sees
/// before they are asked anything.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, required this.title, this.subtitle});

  /// The heading beneath the mark. Carries the semantics for both: the mark
  /// itself stays decorative, so a screen reader says the name once.
  final String title;

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: BrandMark(size: 56, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// A soft wash of brand colour behind a page that is mostly empty.
class BrandWash extends StatelessWidget {
  const BrandWash({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          // Above centre, where the mark is, rather than in the middle of the
          // page — a glow centred on the form looks like a selection.
          center: const Alignment(0, -0.6),
          radius: 1.1,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.38),
            scheme.primaryContainer.withValues(alpha: 0),
          ],
        ),
      ),
      child: child,
    );
  }
}
