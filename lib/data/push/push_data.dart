import 'package:opensplit_api/opensplit_api.dart' as api;

/// The contract's push message, or null for one this build cannot act on.
api.PushData? readPushData(Map<String, dynamic> data) {
  try {
    final push = api.PushData.fromJson(data);
    return push.kind == api.EventKind.unknownDefaultOpenApi ? null : push;
  } on Object {
    return null;
  }
}
