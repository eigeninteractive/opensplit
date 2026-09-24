import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/repositories/invite_api.dart';
import '../widgets/brand_mark.dart';
import '../widgets/identity_choices.dart';
import '../widgets/page_body.dart';

/// The critical path: someone taps a link a friend sent them.
///
/// It reads the invite before spending it, and that ordering is the whole
/// screen. The previous version signed every arrival in anonymously and
/// redeemed immediately, on the reasoning that a signup wall here is where
/// people leave. The wall really is worth avoiding — but claiming first meant
/// that anybody who already had an account, which is most people arriving from
/// a link, had their place taken by a throwaway account and the single-use
/// token spent. Signing in afterwards did not help: their real account had a
/// different id, the member row pointed at the anonymous one, and a group
/// refuses two places for the same person. Only the owner reissuing the link
/// fixed it.
///
/// So: show what the link is for, ask who they are, then claim once. There is
/// still no wall — being a guest is one of the three answers — and there is now
/// a way to say no, which matters when the link was meant for somebody else.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  LinkTarget? _target;
  String? _error;
  bool _loading = true;
  bool _joining = false;

  /// The unclaimed places an open link's group is holding.
  ///
  /// Null until asked for, which is deliberately not until there is a session:
  /// these are other people's names, and the server refuses to list them to
  /// somebody who has not said who they are.
  List<LinkPlaceholder>? _places;
  bool _loadingPlaces = false;

  /// The place about to be claimed, or null for "I am not listed".
  String? _chosenMemberId;

  /// The name to arrive under, for somebody who is not one of the places.
  ///
  /// Only ever read on that branch. Claiming a place keeps the name the group
  /// already wrote on it, and the account adopts that name rather than the
  /// other way round.
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _peek());
  }

  Future<void> _peek() async {
    final invites = ref.read(inviteApiProvider);
    if (invites == null) {
      setState(() {
        _loading = false;
        _error =
            'This build has no server configured, so links cannot be opened '
            'on it.';
      });
      return;
    }

    try {
      final target = await invites.peekLink(widget.token);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _target = target;
        if (target == null) _error = 'This is not a link we recognise.';
      });
      // An open link with a session already in hand can go straight to the
      // question that matters.
      if (target is GroupLinkTarget) await _loadPlaces();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not open this link. $e';
        });
      }
    }
  }

  /// The unclaimed places, once there is somebody to show them to.
  Future<void> _loadPlaces() async {
    final invites = ref.read(inviteApiProvider);
    if (invites == null || _places != null || _loadingPlaces) return;
    if (ref.read(accountProvider).value == null) return;

    setState(() => _loadingPlaces = true);
    try {
      final places = await invites.placeholdersFor(widget.token);
      if (mounted) setState(() => _places = places);
    } catch (_) {
      // Not fatal, and not worth an error banner in front of the button that
      // still works: without the list, joining simply adds a new member, which
      // is what "I am not listed" does anyway.
      if (mounted) setState(() => _places = const []);
    } finally {
      if (mounted) setState(() => _loadingPlaces = false);
    }
  }

  /// Spends the token as whoever holds the session now.
  Future<void> _join() async {
    final invites = ref.read(inviteApiProvider);
    if (invites == null) return;

    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final member = switch (_target) {
        GroupLinkTarget() => await invites.joinWithLink(
          widget.token,
          memberId: _chosenMemberId,
          displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        ),
        // A named invite names the place; there is nothing to choose.
        _ => await invites.redeem(widget.token),
      };
      // Pull the group down before showing it, so it is populated on arrival
      // rather than filling in underneath them.
      await ref.read(syncControllerProvider.notifier).syncGroup(member.groupId);
      if (mounted) context.go('/g/${member.groupId}');
    } on InviteRejected catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = 'Could not join. $e';
        });
      }
    }
  }

  /// Leaves this account and comes back to the same link.
  ///
  /// Safe to offer precisely because nothing has been claimed yet: the token is
  /// still unspent, so signing out and returning is a real way to fix having
  /// opened somebody else's invite while signed in as yourself.
  Future<void> _switchAccount() async {
    await ref.read(sessionControllerProvider.notifier).signOut();
    if (mounted) {
      setState(() {
        // The list came from the account that is now gone, and the server
        // would refuse to give it to nobody.
        _places = null;
        _chosenMemberId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: BrandWash(
        child: PageBody(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _body(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(semanticsLabel: 'Opening this link'),
        ],
      );
    }

    return switch (_target) {
      null => _Dead(message: _error ?? 'Unknown problem.'),
      MemberInviteTarget(:final preview) => _invitation(theme, preview),
      GroupLinkTarget(:final preview) => _openLink(theme, preview),
    };
  }

  /// A link naming one place, for one person.
  Widget _invitation(ThemeData theme, InvitePreview preview) {
    if (preview.isRedeemed) {
      return _Dead(
        message:
            'This link has already been used. Links work once, so ask '
            '${preview.inviterName} to send a new one.',
      );
    }
    if (preview.isExpired) {
      return _Dead(
        message:
            'This link has expired. Ask ${preview.inviterName} to send a '
            'new one.',
      );
    }
    if (preview.isMember) {
      return _Dead(
        message:
            'You are already in ${preview.groupName}, so there is nothing to '
            'claim here.',
        action: FilledButton(
          onPressed: () => context.go('/g/${preview.groupId}'),
          child: const Text('Open the group'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandHeader(
          title: '${preview.inviterName} invited you to ${preview.groupName}',
          subtitle:
              'You would join as \u201c${preview.memberName}\u201d, alongside '
              '${preview.memberCount} '
              '${preview.memberCount == 1 ? 'person' : 'people'}.',
        ),
        const SizedBox(height: 32),
        ..._errorIfAny(theme),
        _Claim(
          preview: preview,
          joining: _joining,
          onJoin: _join,
          onSwitchAccount: _switchAccount,
        ),
      ],
    );
  }

  /// A link anybody may use, which is the one posted in a group chat.
  Widget _openLink(ThemeData theme, GroupLinkPreview preview) {
    if (preview.isRevoked) {
      return _Dead(
        message:
            'This link has been turned off. Ask ${preview.inviterName} for a '
            'new one.',
      );
    }
    if (preview.isExpired) {
      return _Dead(
        message:
            'This link has expired. Ask ${preview.inviterName} for a new one.',
      );
    }
    if (preview.isMember) {
      return _Dead(
        message:
            'You are already in ${preview.groupName}, so there is nothing to '
            'do here.',
        action: FilledButton(
          onPressed: () => context.go('/g/${preview.groupId}'),
          child: const Text('Open the group'),
        ),
      );
    }

    final account = ref.watch(accountProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandHeader(
          title: '${preview.inviterName} invited you to ${preview.groupName}',
          subtitle:
              '${preview.memberCount} '
              '${preview.memberCount == 1 ? 'person is' : 'people are'} '
              'already here.',
        ),
        const SizedBox(height: 32),
        ..._errorIfAny(theme),

        // Who you are comes first, exactly as it does for a named invite, and
        // for the same reason: the list below is other people's names, and the
        // server will not show it to somebody who has not said who they are.
        if (account == null)
          IdentityChoices(
            onSignedIn: () async {
              await _loadPlaces();
              // Not joined yet, deliberately. An open link has a question
              // after the account one -- which of these people are you -- and
              // answering the first should not answer the second by default.
              if (mounted) setState(() {});
            },
            guestNote:
                'You will join straight away and the group will synchronize. '
                'This device is the only way back into the guest account '
                'until you add an email address or Google account.',
          )
        else
          _ChoosePlace(
            places: _places,
            loading: _loadingPlaces,
            chosen: _chosenMemberId,
            joining: _joining,
            // Asked for only when there is nowhere to take it from. Anybody
            // who signed in with Google or an email address already has a
            // name; a guest has none, and a member row without one is not a
            // row this ledger can hold.
            name: account.displayName == null ? _name : null,
            onChoose: (memberId) => setState(() => _chosenMemberId = memberId),
            onJoin: _join,
            onSwitchAccount: _switchAccount,
          ),
      ],
    );
  }

  List<Widget> _errorIfAny(ThemeData theme) => [
    if (_error != null) ...[
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      const SizedBox(height: 16),
    ],
  ];
}

/// "Are you one of these people?"
///
/// The whole reason an open link does not turn a group of six into a group of
/// twelve. Somebody makes the group, types in everyone on the trip, and posts
/// one link; without this, each arrival becomes a new member beside the
/// placeholder that was already them, and somebody spends an evening merging
/// rows by hand. Claiming one is the same single-column update a named invite
/// performs, so no balance moves and no expense is rewritten.
///
/// "I'm not listed" is a real option and sits with the others rather than below
/// them, because for a group that named nobody it is the only true answer.
class _ChoosePlace extends StatelessWidget {
  const _ChoosePlace({
    required this.places,
    required this.loading,
    required this.chosen,
    required this.joining,
    required this.name,
    required this.onChoose,
    required this.onJoin,
    required this.onSwitchAccount,
  });

  final List<LinkPlaceholder>? places;
  final bool loading;
  final String? chosen;
  final bool joining;

  /// Where to put the arrival's own name, or null when the account has one.
  final TextEditingController? name;

  final ValueChanged<String?> onChoose;
  final Future<void> Function() onJoin;
  final Future<void> Function() onSwitchAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(
            semanticsLabel: 'Looking at who is in this group',
          ),
        ),
      );
    }

    final waiting = places ?? const <LinkPlaceholder>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (waiting.isNotEmpty) ...[
          Text(
            'Are you one of these people?',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Someone here has already added them. Picking yourself keeps the '
            'expenses they are part of.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          // One RadioGroup around the set rather than a groupValue on each
          // tile: Material moved the selection to an ancestor after 3.32, so
          // the group is stated once and the tiles only carry their own value.
          RadioGroup<String?>(
            groupValue: chosen,
            // RadioGroup wants a handler rather than null while disabled, so
            // the joining guard sits inside it: once the join is under way a
            // tap changes nothing rather than being refused by the tile.
            onChanged: (value) {
              if (!joining) onChoose(value);
            },
            child: Column(
              children: [
                for (final place in waiting)
                  RadioListTile<String?>(
                    contentPadding: EdgeInsets.zero,
                    value: place.memberId,
                    title: Text(place.displayName),
                  ),
                const RadioListTile<String?>(
                  contentPadding: EdgeInsets.zero,
                  value: null,
                  title: Text("I'm not listed — add me"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // A guest arriving as somebody new has no name anywhere: not on their
        // account, and not on a placeholder they are declining to claim. The
        // server refuses the join rather than inventing one — "Someone" in a
        // ledger is worse than being asked — so this is where the asking
        // happens, and only in that case.
        if (name != null && chosen == null) ...[
          TextField(
            controller: name,
            autofocus: waiting.isEmpty,
            enabled: !joining,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => joining ? null : onJoin(),
            decoration: const InputDecoration(
              labelText: 'Your name',
              helperText: 'How the group will see you.',
            ),
          ),
          const SizedBox(height: 16),
        ],

        FilledButton(
          onPressed: joining ? null : onJoin,
          child: Text(joining ? 'Joining…' : 'Join group'),
        ),
        TextButton(
          onPressed: joining ? null : onSwitchAccount,
          child: const Text('Use a different account'),
        ),
        TextButton(
          onPressed: joining ? null : () => context.go('/'),
          child: const Text('Not now'),
        ),
      ],
    );
  }
}

/// Who is about to claim the place, and the chance to say it should not be you.
class _Claim extends ConsumerWidget {
  const _Claim({
    required this.preview,
    required this.joining,
    required this.onJoin,
    required this.onSwitchAccount,
  });

  final InvitePreview preview;
  final bool joining;
  final Future<void> Function() onJoin;
  final Future<void> Function() onSwitchAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider).value;

    // Nobody yet. The three ways to become somebody, then the claim happens
    // against whichever one they picked.
    if (account == null) {
      return IdentityChoices(
        onSignedIn: onJoin,
        guestNote:
            'You will join straight away and the group will synchronize. This '
            'device is the only way back into the guest account until you add '
            'an email address or Google account.',
      );
    }

    final me = ref.watch(myProfileProvider).value;
    final myName = me?.displayName?.trim() ?? '';
    final who = myName.isEmpty ? account.email ?? 'this device' : myName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: joining ? null : onJoin,
          child: Text('Join as ${preview.memberName}'),
        ),
        const SizedBox(height: 12),
        Text(
          // Stated plainly, because this is the moment somebody discovers they
          // opened a link meant for a different person. Claiming a place named
          // for somebody else is not forbidden — a placeholder is only ever
          // what a friend happened to type — but it should never happen by
          // accident.
          'You are signed in as $who. Joining puts you in the place '
          '${preview.inviterName} labelled “${preview.memberName}”.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: joining ? null : onSwitchAccount,
          child: const Text('Use a different account'),
        ),
        TextButton(
          onPressed: joining ? null : () => context.go('/'),
          child: const Text('Not now'),
        ),
      ],
    );
  }
}

/// A link that cannot be used, and why.
class _Dead extends StatelessWidget {
  const _Dead({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link_off, size: 40, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'This link did not work',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        action ??
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Go to your groups'),
            ),
      ],
    );
  }
}
