import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// An extended floating action button that shrinks to its icon when the
/// list behind it is scrolled down, and takes its label back on the way up.
///
/// Material's own behaviour for an extended button over scrolling content:
/// the stock [FloatingActionButton.extended] animates between the two when
/// `isExtended` changes, and [extended] decides when.
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
      tooltip: extended ? null : label,
      isExtended: extended,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}
