import '../../data/local/database.dart';

export '../../data/local/database.dart' show Group;

extension GroupState on Group {
  bool get isArchived => archivedAt != null;
}
