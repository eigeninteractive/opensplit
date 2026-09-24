// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_superseded_inner.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InviteSupersededInner _$InviteSupersededInnerFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('InviteSupersededInner', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['token']);
  final val = InviteSupersededInner(
    token: $checkedConvert('token', (v) => v as String),
  );
  return val;
});

Map<String, dynamic> _$InviteSupersededInnerToJson(
  InviteSupersededInner instance,
) => <String, dynamic>{'token': instance.token};
