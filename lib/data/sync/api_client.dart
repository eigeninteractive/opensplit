import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:opensplit_api/opensplit_api.dart' as api;

/// The security scheme name the contract gives the bearer token.
const bearerScheme = 'bearer';

/// The client every backend request goes through.
api.OpensplitApi buildApiClient({
  required String baseUrl,
  String? token,
  Duration timeout = const Duration(seconds: 20),
}) {
  final client = api.OpensplitApi(
    dio: Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        extra: kIsWeb ? const {'withCredentials': true} : const {},
      ),
    ),
  );
  if (token != null) client.setBearerAuth(bearerScheme, token);
  return client;
}

/// A request the server refused, or that never got an answer.
class ApiFailure implements Exception {
  const ApiFailure(this.message, {required this.retry, this.code});

  /// Reads the `{error: {code, message, retry}}` envelope off a failed request.
  factory ApiFailure.from(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final envelope = body is Map<String, dynamic> ? _decode(body) : null;
    if (envelope != null) {
      return ApiFailure(
        envelope.message,
        code: envelope.code,
        retry: envelope.retry,
      );
    }
    return ApiFailure(
      status == null
          ? error.message ?? 'Could not reach the server.'
          : 'The server refused the request ($status).',
      retry: status == null || status >= 500
          ? api.Retry.transient
          : api.Retry.permanent,
    );
  }

  final String message;
  final api.Retry retry;

  /// Null when no server answered in the expected shape.
  final api.ErrorCode? code;

  static api.ErrorError? _decode(Map<String, dynamic> body) {
    try {
      return api.Error.fromJson(body).error;
    } on Object {
      return null;
    }
  }

  @override
  String toString() => 'ApiFailure(${code?.value ?? retry.value}): $message';
}

/// The body of a successful call, or an [ApiFailure].
Future<T> fetch<T>(Future<Response<T>> request) async {
  try {
    final body = (await request).data;
    if (body == null) {
      throw const ApiFailure(
        'The server answered with no body.',
        retry: api.Retry.transient,
      );
    }
    return body;
  } on DioException catch (error) {
    throw ApiFailure.from(error);
  }
}

/// A call whose success has no body worth reading, or an [ApiFailure].
Future<void> send(Future<Response<void>> request) async {
  try {
    await request;
  } on DioException catch (error) {
    throw ApiFailure.from(error);
  }
}
