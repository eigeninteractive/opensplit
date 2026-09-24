// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'placeholder_list.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlaceholderList _$PlaceholderListFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PlaceholderList', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['placeholders']);
      final val = PlaceholderList(
        placeholders: $checkedConvert(
          'placeholders',
          (v) => (v as List<dynamic>)
              .map((e) => Placeholder.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$PlaceholderListToJson(PlaceholderList instance) =>
    <String, dynamic>{
      'placeholders': instance.placeholders.map((e) => e.toJson()).toList(),
    };
