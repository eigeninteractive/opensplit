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

  /// Soft-delete an expense
  /// Deleting always moves money, so unlike a prose edit it must carry the exact version the device last saw. The row stays in the feed with &#x60;deletedAt&#x60; set; nothing here can remove it.
  ///
  /// Parameters:
  /// * [groupId]
  /// * [entryId]
  /// * [baseSeq]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [Entry] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<Entry>> deleteEntry({
    required String groupId,
    required String entryId,
    required int baseSeq,
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
      method: r'DELETE',
      headers: <String, dynamic>{...?headers},
      extra: <String, dynamic>{'secure': <Map<String, String>>[], ...?extra},
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{r'baseSeq': baseSeq};

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
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

  /// Put a deleted expense back
  ///
  ///
  /// Parameters:
  /// * [groupId]
  /// * [entryId]
  /// * [baseSeq]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [Entry] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<Entry>> restoreEntry({
    required String groupId,
    required String entryId,
    required int baseSeq,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/groups/{groupId}/entries/{entryId}/restore'
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
      method: r'POST',
      headers: <String, dynamic>{...?headers},
      extra: <String, dynamic>{'secure': <Map<String, String>>[], ...?extra},
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{r'baseSeq': baseSeq};

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
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

  /// Record or edit an expense, whole
  /// Whole rather than by column: an amount, its payers and its shares are one coherent fact. Send &#x60;baseSeq&#x60; to be told when somebody else has moved the money since you composed the edit — a stale base is refused only when applying the write would move money, so two people fixing a typo never arbitrate.
  ///
  /// Parameters:
  /// * [groupId]
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
  Future<Response<Entry>> upsertEntry({
    required String groupId,
    required EntryInput entryInput,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/groups/{groupId}/entries'.replaceAll(
      '{'
      r'groupId'
      '}',
      groupId.toString(),
    );
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{...?headers},
      extra: <String, dynamic>{'secure': <Map<String, String>>[], ...?extra},
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
