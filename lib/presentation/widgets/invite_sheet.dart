import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import 'notification_invitation.dart';
import '../../config.dart';
import '../../domain/models/member.dart';
import '../../domain/repositories/invite_api.dart';

/// Creates and shows a link that hands over one unclaimed place in a group.
Future<void> showInviteSheet(
  BuildContext context,
  WidgetRef ref,
  Member member,
) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _InviteSheet(member: member),
);

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.member});

  final Member member;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  String? _url;
  String? _error;
  DateTime? _expires;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _create());
  }

  Future<void> _create() async {
    final invites = ref.read(inviteApiProvider);
    if (invites == null) {
      setState(
        () => _error =
            'This build has no server configured, so it cannot '
            'create invite links.',
      );
      return;
    }

    try {
      // The member has to exist server-side before a link can point at it.
      await ref
          .read(syncControllerProvider.notifier)
          .syncGroup(widget.member.groupId);

      final invite = await invites.create(widget.member.id);
      if (mounted) {
        setState(() {
          _url = invite.urlFor(linkHost);
          _expires = invite.expiresAt;
        });
      }
    } on InviteRejected catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create a link. $e');
    }
  }

  /// When the link stops working, in words.
  ///
  /// A date only once one is known: until the server has answered there is no
  /// expiry to quote, and inventing one would be a promise the link cannot
  /// keep.
  String get _expiry => _expires == null
      ? 'shortly'
      : 'on ${_expires!.toLocal().toString().split(' ').first}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Invite ${widget.member.displayName}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.error),
            )
          else if (_url == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _url!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _url!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Link copied')));
                // The group is about to stop being a solo ledger, which is the
                // first moment being notified about it means anything.
                await offerNotifications(context, ref);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy link'),
            ),
            const SizedBox(height: 16),
            Text(
              'Send this to ${widget.member.displayName}. Opening it puts them '
              'straight into the group — no signup, nothing to install first. '
              'It works once and expires $_expiry.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Sharing it again replaces this one, so an old link left in a '
              'chat cannot still be used.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
