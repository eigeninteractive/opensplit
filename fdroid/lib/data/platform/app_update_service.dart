import 'package:opensplit/data/platform/update_urgency.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:opensplit/data/platform/update_urgency.dart';

/// F-Droid handles installation and updates for this build.
class AppUpdateService {
  const AppUpdateService();

  bool get isSupported => false;

  Future<UpdateUrgency> check() async => UpdateUrgency.none;

  Future<bool> download() async => false;

  Future<bool> installNow() async => false;

  Future<void> install() async {}

  Future<void> updateRequired() async {
    final opened = await launchUrl(
      Uri.parse('https://f-droid.org/packages/com.eigeninteractive.opensplit/'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw StateError('Could not open the OpenSplit F-Droid page.');
  }
}
