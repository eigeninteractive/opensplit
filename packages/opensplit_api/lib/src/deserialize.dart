import 'package:opensplit_api/src/model/account.dart';
import 'package:opensplit_api/src/model/account_deletion.dart';
import 'package:opensplit_api/src/model/category.dart';
import 'package:opensplit_api/src/model/change_page.dart';
import 'package:opensplit_api/src/model/currency.dart';
import 'package:opensplit_api/src/model/device.dart';
import 'package:opensplit_api/src/model/device_forgotten.dart';
import 'package:opensplit_api/src/model/email_start_request.dart';
import 'package:opensplit_api/src/model/email_start_response.dart';
import 'package:opensplit_api/src/model/email_verify_request.dart';
import 'package:opensplit_api/src/model/entry.dart';
import 'package:opensplit_api/src/model/entry_input.dart';
import 'package:opensplit_api/src/model/entry_snapshot.dart';
import 'package:opensplit_api/src/model/error.dart';
import 'package:opensplit_api/src/model/error_error.dart';
import 'package:opensplit_api/src/model/event.dart';
import 'package:opensplit_api/src/model/fx_backfill_request.dart';
import 'package:opensplit_api/src/model/fx_backfill_response.dart';
import 'package:opensplit_api/src/model/fx_page.dart';
import 'package:opensplit_api/src/model/fx_rate.dart';
import 'package:opensplit_api/src/model/google_identity_request.dart';
import 'package:opensplit_api/src/model/google_redirect.dart';
import 'package:opensplit_api/src/model/google_redirect_request.dart';
import 'package:opensplit_api/src/model/group.dart';
import 'package:opensplit_api/src/model/group_create.dart';
import 'package:opensplit_api/src/model/group_event_payload.dart';
import 'package:opensplit_api/src/model/group_ids.dart';
import 'package:opensplit_api/src/model/group_link.dart';
import 'package:opensplit_api/src/model/group_update.dart';
import 'package:opensplit_api/src/model/health.dart';
import 'package:opensplit_api/src/model/identity_outcome.dart';
import 'package:opensplit_api/src/model/invite.dart';
import 'package:opensplit_api/src/model/join_request.dart';
import 'package:opensplit_api/src/model/joined.dart';
import 'package:opensplit_api/src/model/link_event_payload.dart';
import 'package:opensplit_api/src/model/link_preview.dart';
import 'package:opensplit_api/src/model/link_revocation.dart';
import 'package:opensplit_api/src/model/live_link.dart';
import 'package:opensplit_api/src/model/member.dart';
import 'package:opensplit_api/src/model/member_create.dart';
import 'package:opensplit_api/src/model/member_event_payload.dart';
import 'package:opensplit_api/src/model/member_update.dart';
import 'package:opensplit_api/src/model/money_row.dart';
import 'package:opensplit_api/src/model/payer.dart';
import 'package:opensplit_api/src/model/placeholder.dart';
import 'package:opensplit_api/src/model/placeholder_list.dart';
import 'package:opensplit_api/src/model/profile.dart';
import 'package:opensplit_api/src/model/profile_list.dart';
import 'package:opensplit_api/src/model/profile_lookup.dart';
import 'package:opensplit_api/src/model/profile_page.dart';
import 'package:opensplit_api/src/model/profile_update.dart';
import 'package:opensplit_api/src/model/push_data.dart';
import 'package:opensplit_api/src/model/reference.dart';
import 'package:opensplit_api/src/model/session.dart';
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
    case 'AccountDeletion':
      return AccountDeletion.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Category':
      return Category.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ChangePage':
      return ChangePage.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Currency':
      return Currency.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Device':
      return Device.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'DeviceForgotten':
      return DeviceForgotten.fromJson(value as Map<String, dynamic>)
          as ReturnType;
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
    case 'EntrySnapshot':
      return EntrySnapshot.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Error':
      return Error.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ErrorCode':
    case 'ErrorError':
      return ErrorError.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Event':
      return Event.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'EventKind':
    case 'FxBackfillRequest':
      return FxBackfillRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'FxBackfillResponse':
      return FxBackfillResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'FxPage':
      return FxPage.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'FxRate':
      return FxRate.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'GoogleIdentityRequest':
      return GoogleIdentityRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'GoogleRedirect':
      return GoogleRedirect.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'GoogleRedirectRequest':
      return GoogleRedirectRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Group':
      return Group.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'GroupCreate':
      return GroupCreate.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'GroupEventPayload':
      return GroupEventPayload.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'GroupIds':
      return GroupIds.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'GroupLink':
      return GroupLink.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'GroupUpdate':
      return GroupUpdate.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Health':
      return Health.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'IdentityOutcome':
      return IdentityOutcome.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'IdentityOutcomeKind':
    case 'Invite':
      return Invite.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'JoinRequest':
      return JoinRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Joined':
      return Joined.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'LinkEventPayload':
      return LinkEventPayload.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'LinkKind':
    case 'LinkPreview':
      return LinkPreview.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'LinkRevocation':
      return LinkRevocation.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'LiveLink':
      return LiveLink.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Member':
      return Member.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'MemberCreate':
      return MemberCreate.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'MemberEventPayload':
      return MemberEventPayload.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'MemberUpdate':
      return MemberUpdate.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'MoneyRow':
      return MoneyRow.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Payer':
      return Payer.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Placeholder':
      return Placeholder.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'PlaceholderList':
      return PlaceholderList.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Platform':
    case 'Profile':
      return Profile.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ProfileList':
      return ProfileList.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ProfileLookup':
      return ProfileLookup.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ProfilePage':
      return ProfilePage.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ProfileUpdate':
      return ProfileUpdate.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'PushData':
      return PushData.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Reference':
      return Reference.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Retry':
    case 'Session':
      return Session.fromJson(value as Map<String, dynamic>) as ReturnType;
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
