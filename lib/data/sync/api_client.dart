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

  return api.OpensplitApi(dio: dio);
}
