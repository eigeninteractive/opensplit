import { sql } from "drizzle-orm";

import type { Tx } from "./store";

/**
 * The one thing this server computes about money.
 *
 * Balances, debt simplification, split arithmetic and analytics are all on the
 * device, and that is what keeps a group's Durable Object cheap enough to be
 * free. This fold exists because two decisions cannot be made on a device at
 * all: whether somebody is settled enough to be removed by *somebody else*,
 * and whether a year-silent group is finished enough to collect. Both are
 * answers about the whole group, given to a caller who must not be able to
 * supply them.
 *
 * Grouped by currency, because a group can legitimately hold a ₹500 balance
 * and a €20 balance at once. Collapsing them into one display currency is a
 * screen's job, never the model's.
 *
 * Only non-zero positions come back, so "no rows" is the definition of
 * settled — which is the same definition removal and collection both use, from
 * the same query, rather than two subtly different ideas of it.
 */
export interface Position {
  memberId: string;
  currency: string;
  /** Positive: this member is owed. Negative: this member owes. */
  balanceMinor: number;
}

/**
 * Deleted entries are excluded, and that is the entire reason deletion is
 * soft. A hard delete would take the payers and shares with it and reach the
 * same total, but it would also vanish from the change feed and strand the row
 * on every device that had already synced it.
 */
const positions = sql`
  select member_id as memberId, currency, sum(delta) as balanceMinor
    from (
      select p.member_id, e.currency, p.amount_minor as delta
        from entry_payers p join entries e on e.id = p.entry_id
       where e.deleted_at is null
      union all
      select s.member_id, e.currency, -s.amount_minor
        from entry_shares s join entries e on e.id = s.entry_id
       where e.deleted_at is null
    )
   group by member_id, currency
  having sum(delta) <> 0`;

/** Everybody who still owes or is owed anything, in any currency. */
export function outstanding(tx: Tx): Position[] {
  return tx.all<Position>(positions);
}

/** Whether this member has an open position in any currency. */
export function isSettled(tx: Tx, memberId: string): boolean {
  return !outstanding(tx).some((position) => position.memberId === memberId);
}

/** Whether anybody does. */
export function isGroupSettled(tx: Tx): boolean {
  return outstanding(tx).length === 0;
}
