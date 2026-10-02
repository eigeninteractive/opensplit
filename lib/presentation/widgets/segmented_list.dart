import 'package:material_ui/material_ui.dart';

/// Material 3 Expressive's segmented list: items filled in a surface
/// container, 2dp apart, with large corners on the outside of the group and
/// extra-small ones between its items.
///
/// Compose ships this as `SegmentedListItem` with
/// `ListItemDefaults.segmentedShapes(index, count)`; material_ui has not yet.
/// This is that layout over the stock [ListTile] and nothing more, so when
/// material_ui ships its own it replaces this file without touching a screen.
class SegmentedList extends StatelessWidget {
  const SegmentedList({super.key, required this.children});

  /// Usually [ListTile]s.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++)
        Segment(index: i, count: children.length, child: children[i]),
    ],
  );
}

/// One item of a [SegmentedList], for a list built lazily that cannot hand
/// over all its children at once.
class Segment extends StatelessWidget {
  const Segment({
    super.key,
    required this.index,
    required this.count,
    required this.child,
  });

  final int index;
  final int count;
  final Widget child;

  /// Material's large and extra-small corner tokens.
  static const _outer = Radius.circular(16);
  static const _inner = Radius.circular(4);

  /// The gap between two items of one group.
  static const gap = 2.0;

  @override
  Widget build(BuildContext context) {
    final first = index == 0;
    final last = index == count - 1;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : gap),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: first ? _outer : _inner,
            bottom: last ? _outer : _inner,
          ),
        ),
        child: child,
      ),
    );
  }
}
