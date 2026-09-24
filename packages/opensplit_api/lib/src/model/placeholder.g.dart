// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'placeholder.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Placeholder _$PlaceholderFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Placeholder', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['memberId', 'displayName']);
      final val = Placeholder(
        memberId: $checkedConvert('memberId', (v) => v as String),
        displayName: $checkedConvert('displayName', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$PlaceholderToJson(Placeholder instance) =>
    <String, dynamic>{
      'memberId': instance.memberId,
      'displayName': instance.displayName,
    };
