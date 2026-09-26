// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'google_redirect.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GoogleRedirect _$GoogleRedirectFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GoogleRedirect', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['url']);
      final val = GoogleRedirect(
        url: $checkedConvert('url', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$GoogleRedirectToJson(GoogleRedirect instance) =>
    <String, dynamic>{'url': instance.url};
