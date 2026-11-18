import 'package:material_ui/material_ui.dart';

import 'segmented_list.dart';

/// A group of rows folded under its own heading: Material's expansion
/// tile, on the surface and corners the lists around it use.
class FoldedSection extends StatelessWidget {
  const FoldedSection({
    super.key,
    required this.storageKey,
    required this.title,
    required this.summary,
    required this.initiallyExpanded,
    required this.children,
  });

  /// Keeps the fold open or shut while its screen is scrolled or its tab is
  /// away.
  final String storageKey;
  final String title;
  final String summary;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: Segment.radiusAt(index: 0, count: 1),
    ),
    child: ExpansionTile(
      key: PageStorageKey(storageKey),
      initiallyExpanded: initiallyExpanded,
      // The surface already has its outline; the tile's own dividers
      // would draw a second one inside it.
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title),
      subtitle: Text(summary),
      children: children,
    ),
  );
}
