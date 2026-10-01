// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'google_redirect_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GoogleRedirectRequest _$GoogleRedirectRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GoogleRedirectRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['callbackUrl', 'allowSignIn']);
  final val = GoogleRedirectRequest(
    callbackUrl: $checkedConvert('callbackUrl', (v) => v as String),
    allowSignIn: $checkedConvert('allowSignIn', (v) => v as bool),
  );
  return val;
});

Map<String, dynamic> _$GoogleRedirectRequestToJson(
  GoogleRedirectRequest instance,
) => <String, dynamic>{
  'callbackUrl': instance.callbackUrl,
  'allowSignIn': instance.allowSignIn,
};
