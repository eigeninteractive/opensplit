import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The OpenSplit mark: a ring with one diagonal cut through it.
///
/// Drawn from `mark-mono.svg`, which strokes itself in `currentColor` rather
/// than in the brand violet. That is the whole reason it is the variant used
/// here: one asset serves every surface in the app, tinted to whichever
/// [ColorScheme] role the place it sits in calls for, and it keeps working when
/// Material You replaces the palette with the user's wallpaper. The pre-stroked
/// variants beside it in `assets/brand/` exist for contexts that cannot tint —
/// an `<img>` tag, a store listing — and none of those are in this app.
///
/// Vector rather than the 1024px PNGs, because the cut is a knockout: the mask
/// lets the surface behind show through the ring, so the mark sits on a card or
/// a coloured container without carrying its own background. A bitmap would
/// have to bake one in.
///
/// Decorative by default. The mark never appears without the word "OpenSplit"
/// or a heading beside it, so announcing it as well would make a screen reader
/// say the name twice. Pass [semanticsLabel] where that stops being true.
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
///
/// Composed here rather than taken from `lockup-horizontal.svg`, even though
/// that file exists and is the one the brand kit offers for an app bar. The
/// lockup sets the word as SVG `<text>` in Instrument Sans, which would mean
/// text that does not scale with the platform's font setting, cannot be
/// selected, and renders in whatever the SVG renderer decides if the family is
/// missing. Building it from the mark plus a real [Text] gives the same drawing
/// out of the app's own type scale, and the word stays a word.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  /// How much bigger the mark's box is than the type beside it.
  ///
  /// Measured off `lockup-horizontal.svg` rather than chosen: there the ring
  /// spans 34.5 units against a 30-unit word, and the ring fills 72% of the
  /// square it is drawn in, so the box wants to be a little over one and a
  /// half times the font size. Matching the ratio keeps this the designer's
  /// lockup at any size, rather than an arrangement that resembles it.
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

    // Scaled to fit rather than allowed to wrap, and that is the one thing
    // this widget cannot compromise on: a lockup is a mark and a word read as
    // a single object, and "Open" above "Split" beside a ring is not the
    // designer's drawing, it is two things that happen to be adjacent.
    //
    // It is also a correctness fix. In a Material 3 large app bar the expanded
    // headline is laid out inside FlexibleSpaceBar, which measures the title
    // and then paints it through a scale transform. A Flexible child that
    // wraps changes height between those two steps, and RenderParagraph
    // asserts on exactly that -- so at a 200% system font size the app bar did
    // not merely look wrong, it threw during paint.
    //
    // scaleDown, so nothing is ever enlarged past the type scale: at ordinary
    // sizes this is the identity and the lockup is set at its real size.
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

/// The mark, the name and a line of explanation, stacked — what an arrival
/// sees before they are asked anything.
///
/// Used on the two screens somebody can reach without a session.
///
/// The mark sits in a [ColorScheme.primaryContainer] disc rather than on the
/// page. A knockout ring drawn straight onto `surface` reads as a stray glyph
/// at this size, and the disc is also what keeps it legible once Material You
/// has replaced the palette with somebody's wallpaper — the pair are a
/// container role and its `on` colour, so they are contrast-correct together by
/// construction rather than by having been checked once.
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
///
/// The welcome and join screens are a short column in the middle of a large
/// flat surface, which on a tablet or a desktop browser is a great deal of
/// nothing. This puts a single radial gradient behind them, fading to
/// transparent well before the edges so it never becomes a band with a visible
/// end.
///
/// [ColorScheme.primaryContainer] at low opacity rather than a colour of its
/// own: it follows the wallpaper palette with everything else, and at these
/// alphas it cannot fail a contrast ratio because nothing is read against it
/// that is not also on `surface`.
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
