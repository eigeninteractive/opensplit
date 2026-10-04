// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PullRequest _$PullRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PullRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['groups', 'limit']);
      final val = PullRequest(
        groups: $checkedConvert(
          'groups',
          (v) => (v as List<dynamic>)
              .map((e) => GroupCursor.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        limit: $checkedConvert('limit', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$PullRequestToJson(PullRequest instance) =>
    <String, dynamic>{
      'groups': instance.groups.map((e) => e.toJson()).toList(),
      'limit': instance.limit,
    };
