# Group lifecycle

Active membership grants access to the current group. Leaving ends that access.
There is no archive preference, closed state, past-groups screen or departure
snapshot. The member's `leftAt` records participation; it is not an entitlement
to read the group's history.

## Leaving and retention

A departing member must be settled in every currency. Their member row and
financial records remain for the other participants. They can rejoin through a
valid link and then see the group's current data, including its history.

If the last active account holder leaves, the entire group must be settled,
including placeholders. The same transaction deletes the group and its financial
records, revokes its links and stages removal of its discovery index. A minimal
tombstone prevents old clients or queued writes from recreating a deleted group.
Leaving requires confirmation, which explains lost access and, for the last
account holder, permanent deletion. Users can export before leaving.

A group's age never deletes it. Only active account holders keep it alive;
placeholders and former members cannot access or manage it. The object's alarm
exists only for outstanding index delivery retries.

## Account deletion

Deleting an account changes its member into an ordinary placeholder under its
last display name. Existing departure status is preserved. Active placeholders
can receive expenses and be claimed. Balances and shared records remain for
other active account holders. If no active account holder remains, the group is
permanently deleted. Account deletion does not require settlement.

Guest-to-account transfer moves active access with the person. If the account
already has a departed member row, signing in as an active guest restores that
account's access and leaves the guest's separate financial identity as a
placeholder, just as for other duplicate memberships.

## Offline changes and concurrency

Leaving is queued locally. The group disappears from the list and all its
routes become unavailable immediately. The cache remains only until the server
acknowledges departure, after which the group, related financial data and queued
edits are removed together. Other devices remove their copies when they next
sync and receive `not_member` or a deletion tombstone. An offline device cannot
learn about a departure on another device until it reconnects.

A retry after a lost leave response either acknowledges the already-departed
member or sees the deleted-group tombstone; both remove the local cache. If the
server refuses a departure because a newer balance or member update intervened,
the local member is made active again and the refusal is shown for review.
Discarding the refused change refreshes the authoritative state before a new
attempt. Access loss itself does not create a retryable sync conflict.

Group settings and member updates carry their base sequence. Stale edits are
refused instead of overwriting newer versions. Expense conflicts keep their
existing explicit conflict workflow. Repository writes and every group route
check membership. Applying server responses checks the sync session inside the
same database transaction, so sign-out cannot be undone by an in-flight response.

## Schema

The current schema has no archive column and includes outbox refusal categories.
The local ledger starts at schema version 1 in `opensplit-v1-<accountId>`.
Old `opensplit-<accountId>` databases remain untouched and unused, including
their cursors and queued edits. The updated app synchronizes a fresh ledger
from the server. Only the new v1 snapshot is retained. The server group schema
is one initial migration, with no archive column or inactivity schedules.
No lifecycle tables or history copies are introduced. Unversioned API requests
never reach account or group handlers.

Regression coverage includes create/delete/last departure, lost leave responses,
offline departure and access loss, rejected departures, rejoining current data,
stale writes, account deletion, placeholder claiming, local storage isolation and
inaccessible group routes.
