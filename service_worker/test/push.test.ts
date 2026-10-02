import assert from "node:assert/strict";
import { test } from "node:test";

import { DESCRIBE_PUSH, type DescribeReply, OPEN_GROUP } from "../src/messages.ts";
import { fallbackText, openGroup, showActivity, type WorkerScope } from "../src/push.ts";

const SCOPE = "https://example.test/app/";
const PUSH = { groupId: "group-1", eventId: "event-1", kind: "entry", subjectId: "entry-1" };

interface Shown {
  title: string;
  options: NotificationOptions | undefined;
}

/** A worker scope with the given tabs, recording what it shows, posts and opens. */
function worker(tabs: { url: string; reply?: DescribeReply }[] = []) {
  const shown: Shown[] = [];
  const posted: unknown[] = [];
  const opened: string[] = [];
  const focused: string[] = [];
  const clients = tabs.map(({ url, reply }) => ({
    url,
    focus: async () => {
      focused.push(url);
    },
    postMessage: (message: unknown, transfer?: MessagePort[]) => {
      posted.push(message);
      if (reply) transfer?.[0]?.postMessage(reply);
    },
  }));
  const scope = {
    registration: {
      scope: SCOPE,
      showNotification: async (title: string, options?: NotificationOptions) => {
        shown.push({ title, options });
      },
    },
    clients: {
      matchAll: async () => clients,
      openWindow: async (url: string) => {
        opened.push(url);
        return null;
      },
    },
  } as unknown as WorkerScope;
  return { scope, shown, posted, opened, focused };
}

test("a hidden tab words the notification, keyed on its subject", async () => {
  const { scope, shown, posted } = worker([{ url: `${SCOPE}g/group-1`, reply: { status: "show", title: "Lisbon", body: "Ana added dinner — €40.00." } }]);

  await showActivity(scope, PUSH);

  assert.deepEqual(posted, [{ type: DESCRIBE_PUSH, push: PUSH }]);
  assert.deepEqual(shown, [{ title: "Lisbon", options: { body: "Ana added dinner — €40.00.", icon: "/icons/Icon-192.png", tag: "entry-1", data: { groupId: "group-1" } } }]);
});

test("nothing is shown when the tab says there is nothing to show", async () => {
  const { scope, shown } = worker([{ url: SCOPE, reply: { status: "skip" } }]);

  await showActivity(scope, PUSH);

  assert.deepEqual(shown, []);
});

test("the worker words it itself when the tab could not", async () => {
  const { scope, shown } = worker([{ url: SCOPE, reply: { status: "failed" } }]);

  await showActivity(scope, PUSH);

  assert.equal(shown[0]?.title, fallbackText("entry").title);
  assert.equal(shown[0]?.options?.body, fallbackText("entry").body);
});

test("the worker words it itself when the tab never answers", async () => {
  const { scope, shown } = worker([{ url: SCOPE }]);

  await showActivity(scope, PUSH, 10);

  assert.equal(shown[0]?.options?.body, fallbackText("entry").body);
});

test("with no app tab open, the worker words it without asking anyone", async () => {
  // A landing-page tab on the same origin is not the app, and cannot answer.
  const { scope, shown, posted } = worker([{ url: "https://example.test/" }]);

  await showActivity(scope, { ...PUSH, kind: "member_joined" });

  assert.deepEqual(posted, []);
  assert.equal(shown[0]?.options?.body, "Someone joined one of your groups.");
});

test("a message without the contract's ids shows nothing", async () => {
  const { scope, shown } = worker();

  await showActivity(scope, { groupId: "group-1" });

  assert.deepEqual(shown, []);
});

test("a tap opens the group in the tab that is already open", async () => {
  const { scope, posted, focused, opened } = worker([{ url: `${SCOPE}settings` }]);

  await openGroup(scope, "group-1");

  assert.deepEqual(focused, [`${SCOPE}settings`]);
  assert.deepEqual(posted, [{ type: OPEN_GROUP, groupId: "group-1" }]);
  assert.deepEqual(opened, []);
});

test("a tap with no app tab open opens the group's deep link", async () => {
  const { scope, opened } = worker();

  await openGroup(scope, "group 1");

  assert.deepEqual(opened, [`${SCOPE}g/group%201`]);
});
