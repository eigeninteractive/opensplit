import type { Account, IdentityOutcome } from "../schemas/identity";

/** Whether the device's ledger stayed with the session, settled by comparing account ids. */
export function outcomeFor(account: Account, previousUserId: string | null, token: string | null): IdentityOutcome {
  const replaced = previousUserId !== null && previousUserId !== account.id;
  return { outcome: replaced ? "replaced" : "kept", account, token, strandedUserId: replaced ? previousUserId : null };
}

/** The anonymous plugin's invented address. */
const PLACEHOLDER_DOMAIN = "@anonymous.placeholder.invalid";

/**
 * Better Auth's user as the app sees it. A guest reports no email and no name,
 * so "has no name of its own" stays true for them.
 */
export function toAccount(user: { id: string; email?: string | null; name?: string | null; isAnonymous?: boolean | number | null }): Account {
  const isAnonymous = Boolean(user.isAnonymous);
  const email = user.email && !user.email.endsWith(PLACEHOLDER_DOMAIN) ? user.email : null;
  return { id: user.id, isAnonymous, email, displayName: isAnonymous ? null : user.name?.trim() || null };
}
