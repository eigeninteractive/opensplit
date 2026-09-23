/**
 * What attaching an identity did — the one question a caller actually has.
 *
 * "Did this device's ledger stay with the account?" cannot be inferred from
 * which code path ran, and that is why it is decided here rather than on the
 * device. Signing in with Google using the address an existing email account
 * already owns lands on *that same account*: the sign-in branch ran and yet
 * nothing moved. Only the resulting id settles it.
 *
 * These names match the Dart sum type in `domain/repositories/auth_service.dart`
 * deliberately. That contract was hard-won — it exists because an earlier
 * version silently replaced sessions and stranded people's groups under an
 * account they could never sign into again — and moving backends does not
 * change what the app needs to know.
 */
export type IdentityOutcome =
  | {
      outcome: "kept";
      account: Account;
    }
  | {
      outcome: "replaced";
      account: Account;
      /**
       * The account this device's local database still belongs to. Which
       * database was left behind is the only part of the transition a caller
       * can act on.
       */
      strandedUserId: string;
    };

export interface Account {
  id: string;
  isAnonymous: boolean;
  email: string | null;
  displayName: string | null;
}

/**
 * Which of the two just happened, worked out from the ids rather than assumed.
 */
export function outcomeFor(account: Account, previousUserId: string | null): IdentityOutcome {
  if (previousUserId === null || previousUserId === account.id) {
    return { outcome: "kept", account };
  }
  return { outcome: "replaced", account, strandedUserId: previousUserId };
}

/**
 * The address the anonymous plugin invents for a guest.
 *
 * Never shown, never a real inbox, and never reported to the client as an
 * email — a guest who sees `a1b2c3@anonymous.placeholder.invalid` on their
 * account screen would reasonably think they had signed up with it.
 */
const PLACEHOLDER_DOMAIN = "@anonymous.placeholder.invalid";

export function toAccount(user: {
  id: string;
  email?: string | null;
  name?: string | null;
  // SQLite has no boolean, so a row read straight from D1 carries 0 or 1 here
  // while Better Auth's own objects carry a boolean. Both are accepted rather
  // than converted at every call site.
  isAnonymous?: boolean | number | null;
}): Account {
  const email = user.email ?? null;
  return {
    id: user.id,
    isAnonymous: Boolean(user.isAnonymous),
    email: email && !email.endsWith(PLACEHOLDER_DOMAIN) ? email : null,
    displayName: user.name?.trim() || null,
  };
}
