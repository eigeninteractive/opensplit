//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

// ignore: unused_import
import 'dart:convert';
import 'package:opensplit_api/src/deserialize.dart';
import 'package:dio/dio.dart';

import 'package:opensplit_api/src/model/entry.dart';
import 'package:opensplit_api/src/model/entry_input.dart';
import 'package:opensplit_api/src/model/error.dart';

class EntriesApi {
  final Dio _dio;

  const EntriesApi(this._dio);

  /// Record, edit, delete or restore an expense, whole
  /// &#x60;baseSeq&#x60; must be the version stored now (null for a new expense), or the write is refused as &#x60;stale_base&#x60;: the expense is replaced whole, so a write composed on an older version would undo the edit in between. Sending the stored contents again is answered with the stored row, whatever the base.
  ///
  /// Parameters:
  /// * [groupId]
  /// * [entryId]
  /// * [entryInput]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [Entry] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<Entry>> putEntry({
    required String groupId,
    required String entryId,
    required EntryInput entryInput,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/groups/{groupId}/entries/{entryId}'
        .replaceAll(
          '{'
          r'groupId'
          '}',
          groupId.toString(),
        )
        .replaceAll(
          '{'
          r'entryId'
          '}',
          entryId.toString(),
        );
    final _options = Options(
      method: r'PUT',
      headers: <String, dynamic>{...?headers},
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookie',
            'keyName': 'better-auth.session_token',
            'where': '',
          },
          {'type': 'http', 'scheme': 'bearer', 'name': 'bearer'},
        ],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      _bodyData = jsonEncode(entryInput);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _options.compose(_dio.options, _path),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    Entry? _responseData;

    try {
      final rawData = _response.data;
      _responseData = rawData == null
          ? null
          : deserialize<Entry, Entry>(rawData, 'Entry', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<Entry>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }
}
