import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:shared_preferences/shared_preferences.dart';

/// The security scheme name the contract gives the bearer token.
const bearerScheme = 'bearer';

/// The client every backend request goes through.
///
/// [baseUrl] is the backend origin. The generated contract owns its API path.
api.OpensplitApi buildApiClient({
  required String baseUrl,
  String? token,
  ApiAccess? access,
  Duration timeout = const Duration(seconds: 20),
}) {
  final endpoint = Uri.parse(baseUrl).resolve(api.OpensplitApi.basePath);
  final client = api.OpensplitApi(
    dio: Dio(
      BaseOptions(
        baseUrl: endpoint.toString(),
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        extra: kIsWeb ? const {'withCredentials': true} : const {},
      ),
    ),
  );
  if (access != null) {
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (access.updateRequired) {
            handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.cancel,
                error: const ApiFailure.updateRequired(),
              ),
            );
          } else {
            handler.next(request);
          }
        },
        onResponse: (response, handler) {
          if (access.updateRequired) {
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                type: DioExceptionType.cancel,
                error: const ApiFailure.updateRequired(),
              ),
            );
          } else {
            handler.next(response);
          }
        },
        onError: (error, handler) {
          if (ApiFailure.from(error).isUpdateRequired) access.requireUpdate();
          handler.next(error);
        },
      ),
    );
  }
  if (token != null) client.setBearerAuth(bearerScheme, token);
  return client;
}

/// Whether this running build can still write to the server.
///
/// Retirement is final: only installing a compatible app restores editing.
/// The restriction belongs to the API contract, shared across accounts.
class ApiAccess {
  ApiAccess() : _updateRequired = false, _remember = null;

  ApiAccess._(this._updateRequired, this._remember);

  /// Remembers retirement across offline launches of the same API contract.
  ///
  /// A compatible build has a new API base and therefore a different key.
  factory ApiAccess.persisted(
    SharedPreferences preferences, {
    required String baseUrl,
  }) {
    final endpoint = Uri.parse(baseUrl).resolve(api.OpensplitApi.basePath);
    final key = 'opensplit.retiredApi.$endpoint';
    return ApiAccess._(
      preferences.getBool(key) ?? false,
      () => preferences.setBool(key, true),
    );
  }

  final _changes = StreamController<void>.broadcast(sync: true);

  /// Announces retirement while the current restriction stays synchronously readable.
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();

  final Future<bool> Function()? _remember;
  bool _updateRequired;

  /// True after the server has retired this running build’s API.
  bool get updateRequired => _updateRequired;

  /// Latches retirement; only a build using a supported contract can edit.
  void requireUpdate() {
    if (_updateRequired) return;
    _updateRequired = true;
    unawaited(_saveRetirement());
    _changes.add(null);
  }

  Future<void> _saveRetirement() async {
    try {
      await _remember?.call();
    } catch (error, stackTrace) {
      developer.log(
        'Could not remember API retirement',
        name: 'opensplit.update',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stops a local transaction before it can commit a new queued edit.
  void requireWritable() {
    if (_updateRequired) throw const ApiFailure.updateRequired();
  }
}

/// A request the server refused, or that never got an answer.
class ApiFailure implements Exception {
  const ApiFailure(
    this.message, {
    required this.retry,
    this.code,
    this.unreachable = false,
  });

  const ApiFailure.updateRequired()
    : this(
        'Update OpenSplit to make changes. Saved data is still available.',
        retry: api.Retry.permanent,
        code: api.ErrorCode.updateRequired,
      );

  /// Retirement stops sync without rejecting the pending financial change.
  bool get isUpdateRequired => code == api.ErrorCode.updateRequired;

  /// Reads the `{error: {code, message, retry}}` envelope off a failed request.
  factory ApiFailure.from(DioException error) {
    if (error.error case final ApiFailure failure) return failure;
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final envelope = body is Map<String, dynamic> ? _decode(body) : null;
    if (envelope != null) {
      return ApiFailure(
        envelope.message,
        code: envelope.code,
        // A server failure says nothing about whether the same request would
        // succeed, whatever its body claims; a write told otherwise would sit
        // set aside until somebody retried it by hand.
        retry: status != null && status >= 500
            ? api.Retry.transient
            : envelope.retry,
      );
    }
    return ApiFailure(
      status == null
          ? error.message ?? 'Could not reach the server.'
          : 'The server refused the request ($status).',
      retry: status == null || status >= 500
          ? api.Retry.transient
          : api.Retry.permanent,
      unreachable: _neverAnswered(error),
    );
  }

  final String message;
  final api.Retry retry;

  /// Null when no server answered in the expected shape.
  final api.ErrorCode? code;

  /// Whether the request never reached a server that answered: the device is
  /// offline, or the server is out of reach from where it is.
  final bool unreachable;

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

/// Whether [error] means no server answered at all, as opposed to a server
/// that answered and refused.
///
/// Judged by the request itself rather than by the device's network
/// interfaces, which report a captive portal or a dead Wi-Fi as connected.
bool isUnreachable(Object? error) => switch (error) {
  ApiFailure(:final unreachable) => unreachable,
  DioException() => _neverAnswered(error),
  _ => false,
};

bool _neverAnswered(DioException error) =>
    error.response == null && error.type != DioExceptionType.cancel;
