import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/calendar_date.dart';

/// The calendar day the rows under it happened on.
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.day});

  /// A calendar day at UTC midnight, as [calendarDay] gives it.
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Semantics(
        header: true,
        child: Text(
          dayLabel(day, today: calendarDay(DateTime.now())),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", or the date, with the year only when it is not this
/// one.
String dayLabel(DateTime day, {required DateTime today}) {
  final daysAgo = today.difference(day).inDays;
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  return day.year == today.year
      ? DateFormat.MMMEd().format(day)
      : DateFormat.yMMMEd().format(day);
}
