import { and, isNotNull, isNull } from "drizzle-orm";

import { members } from "../../db/group/schema";
import { positionsByMember } from "./balances";
import type { Tx } from "./store";
import { scheduleAt, scheduledAt, unschedule } from "./upkeep";

export const SETTLEMENT_NUDGE_DELAY_MS = 7 * 24 * 60 * 60 * 1000;

function outstandingDebtors(tx: Tx): string[] {
  const positions = positionsByMember(tx);
  const active = tx
    .select({ id: members.id, profileId: members.profileId })
    .from(members)
    .where(and(isNull(members.leftAt), isNotNull(members.profileId)))
    .all();
  const debtors: string[] = [];
  for (const { id, profileId } of active) {
    if (profileId !== null && [...(positions.get(id)?.values() ?? [])].some((amount) => amount < 0)) {
      debtors.push(profileId);
    }
  }
  return debtors;
}

/** Start the group's weekly check when it has debtors and no check scheduled. */
export function ensureSettlementNudge(tx: Tx, now: number): void {
  if (scheduledAt(tx, "settlement-nudge") !== null || outstandingDebtors(tx).length === 0) return;
  scheduleAt(tx, "settlement-nudge", now + SETTLEMENT_NUDGE_DELAY_MS);
}

/** Recheck current balances and advance the deadline before dispatching pushes. */
export function takeSettlementNudge(tx: Tx, now: number): string[] {
  const due = scheduledAt(tx, "settlement-nudge");
  if (due === null || due > now) return [];
  const debtors = outstandingDebtors(tx);
  if (debtors.length === 0) unschedule(tx, "settlement-nudge");
  else scheduleAt(tx, "settlement-nudge", now + SETTLEMENT_NUDGE_DELAY_MS);
  return debtors;
}
