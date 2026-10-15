# API retirement and app updates

`server/src/paths.ts` defines one numeric `currentApiVersion` and derives the
single supported application API base, `/api/vN`. Positive integer versions
below it are retired and receive HTTP 410 with the stable `update_required`
error and `Cache-Control: no-store`, before reaching account or ledger services.

Unversioned paths, malformed versions, unavailable future versions and unknown
operations within the current version return ordinary `404 / not_found`.
At the v1 baseline, no numbered API has been retired yet. Old unversioned apps
cannot reach data handlers and receive no special upgrade handling.

For example, when the current version becomes 2:

| Request | Result |
| --- | --- |
| `/api/v1/...` | `410 / update_required` |
| Valid `/api/v2/...` operation | Normal handling |
| Unknown `/api/v2/...` operation | `404 / not_found` |
| `/api/v3/...` | `404 / not_found` |
| Unversioned `/api/...` | `404 / not_found` |

The client never guesses incompatibility from an arbitrary 404, redirects an
old request, or changes its own API version.

## Read-only access

One `ApiAccess` flag is shared by the client, local write queue and UI.
An explicit `update_required` refusal turns it on and remembers it in preferences,
keyed by the backend origin and API base. Restarting offline therefore keeps
editing disabled. A compatible app uses the new API base and a fresh flag.
There is no rollback recovery, periodic compatibility probe, extra endpoint or
database schema. Before the first refusal, ordinary offline use still works.

Once refused, the app stops network requests and automatic sync, disables edits,
and keeps saved groups, expenses, payments, history and exports readable. The
persistent notice offers Update OpenSplit. A queued write is neither
acknowledged nor dead-lettered because of retirement; its contents and retry
metadata stay untouched. The queue also checks the flag inside the caller's
transaction so a stale editor cannot commit a new financial edit. Background
sync observes the same refusal and leaves pending work intact.

## Pending edits after an app update

Expenses and their outbox markers are saved together in the local database.
An outbox item identifies a local record; it does not store an HTTP request
addressed to an old API. After updating, the current client reads that record
and builds a request for its own contract.

Preserving an edit during retirement does not guarantee that a newer API will
accept it. A URL or request-format change may need only a new request mapping.
A change to the stored model or its meaning needs a release-specific migration
before synchronization resumes. Future upgrades must retain the same database
name and migrate pending data rather than reset the ledger.

Every breaking release must test upgrading supported old database versions with
pending edits, including relevant creates, updates, deletions and dependencies.
Verify amounts, participants, IDs and queue ordering survive, then exercise the
new API mapping and its success, conflict and refusal responses. No generic
cross-version command format or conversion framework is provided.

If an edit cannot be translated safely, that release needs explicit handling
that keeps it available and explains the correction or manual recovery needed.
The retirement flag does not implement this. Today a permanent server refusal
uses the failed-change UI, a stale expense keeps an attempted snapshot as a
conflict, and a local serialization error can enter automatic retry handling.
Do not ship a breaking release that leaves old pending records in that retry
loop or silently discards them.

The existing access policy still applies: confirmed loss of membership or group
deletion clears that group's cached data and pending edits. The initial
storage baseline intentionally abandons the earlier database and its
queue; it does not transfer old offline work into the new baseline.

## Installing the update

Android reuses `AppUpdateService` and the existing `in_app_update` plugin. The
required-update action checks Play and starts or resumes an immediate update
when allowed, regardless of release priority. Unavailability or failure opens
the Play listing. Canceling keeps the app read-only and leaves Update available.
An update must be released to that user before Play can install it.

Ordinary optional update offers still check Play on launch and, with a four-hour
interval, on resume. Priority 4 or above selects the immediate flow if Play
permits it; priority alone does not enforce compatibility.

Web checks the service worker for a release, waits for installation, sends
`SKIP_WAITING`, and reloads after controller change. A release already activated
by another tab only needs a reload. If no new release is available, the notice
stays and the user can try again. OPFS, saved edits and browser app storage are
not cleared. The existing optional Restart offer remains available as well.

Already installed old builds cannot gain this handling from a server response.
Their unsupported requests are refused safely, but the clear notice and queue
preservation behavior only exist in clients that ship this implementation.

## Release policy

The app version, API contract version and local schema version are independent.
Compatible API changes keep the same API base. Future local schema migrations
keep `opensplit-v1-<accountId>` and increment the Drift schema version inside it.

For future production retirements, make a compatible app available before
removing its predecessor, or accept the period in which users cannot connect.
An update prompt cannot shorten Play review or install an unreleased build.

See [Google Play in-app updates](https://developer.android.com/guide/playcore/in-app-updates),
[availability and cancellation](https://developer.android.com/guide/playcore/in-app-updates/kotlin-java),
and [Workbox update activation](https://developer.chrome.com/docs/workbox/handling-service-worker-updates).
