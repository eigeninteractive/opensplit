import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/repositories/invite_api.dart';

/// The critical path: someone taps a link a friend sent them.
///
/// There is no signup screen here and there never will be. A session is created
/// silently, the token is spent, and they land inside the group with the
/// balances already visible. Every wall placed at this moment is a person who
/// does not arrive.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  String? _error;
  bool _working = true;

  @override
  void initState() {
    super.initState();
    // Runs after the first frame so the screen paints something immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _claim());
  }

  Future<void> _claim() async {
    final invites = ref.read(inviteApiProvider);
    if (invites == null) {
      setState(() {
        _working = false;
        _error =
            'This build has no server configured, so links cannot be '
            'opened on it.';
      });
      return;
    }

    try {
      // Silently. The account is created, not requested.
      await ref.read(sessionControllerProvider.future);

      final member = await invites.redeem(widget.token);

      // Pull the group down before showing it, so it is populated on arrival
      // rather than filling in underneath them.
      await ref.read(syncControllerProvider.notifier).syncGroup(member.groupId);

      if (!mounted) return;
      context.go('/g/${member.groupId}');
    } on InviteRejected catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = 'Could not open this link. $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_working) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'Joining…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ] else ...[
                Icon(Icons.link_off, size: 48, color: scheme.error),
                const SizedBox(height: 16),
                Text(
                  'This link did not work',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Unknown problem.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ask whoever sent it to share a new one — links can only be '
                  'used once.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Go to your groups'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
