import 'package:flutter/material.dart';

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
