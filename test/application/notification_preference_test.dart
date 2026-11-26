import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/application/local_providers.dart';
import 'package:opensplit/application/preferences_providers.dart';
import 'package:opensplit/application/push_providers.dart';
import 'package:opensplit/data/push/device_tokens.dart';
import 'package:opensplit/data/push/notification_preferences.dart';
import 'package:opensplit/data/push/push_service.dart';
import 'package:opensplit_api/opensplit_api.dart' show OpensplitApi;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a token refreshed during sign-out stays unregistered', () async {
    SharedPreferences.setMockInitialValues({notificationPreferenceKey: true});
    final preferences = await SharedPreferences.getInstance();
    final requests = <String>[];
    final dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request.method);
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: request,
              statusCode: 200,
              data: request.method == 'DELETE'
                  ? {'forgotten': true}
                  : {'token': 'device-token', 'platform': 'android'},
            ),
          );
        },
      ),
    );

    String? accountId = 'first-account';
    final container = ProviderContainer.test(
      overrides: [
        currentAccountIdProvider.overrideWith((ref) => accountId),
        deviceTokensProvider.overrideWithValue(
          DeviceTokens(OpensplitApi(dio: dio)),
        ),
        pushServiceProvider.overrideWithValue(_PushService()),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    final controller = container.read(notificationPreferenceProvider.notifier);
    await controller.register('device-token');

    final signingOut = Completer<void>();
    final finishSignOut = Completer<void>();
    final signOut = controller.releaseDeviceAndSignOut(() async {
      signingOut.complete();
      await finishSignOut.future;
      accountId = null;
      container.invalidate(currentAccountIdProvider);
    });
    await signingOut.future;
    final refresh = controller.register('refreshed-token');
    finishSignOut.complete();
    await Future.wait([signOut, refresh]);

    expect(requests, ['PUT', 'DELETE']);
    expect(container.read(notificationPreferenceProvider), isTrue);

    accountId = 'next-account';
    container.invalidate(currentAccountIdProvider);
    await controller.register('refreshed-token');
    expect(requests, ['PUT', 'DELETE', 'PUT']);
  });
}

class _PushService extends PushService {
  _PushService()
    : super(
        isEnabled: () => true,
        onWake: (_) async {},
        describe: (_) async => null,
        onTokenChanged: (_) async {},
        onOpenGroup: (_) {},
      );

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<String?> token() async => 'device-token';
}
