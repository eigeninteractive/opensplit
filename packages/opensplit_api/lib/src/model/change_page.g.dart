// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'change_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChangePage _$ChangePageFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ChangePage', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'groupId',
          'seq',
          'hasMore',
          'group',
          'members',
          'entries',
          'events',
          'purgedAt',
        ],
      );
      final val = ChangePage(
        groupId: $checkedConvert('groupId', (v) => v as String),
        seq: $checkedConvert('seq', (v) => (v as num).toInt()),
        hasMore: $checkedConvert('hasMore', (v) => v as bool),
        group: $checkedConvert(
          'group',
          (v) => v == null ? null : Group.fromJson(v as Map<String, dynamic>),
        ),
        members: $checkedConvert(
          'members',
          (v) => (v as List<dynamic>)
              .map((e) => Member.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        entries: $checkedConvert(
          'entries',
          (v) => (v as List<dynamic>)
              .map((e) => Entry.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        events: $checkedConvert(
          'events',
          (v) => (v as List<dynamic>)
              .map((e) => Event.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        purgedAt: $checkedConvert(
          'purgedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ChangePageToJson(ChangePage instance) =>
    <String, dynamic>{
      'groupId': instance.groupId,
      'seq': instance.seq,
      'hasMore': instance.hasMore,
      'group': instance.group?.toJson(),
      'members': instance.members.map((e) => e.toJson()).toList(),
      'entries': instance.entries.map((e) => e.toJson()).toList(),
      'events': instance.events.map((e) => e.toJson()).toList(),
      'purgedAt': instance.purgedAt?.toIso8601String(),
    };
