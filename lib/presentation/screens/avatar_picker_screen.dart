import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit_api/opensplit_api.dart' show AvatarColor, AvatarIcon;

import '../../application/ledger_providers.dart';
import '../../application/local_providers.dart';
import '../../data/local/database.dart';
import '../../domain/avatar.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/avatar_view.dart';
import '../widgets/page_body.dart';
import '../widgets/sync_status_notice.dart';

/// Chooses what stands for you, or for a group: initials, an emoji or an
/// icon, on a hue.
///
/// Like the profile editor, it copies the avatar once when it opens and
/// writes it back only on Save.
class AvatarPickerScreen extends ConsumerStatefulWidget {
  /// Your own avatar.
  const AvatarPickerScreen.profile({super.key}) : groupId = null;

  /// A group's.
  const AvatarPickerScreen.group({super.key, required String this.groupId});

  final String? groupId;

  @override
  ConsumerState<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

/// What the picker needs to know about whoever it is picturing.
typedef _Subject = ({Avatar avatar, String name, String id});

class _AvatarPickerScreenState extends ConsumerState<AvatarPickerScreen> {
  Avatar? _original;
  Avatar? _chosen;
  bool _saving = false;

  String get _back =>
      widget.groupId == null ? '/account' : '/g/${widget.groupId}/settings';

  _Subject? _subject() {
    final groupId = widget.groupId;
    if (groupId != null) {
      final group = ref.watch(groupProvider(groupId)).value;
      return group == null
          ? null
          : (avatar: group.avatar, name: group.name, id: group.id);
    }
    final id = ref.watch(currentAccountIdProvider);
    if (id == null) return null;
    // Not until the saved profile has been read: what is shown first becomes
    // the picture that "unchanged" is measured against.
    final saved = ref.watch(myProfileProvider);
    if (!saved.hasValue) return null;
    final profile = saved.value;
    return (
      avatar: profile?.avatar ?? const InitialsAvatar(),
      name: profile?.displayName ?? '',
      id: id,
    );
  }

  Future<void> _save(Avatar avatar) async {
    setState(() => _saving = true);
    try {
      final groupId = widget.groupId;
      if (groupId == null) {
        await ref.read(myProfileControllerProvider.notifier).setAvatar(avatar);
      } else {
        final groups = ref.read(groupRepositoryProvider);
        final group = await groups.getGroup(groupId);
        if (group != null) await groups.updateGroup(group.withAvatar(avatar));
      }
      if (mounted) goBack(context, _back);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save. $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = _subject();
    if (subject != null && _original == null) {
      _original = subject.avatar;
      _chosen = subject.avatar;
    }
    final chosen = _chosen;
    final changed = chosen != null && chosen != _original;

    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: () => goBack(context, _back)),
        title: Text(widget.groupId == null ? 'Your picture' : 'Group picture'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: changed && !_saving ? () => _save(chosen) : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: PageBody(
        child: subject == null || chosen == null
            ? const SavedDataLoading(label: 'Loading the current picture')
            : _Picker(
                subject: subject,
                chosen: chosen,
                onChanged: (avatar) => setState(() => _chosen = avatar),
              ),
      ),
    );
  }
}

enum _Kind { initials, emoji, icon }

class _Picker extends StatelessWidget {
  const _Picker({
    required this.subject,
    required this.chosen,
    required this.onChanged,
  });

  final _Subject subject;
  final Avatar chosen;
  final ValueChanged<Avatar> onChanged;

  _Kind get _kind => switch (chosen) {
    EmojiAvatar() => _Kind.emoji,
    IconAvatar() => _Kind.icon,
    InitialsAvatar() || PhotoAvatar() => _Kind.initials,
  };

