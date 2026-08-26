import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/page_body.dart';
import '../../application/providers.dart';
import '../../config.dart';
import 'package:go_router/go_router.dart';

import '../dynamic_colors.dart';
import '../theme_mode.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _AccountRow(),
            const SizedBox(height: 24),
            const _AppearanceSetting(),
            const SizedBox(height: 24),
            const _WallpaperSetting(),
            // Hidden entirely rather than shown broken when the build has
            // no FCM credentials, matching how every other integration behaves
            // here.
            if (hasPush) ...[
              const Divider(height: 48),
              const _NotificationSetting(),
            ],
            const Divider(height: 48),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_outline),
              title: Text('Your data is on this device'),
              subtitle: Text(
                'Expenses are stored locally in SQLite. The app keeps working '
                'with what it has even if it can never reach a server again.',
              ),
              isThreeLine: true,
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.favorite_outline),
              title: Text('Free forever'),
              subtitle: Text(
                'Logging an expense is never gated, there are no ads, and no '
                'analytics SDK is present in this app.',
              ),
              isThreeLine: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the account is, at the top of the screen where it is read first.
///
/// Settings pages put the account first because it is the thing a user checks
/// rather than changes, and because "am I actually signed in?" is the question
/// this screen most often gets opened to answer. It used to be answerable only
/// by scrolling past three other sections to a form.
///
/// Leads to a screen rather than expanding in place. The linking flow has its
/// own state — an email field, a sent code, an error — and a settings list is
/// the wrong container for something with steps.
class _AccountRow extends ConsumerWidget {
  const _AccountRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;

    // No backend configured, so there is no account to have.
    if (account == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final anonymous = account.isAnonymous;

    return Card.filled(
      // Coloured only while something needs doing. A permanent warning tint on
      // a settled account would be crying wolf on every visit.
      color: anonymous ? scheme.secondaryContainer : null,
      child: ListTile(
        onTap: () => context.go('/account'),
        leading: Icon(
          anonymous ? Icons.person_outline : Icons.verified_user_outlined,
          color: anonymous ? scheme.onSecondaryContainer : null,
        ),
        title: Text(
          anonymous ? 'Guest — nothing is backed up' : 'Account saved',
          style: TextStyle(
            color: anonymous ? scheme.onSecondaryContainer : null,
          ),
        ),
        subtitle: Text(
          anonymous
              ? 'Add an email or use Google, so this survives losing the '
                    'device.'
              : account.email ?? 'You can sign in on another device.',
          style: TextStyle(
            color: anonymous ? scheme.onSecondaryContainer : null,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: anonymous ? scheme.onSecondaryContainer : null,
        ),
      ),
    );
  }
}

/// Light, dark, or whatever the platform is doing.
///
/// A SegmentedButton rather than three radio tiles or a dropdown: Material 3
/// defines it for exactly this shape of choice — a small set of mutually
/// exclusive options, all worth showing at once, where the selected one should
/// be readable without opening anything.
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
        const SizedBox(height: 8),
        Text(
          'System follows your device, including its automatic night '
          'schedule.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Whether the app takes its colours from the wallpaper, and whether it can.
///
/// Both halves matter, and the second is why this row exists at all. Material
/// You is invisible when it is working — the app simply looks like the rest of
/// the phone — and identical to a bug when it is not. Saying which is happening
/// turns "the colours never change" from something to investigate into
/// something to read.
class _WallpaperSetting extends ConsumerWidget {
  const _WallpaperSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schemes = ref.watch(wallpaperSchemesProvider);
    final enabled = ref.watch(wallpaperColorsProvider);
    final text = Theme.of(context).textTheme;

    // Still asking the platform. A single frame in practice, and showing
    // "not available" during it would be a lie that then corrects itself.
    if (schemes.isLoading) return const SizedBox.shrink();

    final available = schemes.value;
    if (available == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.palette_outlined),
        title: const Text('Wallpaper colours are not available here'),
        subtitle: const Text(
          'Android 12 and later hand apps a palette taken from your '
          'wallpaper. This device does not offer one, so OpenSplit uses its '
          'own — which is also what every browser gets.',
        ),
        isThreeLine: true,
        enabled: false,
      );
    }

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
          subtitle: const Text(
            'Use the colours Android takes from your wallpaper, instead of '
            "OpenSplit's own.",
          ),
        ),
        const SizedBox(height: 8),
        // The palette itself, so that "it is on and nothing changed" is
        // answerable by looking rather than by guessing. A wallpaper can be
        // very nearly grey, and that is what this shows when it is.
        Row(
          children: [
            for (final swatch in [
              available.light.primary,
              available.light.primaryContainer,
              available.light.secondary,
              available.light.tertiary,
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
                enabled
                    ? "What your wallpaper offers, and what you are seeing."
                    : 'What your wallpaper offers. Not in use.',
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
///
/// This is the only place the app asks for notification permission unprompted,
/// and it asks only when the switch is turned on — a deliberate action, taken
/// on a screen the user navigated to. Nothing about launching the app produces
/// a system dialog.
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
      // OS has refused. Android stops showing the dialog after a second
      // refusal, so "try again" is not useful advice — system settings is.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Android did not grant permission. You can turn notifications on '
            'for OpenSplit in system settings.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(notificationPreferenceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: _busy ? null : _toggle,
          title: const Text('Tell me about group activity'),
          subtitle: const Text(
            'A quiet notification when someone adds an expense or settles up. '
            'The message is put together on your device — the server only '
            'sends an id, never an amount.',
          ),
          isThreeLine: true,
        ),
      ],
    );
  }
}
