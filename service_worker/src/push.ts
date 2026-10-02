import { DESCRIBE_PUSH, type DescribeReply, OPEN_GROUP } from "./messages.ts";

/**
 * Web push, for the cases the page cannot handle by itself.
 *
 * Firebase hands a push to the page whenever a tab is visible, and the page
 * syncs and redraws. Everything here is for the other cases: a tab that is
 * open but hidden, and no tab at all. The browser expects every push to end
 * in a notification, and will show its own "updated in the background" one
 * if this does not.
 *
 * The wording belongs to the app, which syncs first and then describes what
 * is on the device with the same formatter its screens use. A worker cannot
 * run Dart, so it borrows a hidden tab to do that, and only words the
 * notification itself when there is no tab to ask.
 */

/** The server's data-only message: ids, never text. See server/src/push/fcm.ts. */
export interface PushData {
  groupId: string;
  eventId: string;
  kind: string;
  subjectId: string;
}

export interface NotificationText {
  title: string;
  body: string;
}

/** The parts of the worker's global scope this needs, so tests can supply them. */
export type WorkerScope = Pick<ServiceWorkerGlobalScope, "clients" | "registration">;

/** How long a hidden tab gets to sync and answer. Background tabs are throttled, so not short. */
const DESCRIBE_TIMEOUT_MS = 15_000;

/** Reads FCM's data map, or null for a message this release does not understand. */
export function readPushData(data: Record<string, string> | undefined): PushData | null {
  const { groupId, eventId, kind, subjectId } = data ?? {};
  if (!groupId || !eventId || !kind || !subjectId) return null;
  return { groupId, eventId, kind, subjectId };
}

/**
 * What the worker can honestly say on its own: what kind of thing happened,
 * and nothing it would have to guess at, such as amounts or names.
 */
export function fallbackText(kind: string): NotificationText {
  const body = {
    entry: "An expense in one of your groups changed.",
    member_joined: "Someone joined one of your groups.",
    member_left: "Someone left one of your groups.",
  }[kind];
  return { title: "OpenSplit", body: body ?? "There is new activity in one of your groups." };
}

/** Shows the notification for a push that arrived with no visible tab. */
export async function showActivity(scope: WorkerScope, data: Record<string, string> | undefined, timeoutMs = DESCRIBE_TIMEOUT_MS): Promise<void> {
  const push = readPushData(data);
  if (!push) return;

  const tab = await appTab(scope);
  const reply = tab ? await askToDescribe(tab, push, timeoutMs) : null;
  if (reply?.status === "skip") return;

  const text = reply?.status === "show" ? { title: reply.title, body: reply.body } : fallbackText(push.kind);
  await scope.registration.showNotification(text.title, {
    body: text.body,
    icon: "/icons/Icon-192.png",
    // Keyed on the subject, as on Android, so five edits to one expense
    // replace each other rather than stacking into five banners.
    tag: push.subjectId,
    data: { groupId: push.groupId },
  });
}

/** Opens the group a tapped notification was about, in a tab that already exists if there is one. */
export async function openGroup(scope: WorkerScope, groupId: string): Promise<void> {
  const tab = await appTab(scope);
  if (tab) {
    await tab.focus();
    tab.postMessage({ type: OPEN_GROUP, groupId });
    return;
  }
  // The app's groupNotificationRoute, under the /app/ base.
  await scope.clients.openWindow(new URL(`g/${encodeURIComponent(groupId)}`, scope.registration.scope).href);
}

/** The group a notification this worker showed is about, or null for one it did not show. */
export function groupOf(notification: Notification): string | null {
  const groupId: unknown = notification.data?.groupId;
  return typeof groupId === "string" ? groupId : null;
}

/** The most recently focused tab of the app, hidden or not. */
async function appTab(scope: WorkerScope): Promise<WindowClient | undefined> {
  const windows = await scope.clients.matchAll({ type: "window", includeUncontrolled: true });
  return windows.find((client) => client.url.startsWith(scope.registration.scope));
}

/** Asks a tab to sync and word a push. Null when it did not answer in time. */
async function askToDescribe(tab: WindowClient, push: PushData, timeoutMs: number): Promise<DescribeReply | null> {
  const channel = new MessageChannel();
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      new Promise<DescribeReply>((resolve) => {
        channel.port1.onmessage = (event: MessageEvent<DescribeReply>) => resolve(event.data);
        tab.postMessage({ type: DESCRIBE_PUSH, push }, [channel.port2]);
      }),
      new Promise<null>((resolve) => {
        timer = setTimeout(() => resolve(null), timeoutMs);
      }),
    ]);
  } finally {
    clearTimeout(timer);
    channel.port1.close();
  }
}