  void _switchTo(_Kind kind) => onChanged(switch (kind) {
    _Kind.initials => InitialsAvatar(color: chosen.color),
    _Kind.emoji => EmojiAvatar(
      _emojiChoices.first.emoji.first,
      color: chosen.color,
    ),
    _Kind.icon => IconAvatar(avatarIconChoices.first, color: chosen.color),
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hue = chosen.color ?? hueFor(subject.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Center(
          child: AvatarView(
            avatar: chosen,
            name: subject.name,
            id: subject.id,
            radius: 56,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subject.name.isEmpty ? 'No name yet' : subject.name,
          textAlign: TextAlign.center,
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        Center(
          child: SegmentedButton<_Kind>(
            segments: const [
              ButtonSegment(
                value: _Kind.initials,
                label: Text('Initials'),
                icon: Icon(Icons.text_fields),
              ),
              ButtonSegment(
                value: _Kind.emoji,
                label: Text('Emoji'),
                icon: Icon(Icons.emoji_emotions_outlined),
              ),
              ButtonSegment(
                value: _Kind.icon,
                label: Text('Icon'),
                icon: Icon(Icons.interests_outlined),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (kinds) => _switchTo(kinds.single),
          ),
        ),
        const SizedBox(height: 24),
        _Heading('Colour'),
        _Hues(
          selected: hue,
          onSelected: (hue) => onChanged(chosen.withColor(hue)),
        ),
        ...switch (chosen) {
          EmojiAvatar(:final emoji) => [
            for (final group in _emojiChoices) ...[
              _Heading(group.label),
              _Choices(
                children: [
                  for (final choice in group.emoji)
                    _Choice(
                      selected: choice == emoji,
                      tooltip: choice,
                      onPressed: () =>
                          onChanged(EmojiAvatar(choice, color: chosen.color)),
                      child: Text(choice, style: textTheme.headlineSmall),
                    ),
                ],
              ),
            ],
          ],
          IconAvatar(:final icon) => [
            _Heading('Icon'),
            _Choices(
              children: [
                for (final choice in avatarIconChoices)
                  _Choice(
                    selected: choice == icon,
                    tooltip: choice.value.replaceAll('_', ' '),
                    onPressed: () =>
                        onChanged(IconAvatar(choice, color: chosen.color)),
                    child: Icon(avatarIconData(choice)),
                  ),
              ],
            ),
          ],
          InitialsAvatar() || PhotoAvatar() => const [],
        },
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// One filled button per hue, the hue itself as its colour.
class _Hues extends StatelessWidget {
  const _Hues({required this.selected, required this.onSelected});

  final AvatarColor selected;
  final ValueChanged<AvatarColor> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AvatarPalette.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hue in avatarHues)
          IconButton.filled(
            tooltip: _hueName(hue),
            isSelected: hue == selected,
            onPressed: () => onSelected(hue),
            style: IconButton.styleFrom(
              backgroundColor: palette[hue].primaryContainer,
              foregroundColor: palette[hue].onPrimaryContainer,
            ),
            icon: const Icon(null),
            selectedIcon: const Icon(Icons.check),
          ),
      ],
    );
  }

  static String _hueName(AvatarColor hue) =>
      hue.value[0].toUpperCase() + hue.value.substring(1);
}

class _Choices extends StatelessWidget {
  const _Choices({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 4, runSpacing: 4, children: children);
}

/// A tonal button when chosen, a plain one otherwise.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final bool selected;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => selected
      ? IconButton.filledTonal(
          tooltip: tooltip,
          isSelected: true,
          onPressed: onPressed,
          icon: child,
        )
      : IconButton(tooltip: tooltip, onPressed: onPressed, icon: child);
}

/// The icons offered, in the server's order.
final List<AvatarIcon> avatarIconChoices = [
  for (final icon in AvatarIcon.values)
    if (icon != AvatarIcon.unknownDefaultOpenApi) icon,
];

/// The emoji offered, grouped the way people tend to name groups.
const _emojiChoices = [
  (
    label: 'Travel',
    emoji: [
      '✈️',
      '🏖️',
      '🏝️',
      '🏔️',
      '🏕️',
      '🚗',
      '🚆',
      '🚢',
      '🧳',
      '🗺️',
      '🌍',
    ],
  ),
  (
    label: 'Home',
    emoji: ['🏠', '🏡', '🏢', '🛋️', '🔑', '🧺', '🪴', '🐶', '🐱', '👪'],
  ),
  (
    label: 'Food and drink',
    emoji: [
      '🍕',
      '🍔',
      '🍜',
      '🍣',
      '🌮',
      '🥗',
      '🍰',
      '☕',
      '🍺',
      '🍷',
      '🍹',
      '🛒',
    ],
  ),
  (
    label: 'Fun',
    emoji: [
      '🎉',
      '🎂',
      '🎁',
      '🎮',
      '🎬',
      '🎵',
      '🎤',
      '⚽',
      '🏏',
      '🏀',
      '🎾',
      '🚴',
    ],
  ),
  (
    label: 'Everything else',
    emoji: [
      '❤️',
      '⭐',
      '🔥',
      '🌈',
      '☀️',
      '🌙',
      '💼',
      '🎓',
      '💡',
      '📚',
      '🎨',
      '💸',
    ],
  ),
];
