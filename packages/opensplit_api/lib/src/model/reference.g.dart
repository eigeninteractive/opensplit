// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reference.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Reference _$ReferenceFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Reference', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['currencies', 'categories']);
      final val = Reference(
        currencies: $checkedConvert(
          'currencies',
          (v) => (v as List<dynamic>)
              .map((e) => Currency.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        categories: $checkedConvert(
          'categories',
          (v) => (v as List<dynamic>)
              .map((e) => Category.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ReferenceToJson(Reference instance) => <String, dynamic>{
  'currencies': instance.currencies.map((e) => e.toJson()).toList(),
  'categories': instance.categories.map((e) => e.toJson()).toList(),
};
