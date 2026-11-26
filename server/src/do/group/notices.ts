import { and, eq, inArray, isNull } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import { notifiableKinds, type PushData } from "../../schemas/ledger";
import { requireMeta, type Tx } from "./store";

/**
 * What the change committed at `seq` is worth waking somebody for, read from
 * what was actually appended rather than what the caller intended.
 */
export function pendingNotices(tx: Tx, seq: number): { message: PushData; recipients?: string[] }[] {
  const groupId = requireMeta(tx).id;
  const events = tx
    .select({ id: schema.events.id, kind: schema.events.kind, subjectId: schema.events.subjectId, entry: schema.events.entry })
    .from(schema.events)
    .where(and(eq(schema.events.seq, seq), inArray(schema.events.kind, [...notifiableKinds])))
    .all();
  return events.flatMap(({ id, kind, subjectId, entry }) => {
    if (subjectId === null) return [];
    const message: PushData = { groupId, eventId: id, kind, subjectId };
    if (entry?.kind !== "settlement") return [{ message }];

    const ids = [...new Set([...entry.payers, ...entry.shares].map(({ memberId }) => memberId))];
    const members = tx
      .select({ profileId: schema.members.profileId })
      .from(schema.members)
      .where(and(inArray(schema.members.id, ids), isNull(schema.members.leftAt)))
      .all();
    const recipients = members.flatMap(({ profileId }) => (profileId === null ? [] : [profileId]));
    return [{ message: { ...message, entryKind: "settlement" }, recipients }];
  });
}
