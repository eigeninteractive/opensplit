import { and, asc, gt, lte, sql } from "drizzle-orm";
import type { SQLiteColumn } from "drizzle-orm/sqlite-core";

import * as schema from "../../db/group/schema";
import type { ChangePage } from "../../schemas/ledger";
import { readEntries } from "./ledger";
import { refuse } from "./refusal";
import { findMemberByProfile, findMeta, findTombstone, type Tx } from "./store";

/**
 * One group's changes since a cursor. One request, one integer.
 *
 * What this replaces is worth stating, because none of it was bad code. It was
 * the cost of paging a multi-writer store by timestamp: four requests per
 * group per sync, each with an `(updated_at, id)` keyset cursor; a row-value
 * comparison spelled out by hand because PostgREST has no syntax for
 * `(updated_at, id) > (?, ?)`; a quoting rule that made an unquoted ISO-8601
 * timestamp inside an `or=(…)` group silently match nothing; `ascending: true`
 * stated explicitly because the SDK defaults to descending; and the whole
 * class of bug where a row bumped mid-sweep moves past a cursor that has
 * already passed it.
 *
 * A single writer can hand out a strictly increasing integer, so all of that
 * becomes `where seq > ?`.
 */

const CHANGE_LIMIT = { min: 1, max: 500, fallback: 200 } as const;

/**
 * `limit` counts changes, not rows.
 *
 * Every row written by one call shares one sequence number, and a page is cut
 * only between numbers — never inside one. So a device sees a whole write or
 * none of it, and can never observe an entry whose shares have not arrived,
 * which would be a balance that does not add up on somebody's screen.
 */
export function changesSince(tx: Tx, profileId: string, since: number, requestedLimit: number): ChangePage {
  const empty = { group: null, members: [], entries: [], events: [] };

  /**
   * A collected group answers anybody, and says only that it is gone.
   *
   * There is no membership to check — the members were deleted with everything
   * else — and nothing here to protect: a tombstone carries a timestamp and a
   * sequence number. Refusing instead would leave every device that still
   * holds a copy of a year-dead group holding it forever.
   */
  const grave = findTombstone(tx);
  if (grave) {
    return { ...empty, groupId: grave.groupId, seq: grave.seq, hasMore: false, purgedAt: since < grave.seq ? grave.purgedAt : null };
  }

  const meta = findMeta(tx);
  if (!meta) refuse("no_group", "No such group.");

  const member = findMemberByProfile(tx, profileId);
  if (!member) refuse("not_member", "You are not a member of this group.");

  /**
   * Somebody who has left reads up to the change that recorded them leaving,
   * and no further.
   *
   * Both of the obvious answers are wrong. Cutting them off at once — which is
   * what `is_group_member`'s `left_at is null` did — means their device never
   * learns why syncing stopped, so the app shows a group they are no longer in
   * until somebody reinstalls. Letting them read on means removal removes
   * nothing: the person most worth removing keeps watching the ledger.
   *
   * A total order over the group's history makes the third answer expressible,
   * and it is the honest one: everything up to and including your removal is
   * yours, because you were there for it. After that the feed is quiet.
   */
  const ceiling = member.leftAt === null ? Number.MAX_SAFE_INTEGER : member.seq;

  const limit = Math.min(Math.max(requestedLimit || CHANGE_LIMIT.fallback, CHANGE_LIMIT.min), CHANGE_LIMIT.max);

  /**
   * Which sequence numbers moved, across every table that carries one.
   *
   * Asking for one more than the page holds is what answers `hasMore` without
   * a second count over the same four tables.
   */
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

  if (moved.length === 0) {
    return { ...empty, groupId: meta.id, seq: since, hasMore: false, purgedAt: null };
  }

  const hasMore = moved.length > limit;
  const page = hasMore ? moved.slice(0, limit) : moved;
  const upTo = page[page.length - 1]?.seq ?? since;

  const window = (column: SQLiteColumn) => and(gt(column, since), lte(column, upTo));

  const entryRows = tx.select().from(schema.entries).where(window(schema.entries.seq)).orderBy(asc(schema.entries.seq)).all();

  return {
    groupId: meta.id,
    seq: upTo,
    hasMore,
    purgedAt: null,
    group: meta.seq > since && meta.seq <= upTo ? meta : null,
    members: tx.select().from(schema.members).where(window(schema.members.seq)).orderBy(asc(schema.members.seq)).all(),
    entries: readEntries(tx, entryRows),

    /**
     * Ordered by `rowid` within a sequence number, which is insertion order
     * and therefore commit order. One change can append more than one line —
     * a patch that renames and archives a group is two things that happened —
     * and a feed that shows them in an arbitrary order is a feed that
     * occasionally reads backwards.
     */
    events: tx.select().from(schema.events).where(window(schema.events.seq)).orderBy(asc(schema.events.seq), sql`rowid`).all(),
  };
}
