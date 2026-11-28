import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/push_providers.dart';
import '../../config.dart';
import '../dynamic_colors.dart';
import '../theme_mode.dart';
import '../widgets/page_body.dart';
import '../widgets/segmented_list.dart';

/// Appearance, notifications, and information about OpenSplit.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DestinationScaffold(
      title: 'Settings',
      slivers: [
        SliverList.list(
          children: [
            const _AppearanceSetting(),
            const SizedBox(height: 24),
            const _WallpaperSetting(),
            // Hidden entirely rather than shown broken when the build has no
            // FCM credentials, matching how every other integration behaves
            // here.
            if (hasPush) ...[
              const SizedBox(height: 24),
              const _NotificationSetting(),
            ],
            const SizedBox(height: 32),
            SegmentedList(
              children: [
                const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Offline first'),
                  subtitle: Text('Expenses are saved on this device first'),
                  titleAlignment: ListTileTitleAlignment.center,
                ),
                const ListTile(
                  leading: Icon(Icons.favorite_outline),
                  title: Text('Free forever'),
                  subtitle: Text('Open source, with no ads or analytics SDKs.'),
                  titleAlignment: ListTileTitleAlignment.center,
                ),
                if (showFundingLink)
                  _ExternalLink(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'Support OpenSplit',
                    url: supportUrl,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SegmentedList(
              children: [
                _ExternalLink(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  url: privacyPolicyUrl,
                ),
                _ExternalLink(
                  icon: Icons.gavel_outlined,
                  title: 'Terms of service',
                  url: termsUrl,
                ),
                // Last, and a push rather than a link out: everything above leaves
                // the app, and this is the one row that stays in it.
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About OpenSplit'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/about'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Light, dark, or whatever the platform is doing.
class _AppearanceSetting extends ConsumerWidget {
  const _AppearanceSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {mode},
            // Single selection, so the set always holds exactly one.
            onSelectionChanged: (selection) =>
                ref.read(themeModeProvider.notifier).set(selection.first),
          ),
        ),
      ],
    );
  }
}

/// Opens a page on the OpenSplit website.
class _ExternalLink extends StatelessWidget {
  const _ExternalLink({
    required this.icon,
    required this.title,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) => ListTile(
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

/// Whether the app takes its colours from the wallpaper, and whether it can.
class _WallpaperSetting extends ConsumerWidget {
  const _WallpaperSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schemes = ref.watch(wallpaperSchemesProvider);
    final enabled = ref.watch(wallpaperColorsProvider);
    final text = Theme.of(context).textTheme;

    // Still asking the platform. A single frame in practice, and showing
    // "not available" during it would be a lie that then corrects itself.
    if (schemes.isLoading && !schemes.hasValue) {
      return const SizedBox.shrink();
    }

    final available = schemes.value;
    if (available == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Using OpenSplit colours'),
            subtitle: Text(
              kIsWeb
                  ? 'Wallpaper colours are available in the Android app.'
                  : 'On Samsung, check Settings → Wallpaper and style → '
                        'Colour palette.',
            ),
          ),
          if (!kIsWeb)
            TextButton.icon(
              onPressed: () => ref.invalidate(wallpaperSchemesProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
        ],
      );
    }

    final palette = Theme.of(context).brightness == Brightness.dark
        ? available.dark
        : available.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: (wanted) =>
              ref.read(wallpaperColorsProvider.notifier).set(enabled: wanted),
          secondary: const Icon(Icons.palette_outlined),
          title: const Text('Match my wallpaper'),
        ),
        const SizedBox(height: 8),
        // The palette itself, so that "it is on and nothing changed" is
        // answerable by looking rather than by guessing.
        Row(
          children: [
            for (final swatch in [
              palette.primary,
              palette.primaryContainer,
              palette.secondary,
              palette.tertiary,
            ])
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Text(
                'Wallpaper colours',
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The switch that governs whether this device is told about group activity.
class _NotificationSetting extends ConsumerStatefulWidget {
  const _NotificationSetting();

  @override
  ConsumerState<_NotificationSetting> createState() =>
      _NotificationSettingState();
}

class _NotificationSettingState extends ConsumerState<_NotificationSetting> {
  bool _busy = false;

  Future<void> _toggle(bool wanted) async {
    setState(() => _busy = true);
    try {
      final controller = ref.read(notificationPreferenceProvider.notifier);
      if (!wanted) {
        await controller.disable();
        return;
      }

      final granted = await controller.enable();
      if (!mounted || granted) return;

      // The switch springs back, because it would otherwise claim a state the
      // OS has refused.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allow notifications for OpenSplit in your device or browser settings.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update notifications.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(notificationPreferenceProvider) == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: _busy ? null : _toggle,
          title: const Text('Group notifications'),
          subtitle: const Text(
            'Expenses, payments and weekly reminders for unpaid balances.',
          ),
        ),
      ],
    );
  }
}
