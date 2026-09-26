import { sql } from "drizzle-orm";

import type { Tx } from "./store";

/**
 * The one thing the server computes about money, for the two decisions a
 * device cannot be trusted with: removing somebody else, and collecting a
 * dormant group. Per currency; only non-zero positions, so no rows is settled.
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

interface Position {
  memberId: string;
  currency: string;
  balanceMinor: number;
}

function outstanding(tx: Tx): Position[] {
  return tx.all<Position>(positions);
}

export function isSettled(tx: Tx, memberId: string): boolean {
  return !outstanding(tx).some((position) => position.memberId === memberId);
}

export function isGroupSettled(tx: Tx): boolean {
  return outstanding(tx).length === 0;
}
