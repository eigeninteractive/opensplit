import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:opensplit_api/opensplit_api.dart' as api;

/// Where the session token comes from, when one is needed.
///
/// An abstraction rather than a direct dependency on the auth service, because
/// the two have different lifetimes: the HTTP client is built once and lives
/// as long as the app, while the token behind it is replaced on every sign-in,
/// link and refresh. Asking for it per request is what keeps a stale one from
/// being baked into an interceptor at construction.
typedef SessionToken = Future<String?> Function();

/// The HTTP client every request to the backend goes through.
///
/// ## One session, two transports
///
/// The token is the same value on both platforms; how it travels is not, and
/// the difference is forced rather than chosen.
///
/// On the web the app and the API are one origin, so the session is a
/// first-party `HttpOnly` cookie. JavaScript cannot read it, which means a
/// compromised dependency cannot steal it — and `withCredentials` is what
/// makes the browser attach it. Nothing here adds a header.
///
/// On Android there is no cookie jar a background isolate can reach, so the
/// same session travels as a bearer token this interceptor attaches.
api.OpensplitApi buildApiClient({
  required String baseUrl,
  required SessionToken token,
  Duration timeout = const Duration(seconds: 20),
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      // The generated client parses the body itself, and a refusal has a body
      // worth reading — `error.retry` is what the outbox acts on. Letting Dio
      // throw on any non-2xx is right; discarding the body with it is not.
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
      extra: kIsWeb ? const {'withCredentials': true} : const {},
    ),
  );

  if (!kIsWeb) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final value = await token();
          if (value != null && value.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $value';
          }
          handler.next(options);
        },
      ),
    );
  }

  dio.interceptors.add(_IsoDatesInQueryStrings());

  return api.OpensplitApi(dio: dio);
}

/// Writes `T` where Dart writes a space.
///
/// Dio builds a query string by calling `toString()` on anything that is not
/// already a String, and `DateTime.toString()` is not ISO-8601: it separates
/// the date from the time with a space rather than a `T`. So a cursor the
/// server had just issued came back to it as `2026-09-24 11:38:10.397Z` and
/// was refused as malformed — correctly, because that is not a timestamp.
///
/// Fixed here rather than at the call sites because the call sites are
/// generated: every `DateTime` query parameter in the client has this problem,
/// including the ones phase 5 has not written yet.
///
/// `onRequest` is early enough. Dio composes the URI from `queryParameters`
/// inside `fetch`, which runs after every request interceptor.
class _IsoDatesInQueryStrings extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.queryParameters = {
      for (final entry in options.queryParameters.entries)
        entry.key: switch (entry.value) {
          final DateTime at => at.toUtc().toIso8601String(),
          final Object? other => other,
        },
    };
    handler.next(options);
  }
}
