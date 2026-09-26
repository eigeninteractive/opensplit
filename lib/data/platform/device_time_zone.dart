import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// This device's IANA time zone (`Asia/Kolkata`), or null when the platform
/// will not say.
Future<String?> deviceTimeZone() async {
  try {
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
