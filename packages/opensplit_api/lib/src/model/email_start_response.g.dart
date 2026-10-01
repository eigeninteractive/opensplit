// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_start_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmailStartResponse _$EmailStartResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('EmailStartResponse', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['flow']);
      final val = EmailStartResponse(
        flow: $checkedConvert(
          'flow',
          (v) => $enumDecode(
            _$EmailFlowEnumMap,
            v,
            unknownValue: EmailFlow.unknownDefaultOpenApi,
          ),
        ),
      );
      return val;
    });

Map<String, dynamic> _$EmailStartResponseToJson(EmailStartResponse instance) =>
    <String, dynamic>{'flow': _$EmailFlowEnumMap[instance.flow]!};

const _$EmailFlowEnumMap = {
  EmailFlow.linkPending: 'linkPending',
  EmailFlow.signInPending: 'signInPending',
  EmailFlow.unknownDefaultOpenApi: 'unknown_default_open_api',
};
