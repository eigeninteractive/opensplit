import 'package:opensplit_api/src/model/account.dart';
import 'package:opensplit_api/src/model/bootstrap.dart';
import 'package:opensplit_api/src/model/change_page.dart';
import 'package:opensplit_api/src/model/email_start_request.dart';
import 'package:opensplit_api/src/model/email_start_response.dart';
import 'package:opensplit_api/src/model/email_verify_request.dart';
import 'package:opensplit_api/src/model/entry.dart';
import 'package:opensplit_api/src/model/entry_input.dart';
import 'package:opensplit_api/src/model/error.dart';
import 'package:opensplit_api/src/model/error_error.dart';
import 'package:opensplit_api/src/model/event.dart';
import 'package:opensplit_api/src/model/google_identity_request.dart';
import 'package:opensplit_api/src/model/group.dart';
import 'package:opensplit_api/src/model/group_create.dart';
import 'package:opensplit_api/src/model/group_patch.dart';
import 'package:opensplit_api/src/model/health.dart';
import 'package:opensplit_api/src/model/identity_outcome.dart';
import 'package:opensplit_api/src/model/identity_outcome_one_of.dart';
import 'package:opensplit_api/src/model/identity_outcome_one_of1.dart';
import 'package:opensplit_api/src/model/member.dart';
import 'package:opensplit_api/src/model/member_create.dart';
import 'package:opensplit_api/src/model/member_patch.dart';
import 'package:opensplit_api/src/model/payer.dart';
import 'package:opensplit_api/src/model/share.dart';

final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

ReturnType deserialize<ReturnType, BaseType>(
  dynamic value,
  String targetType, {
  bool growable = true,
}) {
  switch (targetType) {
    case 'String':
      return '$value' as ReturnType;
    case 'int':
      return (value is int ? value : int.parse('$value')) as ReturnType;
    case 'bool':
      if (value is bool) {
        return value as ReturnType;
      }
      final valueString = '$value'.toLowerCase();
      return (valueString == 'true' || valueString == '1') as ReturnType;
    case 'double':
      return (value is double ? value : double.parse('$value')) as ReturnType;
    case 'Account':
      return Account.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Bootstrap':
      return Bootstrap.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ChangePage':
      return ChangePage.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'EmailFlow':
    case 'EmailStartRequest':
      return EmailStartRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'EmailStartResponse':
      return EmailStartResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'EmailVerifyRequest':
      return EmailVerifyRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Entry':
      return Entry.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'EntryInput':
      return EntryInput.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'EntryKind':
    case 'Error':
      return Error.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ErrorError':
      return ErrorError.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Event':
      return Event.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'EventKind':
    case 'GoogleIdentityRequest':
      return GoogleIdentityRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Group':
      return Group.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'GroupCreate':
      return GroupCreate.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'GroupPatch':
      return GroupPatch.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Health':
      return Health.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'IdentityOutcome':
      return IdentityOutcome.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'IdentityOutcomeOneOf':
      return IdentityOutcomeOneOf.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'IdentityOutcomeOneOf1':
      return IdentityOutcomeOneOf1.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Member':
      return Member.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'MemberCreate':
      return MemberCreate.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'MemberPatch':
      return MemberPatch.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Payer':
      return Payer.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Retry':
    case 'Share':
      return Share.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'SplitKind':
    default:
      RegExpMatch? match;

      if (value is List && (match = _regList.firstMatch(targetType)) != null) {
        targetType = match![1]!; // ignore: parameter_assignments
        return value
                .map<BaseType>(
                  (dynamic v) => deserialize<BaseType, BaseType>(
                    v,
                    targetType,
                    growable: growable,
                  ),
                )
                .toList(growable: growable)
            as ReturnType;
      }
      if (value is Set && (match = _regSet.firstMatch(targetType)) != null) {
        targetType = match![1]!; // ignore: parameter_assignments
        return value
                .map<BaseType>(
                  (dynamic v) => deserialize<BaseType, BaseType>(
                    v,
                    targetType,
                    growable: growable,
                  ),
                )
                .toSet()
            as ReturnType;
      }
      if (value is Map && (match = _regMap.firstMatch(targetType)) != null) {
        targetType = match![1]!.trim(); // ignore: parameter_assignments
        return Map<String, BaseType>.fromIterables(
              value.keys as Iterable<String>,
              value.values.map(
                (dynamic v) => deserialize<BaseType, BaseType>(
                  v,
                  targetType,
                  growable: growable,
                ),
              ),
            )
            as ReturnType;
      }
      break;
  }
  throw Exception('Cannot deserialize');
}
