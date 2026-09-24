// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'link_revocation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LinkRevocation _$LinkRevocationFromJson(Map<String, dynamic> json) =>
    $checkedCreate('LinkRevocation', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['revoked']);
      final val = LinkRevocation(
        revoked: $checkedConvert('revoked', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$LinkRevocationToJson(LinkRevocation instance) =>
    <String, dynamic>{'revoked': instance.revoked};
