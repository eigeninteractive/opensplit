import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/platform/app_update_service.dart';

class _UpdateService extends AppUpdateService {
  int storeVisits = 0;
  @override
  bool get isSupported => true;
  @override
  Future<void> openStoreListing() async {
    storeVisits++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.ffuf.in_app_update/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _UpdateService service;
  late List<String> calls;
  var available = 2;
  var allowed = true;
  String? failure;
  var checkFails = false;
  setUp(() {
    service = _UpdateService();
    calls = [];
    available = 2;
    allowed = true;
    failure = null;
    checkFails = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'checkForUpdate') {
        if (checkFails) throw PlatformException(code: 'UNAVAILABLE');
        return {
          'updateAvailability': available,
          'immediateAllowed': allowed,
          'flexibleAllowed': true,
          'availableVersionCode': 100,
          'installStatus': 0,
          'packageName': 'com.eigeninteractive.opensplit',
          'updatePriority': 0,
        };
      }
      if (failure != null) throw PlatformException(code: failure!);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('required update uses immediate flow regardless of priority', () async {
    await service.updateRequired();
    expect(calls, ['checkForUpdate', 'performImmediateUpdate']);
    expect(service.storeVisits, 0);
  });
  test('resumes an immediate update already in progress', () async {
    available = 3;
    allowed = false;
    await service.updateRequired();
    expect(calls, ['checkForUpdate', 'performImmediateUpdate']);
    expect(service.storeVisits, 0);
  });
  test('canceling keeps the gate without opening a second prompt', () async {
    failure = 'USER_DENIED_UPDATE';
    await service.updateRequired();
    expect(service.storeVisits, 0);
  });
  for (final scenario in [
    'unavailable',
    'not allowed',
    'check failed',
    'install failed',
  ]) {
    test('$scenario falls back to the store', () async {
      switch (scenario) {
        case 'unavailable':
          available = 1;
        case 'not allowed':
          allowed = false;
        case 'check failed':
          checkFails = true;
        case 'install failed':
          failure = 'IN_APP_UPDATE_FAILED';
      }
      await service.updateRequired();
      expect(service.storeVisits, 1);
    });
  }
}
