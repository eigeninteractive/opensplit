/// Android has no service worker; its background isolate runs Dart itself.
void listenToServiceWorker({
  required Future<({String title, String body})?> Function(
    Map<String, dynamic> data,
  )
  describe,
  required void Function(String groupId) openGroup,
}) {}

/// On the web, shows a payment reminder that arrived in a visible tab.
Future<void> showWebReminder({
  required String groupId,
  required String eventId,
  required String title,
  required String body,
}) async {}
