//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class IdentityApi {
  IdentityApi([ApiClient? apiClient])
      : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Attach Google to this session, or sign in with it
  ///
  /// Tries to link first, so the account id survives and nothing on the device has to move. Falls back to signing in only when the Google account provably belongs to somebody already, and only when allowSignIn says the cost has already been explained to the person.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [GoogleIdentityRequest] googleIdentityRequest (required):
  Future<Response> linkGoogleWithHttpInfo(
    GoogleIdentityRequest googleIdentityRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/identity/google';

    // ignore: prefer_final_locals
    Object? postBody = googleIdentityRequest;

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

  /// Attach Google to this session, or sign in with it
  ///
  /// Tries to link first, so the account id survives and nothing on the device has to move. Falls back to signing in only when the Google account provably belongs to somebody already, and only when allowSignIn says the cost has already been explained to the person.
  ///
  /// Parameters:
  ///
  /// * [GoogleIdentityRequest] googleIdentityRequest (required):
  Future<IdentityOutcome?> linkGoogle(
    GoogleIdentityRequest googleIdentityRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await linkGoogleWithHttpInfo(
      googleIdentityRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'IdentityOutcome',
      ) as IdentityOutcome;
    }
    return null;
  }

  /// Send a sign-in code, and say which flow it started
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [EmailStartRequest] emailStartRequest (required):
  Future<Response> startEmailSignInWithHttpInfo(
    EmailStartRequest emailStartRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/identity/email';

    // ignore: prefer_final_locals
    Object? postBody = emailStartRequest;

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

  /// Send a sign-in code, and say which flow it started
  ///
  /// Parameters:
  ///
  /// * [EmailStartRequest] emailStartRequest (required):
  Future<EmailStartResponse?> startEmailSignIn(
    EmailStartRequest emailStartRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await startEmailSignInWithHttpInfo(
      emailStartRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'EmailStartResponse',
      ) as EmailStartResponse;
    }
    return null;
  }

  /// Complete the flow that POST /identity/email started
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [EmailVerifyRequest] emailVerifyRequest (required):
  Future<Response> verifyEmailCodeWithHttpInfo(
    EmailVerifyRequest emailVerifyRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/identity/email/verify';

    // ignore: prefer_final_locals
    Object? postBody = emailVerifyRequest;

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

  /// Complete the flow that POST /identity/email started
  ///
  /// Parameters:
  ///
  /// * [EmailVerifyRequest] emailVerifyRequest (required):
  Future<IdentityOutcome?> verifyEmailCode(
    EmailVerifyRequest emailVerifyRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await verifyEmailCodeWithHttpInfo(
      emailVerifyRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'IdentityOutcome',
      ) as IdentityOutcome;
    }
    return null;
  }
}
