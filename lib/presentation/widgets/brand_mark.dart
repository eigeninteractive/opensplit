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
    // Scaled with the text rather than fixed, so the pair still reads as a
    // lockup for someone running a large font size instead of the mark
    // shrinking against a word that grew.
    final fontSize = Theme.of(context).textTheme.titleLarge?.fontSize ?? 22;
    final size =
        MediaQuery.textScalerOf(context).scale(fontSize) * _boxPerFontSize;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size),
        SizedBox(width: size * _gapPerBox),
        const Flexible(child: Text('OpenSplit')),
      ],
    );
  }
}
