/// Android has no service worker; its background isolate runs Dart itself.
void listenToServiceWorker({
  required Future<({String title, String body})?> Function(
    Map<String, dynamic> data,
  )
  describe,
  required void Function(String groupId) openGroup,
}) {}
