import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supplies the device's current local time for calendar-based UI.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
