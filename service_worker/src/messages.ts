/**
 * The messages the worker and the Flutter page exchange. The Dart side spells
 * the same strings in lib/data/push/web_push_bridge_web.dart and
 * lib/data/web/release_updates_web.dart.
 */

/** Worker to page: sync this push's group and word it, replying on the port. */
export const DESCRIBE_PUSH = "opensplit:describe-push";

/** Worker to page: a notification about this group was tapped. */
export const OPEN_GROUP = "opensplit:open-group";

/** Page to worker: the person chose to restart into the waiting release. Workbox's own name for it. */
export const SKIP_WAITING = "SKIP_WAITING";

/** What the page answers a {@link DESCRIBE_PUSH} with. */
export type DescribeReply =
  /** Show this; it is what the app itself would say. */
  | { status: "show"; title: string; body: string }
  /** Nothing worth a banner, or nobody signed in to show it to. */
  | { status: "skip" }
  /** The page could not work it out; the worker says what it can on its own. */
  | { status: "failed" };
