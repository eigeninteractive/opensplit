import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// An extended floating action button that shrinks to its icon while the
/// list behind it is moving, and takes its label back when the list rests.
///
/// Material's own behaviour for an extended button over scrolling content:
/// the stock [FloatingActionButton.extended] animates between the two when
/// `isExtended` changes, and this only decides when.
class ScrollAwareFab extends StatelessWidget {
  const ScrollAwareFab({
    super.key,
    required this.scrolling,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  /// Whether the content behind the button is being scrolled.
  final ValueListenable<bool> scrolling;

  final VoidCallback onPressed;
  final IconData icon;

  /// The visible label, and the tooltip while only the icon shows.
  final String label;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: scrolling,
    builder: (context, scrolling, _) => FloatingActionButton.extended(
      heroTag: null,
      tooltip: scrolling ? label : null,
      isExtended: !scrolling,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}
