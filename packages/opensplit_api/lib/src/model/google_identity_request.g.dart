// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'google_identity_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GoogleIdentityRequest _$GoogleIdentityRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GoogleIdentityRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['idToken', 'nonce', 'allowSignIn']);
  final val = GoogleIdentityRequest(
    idToken: $checkedConvert('idToken', (v) => v as String),
    nonce: $checkedConvert('nonce', (v) => v as String?),
    allowSignIn: $checkedConvert('allowSignIn', (v) => v as bool),
  );
  return val;
});

Map<String, dynamic> _$GoogleIdentityRequestToJson(
  GoogleIdentityRequest instance,
) => <String, dynamic>{
  'idToken': instance.idToken,
  'nonce': instance.nonce,
  'allowSignIn': instance.allowSignIn,
};
