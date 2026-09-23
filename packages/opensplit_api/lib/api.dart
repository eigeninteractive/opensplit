//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

library openapi.api;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

part 'api_client.dart';
part 'api_helper.dart';
part 'api_exception.dart';
part 'auth/authentication.dart';
part 'auth/api_key_auth.dart';
part 'auth/oauth.dart';
part 'auth/http_basic_auth.dart';
part 'auth/http_bearer_auth.dart';

part 'api/entries_api.dart';
part 'api/groups_api.dart';
part 'api/identity_api.dart';
part 'api/meta_api.dart';
part 'api/sync_api.dart';

part 'model/account.dart';
part 'model/bootstrap.dart';
part 'model/change_page.dart';
part 'model/email_flow.dart';
part 'model/email_start_request.dart';
part 'model/email_start_response.dart';
part 'model/email_verify_request.dart';
part 'model/entry.dart';
part 'model/entry_input.dart';
part 'model/entry_kind.dart';
part 'model/error.dart';
part 'model/error_error.dart';
part 'model/event.dart';
part 'model/event_kind.dart';
part 'model/google_identity_request.dart';
part 'model/group.dart';
part 'model/group_create.dart';
part 'model/group_patch.dart';
part 'model/health.dart';
part 'model/identity_outcome.dart';
part 'model/identity_outcome_one_of.dart';
part 'model/identity_outcome_one_of1.dart';
part 'model/member.dart';
part 'model/member_create.dart';
part 'model/member_patch.dart';
part 'model/payer.dart';
part 'model/retry.dart';
part 'model/share.dart';
part 'model/split_kind.dart';


/// An [ApiClient] instance that uses the default values obtained from
/// the OpenAPI specification file.
var defaultApiClient = ApiClient();

const _delimiters = {'csv': ',', 'ssv': ' ', 'tsv': '\t', 'pipes': '|'};
const _dateEpochMarker = 'epoch';
const _deepEquality = DeepCollectionEquality();
final _dateFormatter = DateFormat('yyyy-MM-dd');
final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

bool _isEpochMarker(String? pattern) => pattern == _dateEpochMarker || pattern == '/$_dateEpochMarker/';
