//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class EntriesApi {
  EntriesApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Soft-delete an expense
  ///
  /// Deleting always moves money, so unlike a prose edit it must carry the exact version the device last saw. The row stays in the feed with `deletedAt` set; nothing here can remove it.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [String] entryId (required):
  ///
  /// * [int] baseSeq:
  Future<Response> deleteEntryWithHttpInfo(String groupId, String entryId, { int? baseSeq, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/groups/{groupId}/entries/{entryId}'
      .replaceAll('{groupId}', groupId)
      .replaceAll('{entryId}', entryId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (baseSeq != null) {
      queryParams.addAll(_queryParams('', 'baseSeq', baseSeq));
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Soft-delete an expense
  ///
  /// Deleting always moves money, so unlike a prose edit it must carry the exact version the device last saw. The row stays in the feed with `deletedAt` set; nothing here can remove it.
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [String] entryId (required):
  ///
  /// * [int] baseSeq:
  Future<Entry?> deleteEntry(String groupId, String entryId, { int? baseSeq, Future<void>? abortTrigger, }) async {
    final response = await deleteEntryWithHttpInfo(groupId, entryId, baseSeq: baseSeq, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Entry',) as Entry;
    
    }
    return null;
  }

  /// Put a deleted expense back
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [String] entryId (required):
  ///
  /// * [int] baseSeq:
  Future<Response> restoreEntryWithHttpInfo(String groupId, String entryId, { int? baseSeq, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/groups/{groupId}/entries/{entryId}/restore'
      .replaceAll('{groupId}', groupId)
      .replaceAll('{entryId}', entryId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (baseSeq != null) {
      queryParams.addAll(_queryParams('', 'baseSeq', baseSeq));
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Put a deleted expense back
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [String] entryId (required):
  ///
  /// * [int] baseSeq:
  Future<Entry?> restoreEntry(String groupId, String entryId, { int? baseSeq, Future<void>? abortTrigger, }) async {
    final response = await restoreEntryWithHttpInfo(groupId, entryId, baseSeq: baseSeq, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Entry',) as Entry;
    
    }
    return null;
  }

  /// Record or edit an expense, whole
  ///
  /// Whole rather than by column: an amount, its payers and its shares are one coherent fact. Send `baseSeq` to be told when somebody else has moved the money since you composed the edit — a stale base is refused only when applying the write would move money, so two people fixing a typo never arbitrate.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [EntryInput] entryInput (required):
  Future<Response> upsertEntryWithHttpInfo(String groupId, EntryInput entryInput, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/groups/{groupId}/entries'
      .replaceAll('{groupId}', groupId);

    // ignore: prefer_final_locals
    Object? postBody = entryInput;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Record or edit an expense, whole
  ///
  /// Whole rather than by column: an amount, its payers and its shares are one coherent fact. Send `baseSeq` to be told when somebody else has moved the money since you composed the edit — a stale base is refused only when applying the write would move money, so two people fixing a typo never arbitrate.
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [EntryInput] entryInput (required):
  Future<Entry?> upsertEntry(String groupId, EntryInput entryInput, { Future<void>? abortTrigger, }) async {
    final response = await upsertEntryWithHttpInfo(groupId, entryInput, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Entry',) as Entry;
    
    }
    return null;
  }
}
