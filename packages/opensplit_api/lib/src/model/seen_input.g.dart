// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seen_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SeenInput _$SeenInputFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SeenInput', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['seenAt']);
      final val = SeenInput(
        seenAt: $checkedConvert('seenAt', (v) => DateTime.parse(v as String)),
      );
      return val;
    });

Map<String, dynamic> _$SeenInputToJson(SeenInput instance) => <String, dynamic>{
  'seenAt': instance.seenAt.toIso8601String(),
};
