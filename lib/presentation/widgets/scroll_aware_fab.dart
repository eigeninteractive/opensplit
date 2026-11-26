import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// An extended floating action button that shrinks to its icon when the
/// list behind it is scrolled down, and takes its label back on the way up.
///
/// Keeps one Material button while [extended] animates the label in or out.
class ScrollAwareFab extends StatelessWidget {
  const ScrollAwareFab({
    super.key,
    required this.extended,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  /// Whether the label shows beside the icon.
  final ValueListenable<bool> extended;

  final VoidCallback onPressed;
  final IconData icon;

  /// The visible label, and the tooltip while only the icon shows.
  final String label;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: extended,
    builder: (context, extended, _) => FloatingActionButton.extended(
      heroTag: null,
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon),
      // Equal padding keeps the icon centered when the label is hidden.
      extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
      extendedIconLabelSpacing: 0,
      label: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: extended ? 1.0 : 0.0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          builder: (context, factor, child) => ClipRect(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: factor,
              child: Opacity(opacity: factor, child: child),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
            child: Text(label),
          ),
        ),
      ),
    ),
  );
}
