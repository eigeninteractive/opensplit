import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../navigation.dart';
import '../widgets/brand_mark.dart';
import '../widgets/page_body.dart';

/// What this app is, who can change it, and where to say something is wrong.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              child: BrandHeader(
                title: 'OpenSplit',
                subtitle: 'Shared expenses, without the extraction.',
              ),
            ),
            const _Version(),
            const Divider(height: 40),

            _Link(
              icon: Icons.code,
              title: 'Source code',
              subtitle: 'Every line of this app, and the server behind it.',
              url: repositoryUrl,
            ),
            _Link(
              icon: Icons.bug_report_outlined,
              title: 'Report an issue',
              subtitle: 'Bugs, and things that work but should not.',
              url: issuesUrl,
            ),
            _Link(
              icon: Icons.balance_outlined,
              title: 'Licence — AGPL-3.0',
              subtitle:
                  'Chosen so a proprietary fork cannot take this work, close '
                  'it, and outcompete the project it came from.',
              url: licenseUrl,
            ),

            // Flutter's own, rather than a page listing them by hand.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_outlined),
              title: const Text('Open-source licences'),
              subtitle: const Text(
                'The packages and typefaces this app is built on, and their '
                'terms.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'OpenSplit',
                applicationLegalese: '© 2026 EigenInteractive · AGPL-3.0',
              ),
            ),

            const Divider(height: 40),
            Text(
              'No ads, no analytics SDK, no venture funding, and logging an '
              'expense is never gated. Those are commitments rather than '
              'features — they are written down in the repository so they can '
              'be held against us.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
            : 'Version ${info.version} (${info.buildNumber})';

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
  const _Link({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
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
