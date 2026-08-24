// Checks env/app.json, and optionally fills the Android values from a
// google-services.json.
//
//   dart run tool/verify_config.dart
//   dart run tool/verify_config.dart ~/Downloads/google-services.json
//
// This exists because a placeholder can look like a real value. The template
// shipped `1:<sender>:android:<hash>` for the Android App ID, which starts with
// "1:" and does not start with "<", so every "is it filled in?" check I wrote
// said yes — twice, out loud, wrongly. Structure is the thing worth checking,
// not emptiness.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final file = File('env/app.json');
  if (!file.existsSync()) {
    stderr.writeln(
      'env/app.json not found. cp env/app.example.json env/app.json',
    );
    exit(1);
  }
  final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  if (args.isNotEmpty) {
    _importGoogleServices(args.first, config);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n',
    );
    stdout.writeln('Imported into env/app.json from ${args.first}\n');
  }

  final problems = _check(config);
  exit(problems == 0 ? 0 : 1);
}

/// Pulls the four values google-services.json is authoritative for.
///
/// Copying them by hand means four chances to paste the wrong one, and the
/// project id in particular is easy to confuse with the display name — the
/// console shows "OpenSplit" in big letters and the id, which is what every
/// API wants, in small ones.
void _importGoogleServices(String path, Map<String, dynamic> config) {
  final source = File(path);
  if (!source.existsSync()) {
    stderr.writeln('No such file: $path');
    exit(1);
  }
  final gs = jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  final info = gs['project_info'] as Map<String, dynamic>;
  final clients = gs['client'] as List<dynamic>;

  final android = clients.cast<Map<String, dynamic>>().firstWhere(
    (c) => ((c['client_info'] as Map)['mobilesdk_app_id'] as String).contains(
      ':android:',
    ),
    orElse: () {
      stderr.writeln('That google-services.json has no Android app in it.');
      exit(1);
    },
  );

  config['FCM_PROJECT_ID'] = info['project_id'];
  config['FCM_SENDER_ID'] = info['project_number'];
  config['ANDROID_FCM_APP_ID'] =
      (android['client_info'] as Map)['mobilesdk_app_id'];
  config['ANDROID_FCM_API_KEY'] =
      ((android['api_key'] as List).first as Map)['current_key'];
}

int _check(Map<String, dynamic> config) {
  var problems = 0;
  final sender = '${config['FCM_SENDER_ID'] ?? ''}';

  void report(String key, String? problem) {
    final value = '${config[key] ?? ''}';
    final shown = value.length <= 14
        ? value
        : '${value.substring(0, 7)}…${value.substring(value.length - 7)}';
    if (problem == null) {
      stdout.writeln('  ok    ${key.padRight(24)} $shown');
    } else {
      problems++;
      stdout.writeln('  FIX   ${key.padRight(24)} $problem');
    }
  }

  String? matches(String key, RegExp pattern, String expected) {
    final value = '${config[key] ?? ''}';
    if (value.isEmpty || value.startsWith('<')) return 'not filled in yet';
    return pattern.hasMatch(value) ? null : 'expected $expected';
  }

  // An App ID carries the project number, so it cross-checks the sender id.
  String? appId(String key, String platform) {
    final value = '${config[key] ?? ''}';
    if (value.isEmpty || value.startsWith('<')) return 'not filled in yet';
    final match = RegExp('^1:(\\d+):$platform:[0-9a-f]+\$').firstMatch(value);
    if (match == null) return 'expected 1:<number>:$platform:<hex>';
    if (match.group(1) != sender) {
      return 'holds project number ${match.group(1)}, but FCM_SENDER_ID is $sender';
    }
    return null;
  }

  report(
    'SUPABASE_URL',
    matches(
      'SUPABASE_URL',
      RegExp(r'^https://[a-z0-9]+\.supabase\.co$'),
      'https://<ref>.supabase.co',
    ),
  );
  report(
    'SUPABASE_PUBLISHABLE_KEY',
    matches(
      'SUPABASE_PUBLISHABLE_KEY',
      RegExp(r'^sb_publishable_'),
      'sb_publishable_…',
    ),
  );
  report(
    'LINK_HOST',
    matches(
      'LINK_HOST',
      RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$'),
      'a bare host, no scheme or slash',
    ),
  );
  report(
    'GOOGLE_WEB_CLIENT_ID',
    matches(
      'GOOGLE_WEB_CLIENT_ID',
      RegExp(r'\.apps\.googleusercontent\.com$'),
      '….apps.googleusercontent.com',
    ),
  );
  report(
    'FCM_PROJECT_ID',
    matches(
      'FCM_PROJECT_ID',
      RegExp(r'^[a-z][a-z0-9-]{4,29}$'),
      'the lowercase project id, not the display name',
    ),
  );
  report(
    'FCM_SENDER_ID',
    matches(
      'FCM_SENDER_ID',
      RegExp(r'^\d{6,}$'),
      'the project number, digits only',
    ),
  );
  report(
    'FCM_VAPID_KEY',
    matches(
      'FCM_VAPID_KEY',
      RegExp(r'^[A-Za-z0-9_-]{80,100}$'),
      'a ~87 character base64url key',
    ),
  );
  report(
    'ANDROID_FCM_API_KEY',
    matches(
      'ANDROID_FCM_API_KEY',
      RegExp(r'^AIza[0-9A-Za-z_-]{35}$'),
      'AIza followed by 35 characters',
    ),
  );
  report(
    'WEB_FCM_API_KEY',
    matches(
      'WEB_FCM_API_KEY',
      RegExp(r'^AIza[0-9A-Za-z_-]{35}$'),
      'AIza followed by 35 characters',
    ),
  );
  report('ANDROID_FCM_APP_ID', appId('ANDROID_FCM_APP_ID', 'android'));
  report('WEB_FCM_APP_ID', appId('WEB_FCM_APP_ID', 'web'));

  // The same key on both platforms means one of them was pasted twice. It
  // usually works on the day and stops the moment either key's restrictions
  // are tightened.
  if (config['ANDROID_FCM_API_KEY'] == config['WEB_FCM_API_KEY'] &&
      '${config['WEB_FCM_API_KEY']}'.startsWith('AIza')) {
    problems++;
    stdout.writeln(
      '  FIX   ANDROID/WEB_FCM_API_KEY  are identical; Firebase '
      'issues a separate key per platform',
    );
  }

  stdout.writeln(problems == 0 ? '\nAll good.' : '\n$problems to fix.');
  return problems;
}
