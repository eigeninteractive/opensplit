import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers.dart';
import '../../config.dart';
import '../../data/sync/api_client.dart';
import '../../data/sync/invites.dart';
import 'notification_invitation.dart';

/// The group's one open invite link: share it, show it, or turn it off.
///
/// The case this exists for is the one people actually have. A trip already has
/// a WhatsApp group; what it does not have is a list of who is definitely
/// coming. Naming six placeholders in order to mint six named invites, and then
/// working out in a chat of twelve which link belongs to whom, is a worse
/// version of posting one link — so this is one link, and whoever opens it can
/// say which of the people already in the group they are, or that they are
/// nobody yet.
///
/// Shown rather than hidden: the sheet always says the link is live, when it
/// expires, and offers to turn it off. A door into a group's finances that only
/// the person who opened it can see is the thing worth refusing, and the
/// activity feed records the opening and closing for the same reason.
Future<void> showGroupLinkSheet(BuildContext context, String groupId) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _GroupLinkSheet(groupId: groupId),
    );

class _GroupLinkSheet extends ConsumerStatefulWidget {
  const _GroupLinkSheet({required this.groupId});

  final String groupId;

  @override
  ConsumerState<_GroupLinkSheet> createState() => _GroupLinkSheetState();
}

class _GroupLinkSheetState extends ConsumerState<_GroupLinkSheet> {
  api.GroupLink? _link;
  String? _error;
  bool _busy = true;
  bool _showQr = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Invites? get _invites => ref.read(invitesProvider);

  /// Reuses the live link rather than minting one per visit.
  ///
  /// Minting on open would revoke the link somebody posted in a chat an hour
  /// ago, every time anybody looked at this sheet — which is the one way an
  /// invite link can break that nobody would ever think to check.
  Future<void> _load() async {
    final invites = _invites;
    if (invites == null) {
      setState(() {
        _busy = false;
        _error =
            'This build has no server configured, so it cannot create '
            'invite links.';
      });
      return;
    }

    await _run(() async {
      // The group has to exist server-side before a link can point at it.
      await ref.read(syncControllerProvider.notifier).syncGroup(widget.groupId);
      final existing = await invites.currentGroupLink(widget.groupId);
      if (mounted) setState(() => _link = existing);
    });
  }

  Future<void> _create() => _run(() async {
    final link = await _invites!.createGroupLink(widget.groupId);
    if (mounted) setState(() => _link = link);
    if (mounted) await offerNotifications(context, ref);
  });

  Future<void> _revoke() => _run(() async {
    await _invites!.revokeGroupLink(widget.groupId);
    if (mounted) {
      setState(() {
        _link = null;
        _showQr = false;
      });
    }
  });

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _url => joinUrl(linkHost, _link!.token);

  Future<void> _share() async {
    final name = ref.read(groupLedgerProvider(widget.groupId))?.group.name;
    await SharePlus.instance.share(
      ShareParams(
        text: name == null
            ? 'Join my group on OpenSplit: $_url'
            : 'Join “$name” on OpenSplit: $_url',
        subject: 'Join my OpenSplit group',
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        32 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Invite link', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),

          if (_error != null)
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            )
          else if (_busy && _link == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(
                  semanticsLabel: 'Checking for an invite link',
                ),
              ),
            )
          else if (_link == null)
            _NoLinkYet(busy: _busy, onCreate: _create)
          else
            ..._live(theme, scheme),
        ],
      ),
    );
  }

  List<Widget> _live(ThemeData theme, ColorScheme scheme) => [
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(_url, style: theme.textTheme.bodySmall),
    ),
    const SizedBox(height: 12),

    Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: _busy ? null : _copy,
          icon: const Icon(Icons.copy),
          tooltip: 'Copy link',
        ),
        const SizedBox(width: 8),
        // For the person sitting opposite you, which is most of the people a
        // trip's expenses get split with.
        IconButton.filledTonal(
          onPressed: _busy ? null : () => setState(() => _showQr = !_showQr),
          icon: Icon(_showQr ? Icons.qr_code_2_outlined : Icons.qr_code_2),
          tooltip: _showQr ? 'Hide QR code' : 'Show QR code',
        ),
      ],
    ),

    if (_showQr) ...[
      const SizedBox(height: 16),
      Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // White regardless of theme. A QR code is read by a camera, not by
            // a person, and inverting one in dark mode is how you produce a
            // code that looks right and does not scan.
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: _url,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    ],

    const SizedBox(height: 16),
    Text(
      'Anyone with this link can join the group. It works until '
      '${_on(_link!.expiresAt)}, and everyone here sees when it was created '
      'and used.',
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: 16),

    Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: _busy ? null : _revoke,
            icon: const Icon(Icons.link_off),
            label: const Text('Turn off'),
          ),
        ),
        Expanded(
          child: TextButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.refresh),
            label: const Text('New link'),
          ),
        ),
      ],
    ),
    Text(
      'A new link replaces this one, so a copy left in a chat stops working.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
  ];

  static String _on(DateTime at) {
    final local = at.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

/// No live link, which is the state a group starts in and returns to when
/// somebody turns one off.
class _NoLinkYet extends StatelessWidget {
  const _NoLinkYet({required this.busy, required this.onCreate});

  final bool busy;
  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Create a link anyone can use to join this group — paste it into '
          'the chat you already have. People who open it can say which of '
          'the people here they are, or join as somebody new.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          // No haptic. Minting a link is revocable -- there is a button for it
          // two rows down -- and the buzz in this app means precisely "that
          // cannot be taken back".
          onPressed: busy ? null : onCreate,
          icon: const Icon(Icons.link),
          label: const Text('Create invite link'),
        ),
      ],
    );
  }
}
