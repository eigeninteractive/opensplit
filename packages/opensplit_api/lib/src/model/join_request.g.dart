// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'join_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

JoinRequest _$JoinRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('JoinRequest', json, ($checkedConvert) {
      final val = JoinRequest(
        memberId: $checkedConvert('memberId', (v) => v as String?),
        displayName: $checkedConvert('displayName', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$JoinRequestToJson(JoinRequest instance) =>
    <String, dynamic>{
      'memberId': ?instance.memberId,
      'displayName': ?instance.displayName,
    };
