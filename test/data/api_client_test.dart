import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

DioException _refusal(int status, String retry) {
  final request = RequestOptions(path: '/groups/g');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: request,
      statusCode: status,
      data: {
        'error': {
          'code': 'internal',
          'message': 'Something went wrong.',
          'retry': retry,
        },
      },
    ),
  );
}

void main() {
  for (final origin in [
    'https://ledger.example.org',
    'https://ledger.example.org/',
  ]) {
    test('generated requests use the contract base URL from $origin', () async {
      final client = buildApiClient(baseUrl: origin, token: 'session-token');
      addTearDown(() => client.dio.close());
      late RequestOptions sent;
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            sent = request;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: {
                  'ok': true,
                  'service': 'opensplit',
                  'now': '2026-10-14T00:00:00Z',
                },
              ),
            );
          },
        ),
      );

      final health = await fetch(client.getMetaApi().health());

      expect(sent.path, '/health');
      expect(
        sent.uri.toString(),
        'https://ledger.example.org${api.OpensplitApi.basePath}/health',
      );
      expect(health.ok, isTrue);
    });
  }

  group('reading a failed request', () {
    test('a server failure is retried, whatever its body says', () {
      final failure = ApiFailure.from(_refusal(500, 'permanent'));

      expect(failure.retry, api.Retry.transient);
      expect(failure.message, 'Something went wrong.');
    });

    test('a request no server answered reads as unreachable', () {
      final request = RequestOptions(path: '/groups/g');
      final offline = DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );

      expect(ApiFailure.from(offline).unreachable, isTrue);
      expect(isUnreachable(ApiFailure.from(offline)), isTrue);
      expect(isUnreachable(offline), isTrue);
      expect(isUnreachable(ApiFailure.from(_refusal(500, 'transient'))), false);
      expect(isUnreachable(StateError('not a request')), isFalse);
    });

    test('a refusal keeps the retry the server gave it', () {
      expect(ApiFailure.from(_refusal(409, 'stale')).retry, api.Retry.stale);
      expect(
        ApiFailure.from(_refusal(403, 'permanent')).retry,
        api.Retry.permanent,
      );
    });
  });
}
