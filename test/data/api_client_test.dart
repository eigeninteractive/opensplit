import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

DioException _refusal(int status, String retry) {
  final request = RequestOptions(path: '/api/groups/g');
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
  group('reading a failed request', () {
    test('a server failure is retried, whatever its body says', () {
      final failure = ApiFailure.from(_refusal(500, 'permanent'));

      expect(failure.retry, api.Retry.transient);
      expect(failure.message, 'Something went wrong.');
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
