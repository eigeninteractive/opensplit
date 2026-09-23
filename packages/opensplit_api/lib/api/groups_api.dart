//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class GroupsApi {
  GroupsApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Add somebody who has never opened the app
  ///
  /// A placeholder is a full member: they can pay, hold a balance and be settled with. Claiming an invite later sets one column and moves no money.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [MemberCreate] memberCreate (required):
  Future<Response> addMemberWithHttpInfo(String groupId, MemberCreate memberCreate, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/groups/{groupId}/members'
      .replaceAll('{groupId}', groupId);

    // ignore: prefer_final_locals
    Object? postBody = memberCreate;

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

  /// Add somebody who has never opened the app
  ///
  /// A placeholder is a full member: they can pay, hold a balance and be settled with. Claiming an invite later sets one column and moves no money.
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [MemberCreate] memberCreate (required):
  Future<Member?> addMember(String groupId, MemberCreate memberCreate, { Future<void>? abortTrigger, }) async {
    final response = await addMemberWithHttpInfo(groupId, memberCreate, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Member',) as Member;
    
    }
    return null;
  }

  /// Make a group, and its creator's place in it
  ///
  /// Idempotent for the account that made it, so a retry whose response was lost returns the same group rather than refusing.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [GroupCreate] groupCreate (required):
  Future<Response> createGroupWithHttpInfo(GroupCreate groupCreate, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/groups';

    // ignore: prefer_final_locals
    Object? postBody = groupCreate;

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

  /// Make a group, and its creator's place in it
  ///
  /// Idempotent for the account that made it, so a retry whose response was lost returns the same group rather than refusing.
  ///
  /// Parameters:
  ///
  /// * [GroupCreate] groupCreate (required):
  Future<Group?> createGroup(GroupCreate groupCreate, { Future<void>? abortTrigger, }) async {
    final response = await createGroupWithHttpInfo(groupCreate, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Group',) as Group;
    
    }
    return null;
  }

  /// Rename, archive or change a setting
  ///
  /// A patch, not a whole row. There are no fields for `id`, `createdAt` or `createdBy`, which is why nothing needs to forbid rewriting them.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [GroupPatch] groupPatch (required):
  Future<Response> updateGroupWithHttpInfo(String groupId, GroupPatch groupPatch, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/groups/{groupId}'
      .replaceAll('{groupId}', groupId);

    // ignore: prefer_final_locals
    Object? postBody = groupPatch;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'PATCH',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Rename, archive or change a setting
  ///
  /// A patch, not a whole row. There are no fields for `id`, `createdAt` or `createdBy`, which is why nothing needs to forbid rewriting them.
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [GroupPatch] groupPatch (required):
  Future<Group?> updateGroup(String groupId, GroupPatch groupPatch, { Future<void>? abortTrigger, }) async {
    final response = await updateGroupWithHttpInfo(groupId, groupPatch, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Group',) as Group;
    
    }
    return null;
  }

  /// Change a name, a payment handle, or whether somebody is still here
  ///
  /// Your own row and any placeholder are editable; another account holder's are not — including by whoever made the group. Leaving is always yours to do; removing somebody else requires them to be settled in every currency.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [String] memberId (required):
  ///
  /// * [MemberPatch] memberPatch (required):
  Future<Response> updateMemberWithHttpInfo(String groupId, String memberId, MemberPatch memberPatch, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/groups/{groupId}/members/{memberId}'
      .replaceAll('{groupId}', groupId)
      .replaceAll('{memberId}', memberId);

    // ignore: prefer_final_locals
    Object? postBody = memberPatch;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'PATCH',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Change a name, a payment handle, or whether somebody is still here
  ///
  /// Your own row and any placeholder are editable; another account holder's are not — including by whoever made the group. Leaving is always yours to do; removing somebody else requires them to be settled in every currency.
  ///
  /// Parameters:
  ///
  /// * [String] groupId (required):
  ///
  /// * [String] memberId (required):
  ///
  /// * [MemberPatch] memberPatch (required):
  Future<Member?> updateMember(String groupId, String memberId, MemberPatch memberPatch, { Future<void>? abortTrigger, }) async {
    final response = await updateMemberWithHttpInfo(groupId, memberId, memberPatch, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Member',) as Member;
    
    }
    return null;
  }
}
