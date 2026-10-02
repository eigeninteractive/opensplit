import 'package:material_ui/material_ui.dart';

import 'conflicting_edit_banner.dart';
import 'link_account_prompt.dart';
import 'pull_to_sync.dart';
import 'sync_status_notice.dart';
import 'unsynced_changes_banner.dart';

/// One scrolling half of a group's screen, under its collapsing header.
///
/// A [NestedScrollView] lays each pane out as if the pinned header were not
/// there, so the pane starts by taking back the space the header covers.
class GroupPane extends StatelessWidget {
  const GroupPane({
    super.key,
    required this.groupId,
    required this.storageKey,
    required this.slivers,
    this.showsBanners = true,
  });

  final String groupId;

  /// Keeps this pane's scroll offset while the other tab is showing.
  final String storageKey;

  final List<Widget> slivers;

  /// Whether the group's notices head this pane. Both tabs carry them, since
  /// a write the server refused makes the expenses and the balances wrong
  /// together; side by side, only the first does.
  final bool showsBanners;

  @override
  Widget build(BuildContext context) => PullToSync.group(
    groupId,
    child: CustomScrollView(
      key: PageStorageKey(storageKey),
      // Always scrollable, so there is a pull to sync even on a short list.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        if (showsBanners) const _Banners(),
        ...slivers,
        // Room to scroll the last row out from under the floating button.
        const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
      ],
    ),
  );
}

/// The group's notices, each of which takes no room until it has something to
/// say.
class _Banners extends StatelessWidget {
  const _Banners();

  static const _padding = EdgeInsets.fromLTRB(16, 8, 16, 0);

  @override
  Widget build(BuildContext context) => const SliverToBoxAdapter(
    child: Column(
      children: [
        UnsyncedChangesBanner(padding: _padding),
        ConflictingEditBanner(padding: _padding),
        SyncStatusBanner(padding: _padding),
        LinkAccountPrompt(padding: _padding),
      ],
    ),
  );
}
