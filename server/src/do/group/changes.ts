import { and, asc, gt, lte, sql } from "drizzle-orm";
import type { SQLiteColumn } from "drizzle-orm/sqlite-core";

import * as schema from "../../db/group/schema";
import type { ChangePage } from "../../schemas/ledger";
import { readEntries } from "./ledger";
import { refuse } from "./refusal";
import { findMemberByProfile, findMeta, findTombstone, type Tx } from "./store";

/**
 * One group's changes since a cursor. `limit` counts changes, not rows: a
 * page is cut only between sequence numbers, so a write arrives whole.
 */
export function changesSince(tx: Tx, profileId: string, since: number, limit: number): ChangePage {
  const empty = { group: null, members: [], entries: [], events: [] };

  // A collected group answers anybody, and says only that it is gone.
  const grave = findTombstone(tx);
  if (grave) {
    return { ...empty, groupId: grave.groupId, seq: grave.seq, hasMore: false, purgedAt: since < grave.seq ? grave.purgedAt : null };
  }

  const meta = findMeta(tx);
  if (!meta) refuse("no_group", "No such group.");
  const member = findMemberByProfile(tx, profileId);
  if (!member) refuse("not_member", "You are not a member of this group.");

  // Somebody who left reads up to the change that recorded their leaving, and no further.
  const ceiling = member.leftAt === null ? Number.MAX_SAFE_INTEGER : member.seq;

  // One more than the page holds answers `hasMore` without a count.
  const moved = tx.all<{ seq: number }>(sql`
    select seq from (
      select seq from ${schema.meta}    where seq > ${since} and seq <= ${ceiling}
      union
      select seq from ${schema.members} where seq > ${since} and seq <= ${ceiling}
      union
      select seq from ${schema.entries} where seq > ${since} and seq <= ${ceiling}
      union
      select seq from ${schema.events}  where seq > ${since} and seq <= ${ceiling}
    )
    order by seq
    limit ${limit + 1}`);

  if (moved.length === 0) return { ...empty, groupId: meta.id, seq: since, hasMore: false, purgedAt: null };

  const hasMore = moved.length > limit;
  const upTo = moved.slice(0, limit).at(-1)?.seq ?? since;
  const window = (column: SQLiteColumn) => and(gt(column, since), lte(column, upTo));

  return {
    groupId: meta.id,
    seq: upTo,
    hasMore,
    purgedAt: null,
    // The group and member rows changed since the cursor ride on every page, even ahead of it:
    // this page's entries and events may name them, and a device's foreign keys need them first.
    group: meta.seq > since ? meta : null,
    members: tx
      .select()
      .from(schema.members)
      .where(and(gt(schema.members.seq, since), lte(schema.members.seq, ceiling)))
      .orderBy(asc(schema.members.seq))
      .all(),
    entries: readEntries(tx, tx.select().from(schema.entries).where(window(schema.entries.seq)).orderBy(asc(schema.entries.seq)).all()),
    events: tx.select().from(schema.events).where(window(schema.events.seq)).orderBy(asc(schema.events.seq), asc(schema.events.ordinal)).all(),
  };
}
