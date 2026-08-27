import 'dart:io';

import 'package:test/test.dart';

import '../../tool/build_web.dart';

void main() {
  late Directory output;
  final config = <String, dynamic>{
    'WEB_FCM_API_KEY': 'test-key',
    'WEB_FCM_APP_ID': 'test-app',
    'FCM_SENDER_ID': '123',
    'FCM_PROJECT_ID': 'test-project',
  };

  void fixture({String main = 'release-one'}) {
    for (final path in [
      'app/index.html',
      'app/flutter_bootstrap.js',
      'app/sqlite3.wasm',
      'app/drift_worker.js',
      'app/main.dart.wasm',
      'app/canvaskit/canvaskit.wasm',
      'icons/Icon-192.png',
      'index.html',
      'terms/index.html',
    ]) {
      final file = File('${output.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(path);
    }
    File('${output.path}/app/main.dart.js').writeAsStringSync(main);
    File('web/sw.js').copySync('${output.path}/app/sw.js');
    File(
      'web/firebase-messaging-sw.js',
    ).copySync('${output.path}/app/firebase-messaging-sw.js');
  }

  setUp(() => output = Directory.systemTemp.createTempSync('opensplit-web-'));
  tearDown(() => output.deleteSync(recursive: true));

  test('precache covers the full client but not marketing or legal pages', () {
    fixture();
    final id = finalizeWebBundle(output, config, buildId: 'test-build');
    final worker = File('${output.path}/app/sw.js').readAsStringSync();

    expect(worker, contains(id));
    for (final path in [
      'main.dart.js',
      'main.dart.wasm',
      'sqlite3.wasm',
      'drift_worker.js',
      'canvaskit/canvaskit.wasm',
      '/icons/Icon-192.png',
    ]) {
      expect(worker, contains('"$path"'));
    }
    expect(worker, isNot(contains('terms/index.html')));
    expect(worker, isNot(contains('"/index.html"')));
    expect(worker, isNot(contains('__OPEN_SPLIT_')));
  });

  test('cache identity changes with content even at the same commit', () {
    fixture();
    final first = finalizeWebBundle(output, config, buildId: 'test-build');
    fixture();
    expect(finalizeWebBundle(output, config, buildId: 'test-build'), first);
    fixture(main: 'release-two');
    expect(
      finalizeWebBundle(output, config, buildId: 'test-build'),
      isNot(first),
    );
  });

  test('an incomplete app cannot be packaged as offline capable', () {
    fixture();
    File('${output.path}/app/sqlite3.wasm').deleteSync();
    expect(
      () => finalizeWebBundle(output, config, buildId: 'test-build'),
      throwsStateError,
    );
  });

  test('invalid release ids cannot be injected into JavaScript', () {
    fixture();
    expect(
      () => finalizeWebBundle(output, config, buildId: "malicious';"),
      throwsFormatException,
    );
  });
}
