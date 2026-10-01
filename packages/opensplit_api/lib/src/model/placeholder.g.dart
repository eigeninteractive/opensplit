// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'placeholder.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Placeholder _$PlaceholderFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Placeholder', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['id', 'displayName']);
      final val = Placeholder(
        id: $checkedConvert('id', (v) => v as String),
        displayName: $checkedConvert('displayName', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$PlaceholderToJson(Placeholder instance) =>
    <String, dynamic>{'id': instance.id, 'displayName': instance.displayName};
