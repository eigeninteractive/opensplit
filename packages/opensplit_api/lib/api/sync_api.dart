//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class SyncApi {
  SyncApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Who I am, and which groups to ask
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> bootstrapWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/bootstrap';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Who I am, and which groups to ask
  Future<Bootstrap?> bootstrap({ Future<void>? abortTrigger, }) async {
    final response = await bootstrapWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Bootstrap',) as Bootstrap;
    
    }
    return null;
  }

  /// Everything that changed in one group since a cursor
  ///
  /// `limit` counts changes, not rows. Every row written by one call shares a sequence number and a page is only ever cut between numbers, so a device sees a whole write or none of it — it can never observe an expense whose shares have not arrived. Send `seq` back as `since` next time.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [int] since:
  ///
  /// * [int] limit:
  Future<Response> getChangesWithHttpInfo(String groupId, { int? since, int? limit, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/groups/{groupId}/changes'
      .replaceAll('{groupId}', groupId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (since != null) {
      queryParams.addAll(_queryParams('', 'since', since));
    }
    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Everything that changed in one group since a cursor
  ///
  /// `limit` counts changes, not rows. Every row written by one call shares a sequence number and a page is only ever cut between numbers, so a device sees a whole write or none of it — it can never observe an expense whose shares have not arrived. Send `seq` back as `since` next time.
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [int] since:
  ///
  /// * [int] limit:
  Future<ChangePage?> getChanges(String groupId, { int? since, int? limit, Future<void>? abortTrigger, }) async {
    final response = await getChangesWithHttpInfo(groupId, since: since, limit: limit, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'ChangePage',) as ChangePage;
    
    }
    return null;
  }
}
