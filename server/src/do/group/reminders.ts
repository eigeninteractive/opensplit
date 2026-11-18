import { positionsByMember } from "./balances";
import { refuse } from "./refusal";
import { requireMember, type Tx, type WriteContext } from "./store";

/** Who a reminder goes from and to, once the group has agreed it may be sent. */
export interface ReminderRoute {
  fromMemberId: string;
  toProfileId: string;
}

/**
 * Whether the caller may remind `memberId` about `currency`: only somebody
 * who is owed may ask, and only somebody who owes, is still here and has an
 * account can be asked. Positions are net, as everywhere on the server, so
 * this does not say who should pay whom: the device works that out.
 */
export function reminderRoute(tx: Tx, memberId: string, currency: string, { actor }: WriteContext): ReminderRoute {
  const target = requireMember(tx, memberId);
  if (target.id === actor.id) refuse("forbidden", "You cannot remind yourself.");
  if (target.leftAt !== null) refuse("forbidden", "They are no longer in this group.");
  if (target.profileId === null) refuse("forbidden", "They have not joined with an account, so there is nobody to notify.");

  const positions = positionsByMember(tx);
  const owed = positions.get(actor.id)?.get(currency) ?? 0;
  const owes = positions.get(target.id)?.get(currency) ?? 0;
  if (owed <= 0 || owes >= 0) refuse("forbidden", "They do not owe you anything in that currency.");

  return { fromMemberId: actor.id, toProfileId: target.profileId };
}
