import { and, eq, inArray, isNull, ne, sql } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { Notice } from "../../push/fcm";
import { currentSeq, type Tx } from "./store";

/**
 * What the change just committed is worth waking somebody for.
 *
 * Read **after** the write, from what was actually appended, rather than
 * assembled by each write method as it goes. That is the point: a method knows
 * what it intended to record, and `append` knows what it recorded — and those
 * differ, because an edit that changes nothing writes no event at all. Reading
 * the feed back means a notification can only ever describe something that
 * really happened.
 *
 * Everything at the current sequence number is what this call wrote. One change
 * is one `seq`, handed out once per call by `nextSeq`, so there is no window
 * here and no need to pass anything between the transaction and this.
 */

/**
 * The three kinds that reach a lock screen.
 *
 * An expense, somebody arriving, somebody leaving. Not renames, archives or
 * links: those belong in the activity feed, which is read on purpose. A
 * notification nobody wanted is how notifications stop being read at all — and
 * `link_created` in particular would wake a whole group to say that one of them
 * tapped Share.
 */
const NOTIFIABLE = ["entry", "member_joined", "member_left"] as const;

type NotifiableKind = (typeof NOTIFIABLE)[number];

export function pendingNotices(tx: Tx, groupId: string, actorProfileId: string | null): Notice[] {
  const seq = currentSeq(tx);
  if (seq === 0) return [];

  const events = tx
    .select({ id: schema.events.id, kind: schema.events.kind, subjectId: schema.events.subjectId })
    .from(schema.events)
    .where(and(eq(schema.events.seq, seq), inArray(schema.events.kind, [...NOTIFIABLE])))
    .all();

  if (events.length === 0) return [];

  /**
   * Everybody with an account who is still here, minus whoever did it.
   *
   * The **actor** is excluded, not the author. On an edit those are usually
   * different people, and the author is precisely who needs to hear that
   * somebody changed their expense.
   *
   * Placeholders have no account and so no device; somebody who has left has
   * stopped reading this group. Both fall out of the same predicate.
   */
  const recipients = tx
    .select({ profileId: schema.members.profileId })
    .from(schema.members)
    .where(and(sql`${schema.members.profileId} is not null`, isNull(schema.members.leftAt), actorProfileId === null ? sql`1 = 1` : ne(schema.members.profileId, actorProfileId)))
    .all()
    .map((row) => row.profileId)
    .filter((id): id is string => id !== null);

  if (recipients.length === 0) return [];

  return events.map((event) => ({
    groupId,
    eventId: event.id,
    kind: event.kind as NotifiableKind,
    subjectId: event.subjectId,
    profileIds: recipients,
  }));
}
