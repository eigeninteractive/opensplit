import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../navigation.dart';
import '../widgets/brand_mark.dart';
import '../widgets/page_body.dart';

/// The version line, as a bug report should quote it.
///
/// [buildNumber] is the release workflow's, the same on Android and the web for
/// one release, and is what tells two builds of one version apart. A build made
/// from a checkout has none on the web, so it shows the version alone rather
/// than an empty pair of brackets.
String versionLabel(String version, String buildNumber) => buildNumber.isEmpty
    ? 'Version $version'
    : 'Version $version ($buildNumber)';

/// What this app is, who can change it, and where to say something is wrong.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/settings')),
        title: const Text('About'),
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: BrandHeader(title: 'OpenSplit', subtitle: brandTagline),
            ),
            const _Version(),
            const Divider(height: 40),

            _Link(icon: Icons.code, title: 'Source code', url: repositoryUrl),
            _Link(
              icon: Icons.bug_report_outlined,
              title: 'Report an issue',
              url: issuesUrl,
            ),
            _Link(
              icon: Icons.balance_outlined,
              title: 'Licence — AGPL-3.0',
              url: licenseUrl,
            ),

            // Flutter's own, rather than a page listing them by hand.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_outlined),
              title: const Text('Open-source licences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'OpenSplit',
                applicationLegalese: '© 2026 EigenInteractive · AGPL-3.0',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The running version, read from the bundle rather than from a constant.
class _Version extends StatelessWidget {
  const _Version();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        // Reserves its line while the platform channel answers, so the rows
        // below do not jump once it does.
        final text = info == null
            ? ''
            : versionLabel(info.version, info.buildNumber);

        return SizedBox(
          height: 24,
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A row that leaves the app.
class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.title, required this.url});

  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.open_in_new, size: 18),
    onTap: () async {
      final messenger = ScaffoldMessenger.of(context);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    },
  );
}
