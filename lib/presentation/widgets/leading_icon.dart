import 'package:material_ui/material_ui.dart';

/// A list item's leading icon, centred in the width of a leading avatar.
///
/// Material puts a list's text after its leading element, so a 24dp icon and
/// a 40dp avatar in one list start their text at different places. Giving the
/// icon the avatar's width lines every row's text up.
class LeadingIcon extends StatelessWidget {
  const LeadingIcon(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  /// The width of a Material list's leading avatar.
  static const width = 40.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Center(child: Icon(icon, color: color)),
  );
}
