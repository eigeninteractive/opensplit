import 'dart:async';
import 'dart:developer' as developer;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The messages `service_worker/src/messages.ts` defines.
const _describePush = 'opensplit:describe-push';
const _openGroup = 'opensplit:open-group';

/// Answers the service worker's requests to this tab.
///
/// A push that arrives while every tab is hidden goes to the worker, which
/// cannot run Dart and so cannot sync or word the notification the way the app
/// does. It asks a tab to: [describe] syncs the push's group and returns the
/// text, or null when there is nothing worth showing. A tapped notification
/// reaches the tab through [openGroup].
void listenToServiceWorker({
  required Future<({String title, String body})?> Function(
    Map<String, dynamic> data,
  )
  describe,
  required void Function(String groupId) openGroup,
}) {
  if (!web.window.navigator.has('serviceWorker')) return;
  final container = web.window.navigator.serviceWorker;

  container.addEventListener(
    'message',
    (web.MessageEvent event) {
      final message = event.data.dartify();
      if (message is! Map) return;
      switch (message) {
        case {'type': _describePush, 'push': final Map push}:
          final port = event.ports.toDart.firstOrNull;
          if (port != null) unawaited(_answer(port, push, describe));
        case {'type': _openGroup, 'groupId': final String groupId}:
          openGroup(groupId);
      }
    }.toJS,
  );
  // Messages the worker sent before this listener existed are held until now.
  container.startMessages();
}

/// Replies with the worker's `DescribeReply`.
Future<void> _answer(
  web.MessagePort port,
  Map<Object?, Object?> push,
  Future<({String title, String body})?> Function(Map<String, dynamic>)
  describe,
) async {
  Map<String, String> reply;
  try {
    final text = await describe(push.cast<String, dynamic>());
    reply = text == null
        ? {'status': 'skip'}
        : {'status': 'show', 'title': text.title, 'body': text.body};
  } catch (error, stackTrace) {
    developer.log(
      'Could not describe a push for the service worker',
      name: 'opensplit.push',
      error: error,
      stackTrace: stackTrace,
      level: 900,
    );
    // The worker words it itself, rather than showing nothing.
    reply = {'status': 'failed'};
  }
  port.postMessage(reply.jsify());
}
