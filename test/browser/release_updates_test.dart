@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:opensplit/data/web/release_updates.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

@JS('Object.defineProperty')
external void _defineProperty(
  JSObject target,
  JSString name,
  JSObject descriptor,
);

@JS('Object.getOwnPropertyDescriptor')
external JSObject? _descriptor(JSObject target, JSString name);

@JS('Reflect.deleteProperty')
external JSBoolean _deleteProperty(JSObject target, JSString name);

void main() {
  test(
    'web update waits for installation and activates only a waiting release',
    () async {
      final registration = JSObject();
      final container = JSObject();
      final property = 'serviceWorker'.toJS;
      final original = _descriptor(web.window.navigator, property);
      addTearDown(() {
        if (original == null) {
          _deleteProperty(web.window.navigator, property);
        } else {
          _defineProperty(web.window.navigator, property, original);
        }
      });
      _defineProperty(
        web.window.navigator,
        property,
        JSObject()
          ..setProperty('configurable'.toJS, true.toJS)
          ..setProperty('value'.toJS, container),
      );
      container.setProperty('ready'.toJS, Future.value(registration).toJS);
      var checks = 0;
      registration
        ..setProperty('waiting'.toJS, null)
        ..setProperty('installing'.toJS, null)
        ..setProperty(
          'update'.toJS,
          (() {
            checks++;
            return Future.value(registration).toJS;
          }).toJS,
        );
      await expectLater(updateAndRestart(), throwsStateError);
      expect(
        checks,
        1,
        reason: 'an old precache must not be reloaded as an update',
      );

      final listening = Completer<JSFunction>();
      var removed = 0;
      final installing = JSObject()
        ..setProperty('state'.toJS, 'installing'.toJS)
        ..setProperty(
          'addEventListener'.toJS,
          ((JSString type, JSFunction listener) {
            listening.complete(listener);
          }).toJS,
        )
        ..setProperty(
          'removeEventListener'.toJS,
          ((JSString type, JSFunction listener) {
            removed++;
          }).toJS,
        );
      final messages = <Object?>[];
      final waiting = JSObject()
        ..setProperty(
          'postMessage'.toJS,
          ((JSAny? message) {
            messages.add(message.dartify());
          }).toJS,
        );
      registration.setProperty('installing'.toJS, installing);
      final updating = updateAndRestart();
      final listener = await listening.future;
      expect(
        messages,
        isEmpty,
        reason: 'do not activate an unfinished release',
      );
      installing.setProperty('state'.toJS, 'installed'.toJS);
      registration.setProperty('waiting'.toJS, waiting);
      listener.callAsFunction(installing, web.Event('statechange'));
      await updating;
      expect(checks, 2);
      expect(messages, [
        {'type': 'SKIP_WAITING'},
      ]);
      expect(removed, 1);
      // An already downloaded release must also work without another network check.
      await updateAndRestart();
      expect(checks, 2);
      expect(messages, hasLength(2));
    },
  );
}
