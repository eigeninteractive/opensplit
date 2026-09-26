import { and, eq, inArray, isNotNull, isNull, ne } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import { notifiableKinds, type PushData } from "../../schemas/ledger";
import { requireMeta, type Tx } from "./store";

export interface Notice {
  data: PushData;
  /** Who to wake: account holders still here, minus whoever made the change. */
  profileIds: string[];
}

/**
 * What the change committed at `seq` is worth waking somebody for, read from
 * what was actually appended rather than what the caller intended.
 */
export function pendingNotices(tx: Tx, seq: number, actorProfileId: string): Notice[] {
  const events = tx
    .select({ id: schema.events.id, kind: schema.events.kind, subjectId: schema.events.subjectId })
    .from(schema.events)
    .where(and(eq(schema.events.seq, seq), inArray(schema.events.kind, [...notifiableKinds])))
    .all();
  if (events.length === 0) return [];

  const profileIds = tx
    .select({ profileId: schema.members.profileId })
    .from(schema.members)
    .where(and(isNotNull(schema.members.profileId), isNull(schema.members.leftAt), ne(schema.members.profileId, actorProfileId)))
    .all()
    .flatMap((row) => (row.profileId === null ? [] : [row.profileId]));
  if (profileIds.length === 0) return [];

  const groupId = requireMeta(tx).id;
  return events.flatMap((event) => (event.subjectId === null ? [] : [{ data: { groupId, eventId: event.id, kind: event.kind, subjectId: event.subjectId }, profileIds }]));
}
