import { DurableObject } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { drizzle as drizzleD1 } from "drizzle-orm/d1";
import { type DrizzleSqliteDODatabase, drizzle } from "drizzle-orm/durable-sqlite";
import { migrate } from "drizzle-orm/durable-sqlite/migrator";

import * as d1 from "../../db/d1/schema";
import * as schema from "../../db/group/schema";
import { wakeDevices } from "../../push/fcm";
// `Group` is the wire shape of a group and also the name of the class below,
// which wrangler binds by name. The record is the one that gets the alias.
import type { ChangePage, Entry, EntryInput, GroupCreate, GroupLink, Group as GroupRecord, GroupUpdate, Invite, LinkPreview, LinkRevocation, LiveLink, Member, MemberCreate, MemberUpdate, Placeholder } from "../../schemas/ledger";
import { changesSince } from "./changes";
import { createGroupLink, createInvite, join, liveLink, peek, placeholders, revokeGroupLink } from "./invites";
import { deleteEntry, restoreEntry, upsertEntry } from "./ledger";
import migrations from "./migrations/migrations";
import { pendingNotices } from "./notices";
import { attempt, type Result } from "./refusal";
import { addMember, createGroup, forgetProfile, updateGroup, updateMember } from "./roster";
import { nowIso, requireActiveMember, requireMeta, type Tx } from "./store";
import { backoffOutbox, clearOutbox, nextDue, type OutboxRow, pendingOutbox, restageAllMemberships, restageLiveTokens, runDormancy, stageLinkToken, stageMembership, stagePurge, touchDormancy, type UpkeepOutcome } from "./upkeep";

/**
 * One group's ledger, and the authorization boundary for it.
 *
 * A Durable Object processes one request at a time and owns exactly one
 * group's rows. Three rules that are awkward anywhere else are ordinary code
 * here: the balance invariant is a function call with the finished shape in
 * hand, the column guards are comparisons with real before-and-after values,
 * and "are you a member" is reading its own table.
 *
 * Being the only writer also buys a strictly increasing sequence number per
 * group, for free. The change feed is cursored on it.
 *
 * ## Every method takes a profile id, and none takes a member id for "me"
 *
 * The Worker resolves the session and passes the profile id. This object
 * resolves that to its own member row and uses it for authorship. There is
 * deliberately no parameter for who the caller claims to be, so there is
 * nothing to spoof and nothing to check.
 *
 * The Worker also consults D1's membership index first, and that check exists
 * to fail cheap rather than to decide. **This object re-checks membership
 * itself and is the authority.**
 *
 * ## Refusals are values
 *
 * Every method returns `Result<T>`. A refusal is an answer the object is meant
 * to give; an exception is a bug. See `refusal.ts`.
 */
export class Group extends DurableObject<Env> {
  private readonly db: DrizzleSqliteDODatabase<typeof schema>;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.db = drizzle(ctx.storage, { schema, logger: false });

    /**
     * Migrations are lazy and per object: a group nobody has touched for six
     * months migrates on its next open, not on deploy. There is no
     * `wrangler d1 migrations apply` for a Durable Object and there could not
     * be — the objects are created on demand, live in different places, and
     * are not enumerable.
     *
     * `blockConcurrencyWhile` is what makes that safe. Requests queue behind
     * it, so no handler can ever see a half-migrated database, and it is used
     * here and nowhere else — holding it per request would serialize the
     * object down to one operation at a time for no reason.
     */
    ctx.blockConcurrencyWhile(async () => {
      await migrate(this.db, migrations);
    });
  }

  /** Liveness, so the binding and `exports` wiring can be tested. */
  async ping(): Promise<string> {
    return "group";
  }

  // ---------------------------------------------------------------- reading

  async changes(profileId: string, since: number, limit: number): Promise<Result<ChangePage>> {
    return attempt(() => this.db.transaction((tx) => changesSince(tx, profileId, since, limit)));
  }

  // ---------------------------------------------------------------- writing

  async create(input: GroupCreate, profileId: string): Promise<Result<GroupRecord>> {
    const now = nowIso();
    const result = attempt(() =>
      this.db.transaction((tx) => {
        const written = createGroup(tx, input, profileId, { now });
        if (written.changed) {
          stageMembership(tx, input.id, profileId, null, now);
          touchDormancy(tx, Date.parse(now));
        }
        return written.value;
      }),
    );
    await this.settle();
    return result;
  }

  async update(patch: Partial<GroupUpdate>, profileId: string): Promise<Result<GroupRecord>> {
    const result = attempt(() => this.db.transaction((tx) => updateGroup(tx, patch, this.contextFor(tx, profileId)).value));
    await this.settle();
    return result;
  }

  async addMember(input: MemberCreate, profileId: string): Promise<Result<Member>> {
    const result = attempt(() => this.db.transaction((tx) => addMember(tx, input, this.contextFor(tx, profileId)).value));
    await this.settle();
    return result;
  }

  async updateMember(memberId: string, patch: Partial<MemberUpdate>, profileId: string): Promise<Result<Member>> {
    const now = nowIso();
    const result = attempt(() =>
      this.db.transaction((tx) => {
        const written = updateMember(tx, memberId, patch, this.contextFor(tx, profileId, now));

        // Only a change to somebody with an account moves the derived index.
        if (written.changed && written.value.profileId) {
          stageMembership(tx, this.groupId(tx), written.value.profileId, written.value.leftAt, now);
        }
        return written.value;
      }),
    );
    await this.settle();
    if (result.ok) this.announce(profileId);
    return result;
  }

  async upsertEntry(input: EntryInput, profileId: string): Promise<Result<Entry>> {
    const now = nowIso();
    const result = attempt(() =>
      this.db.transaction((tx) => {
        const written = upsertEntry(tx, input, this.contextFor(tx, profileId, now));
        if (written.changed) touchDormancy(tx, Date.parse(now));
        return written.entry;
      }),
    );
    await this.settle();
    if (result.ok) this.announce(profileId);
    return result;
  }

  async deleteEntry(entryId: string, baseSeq: number, profileId: string): Promise<Result<Entry>> {
    const now = nowIso();
    const result = attempt(() => this.db.transaction((tx) => deleteEntry(tx, entryId, baseSeq, this.contextFor(tx, profileId, now)).entry));
    await this.settle();
    if (result.ok) this.announce(profileId);
    return result;
  }

  async restoreEntry(entryId: string, baseSeq: number, profileId: string): Promise<Result<Entry>> {
    const now = nowIso();
    const result = attempt(() => this.db.transaction((tx) => restoreEntry(tx, entryId, baseSeq, this.contextFor(tx, profileId, now)).entry));
    await this.settle();
    if (result.ok) this.announce(profileId);
    return result;
  }

  // ---------------------------------------------------------------- arriving

  async createInvite(memberId: string, profileId: string): Promise<Result<Invite>> {
    const now = nowIso();
    const result = attempt(() =>
      this.db.transaction((tx) => {
        const { invite, superseded } = createInvite(tx, memberId, this.contextFor(tx, profileId, now));
        const groupId = this.groupId(tx);

        // The index has to forget the links this one replaced, or a URL from a
        // chat history still routes somewhere even though it cannot be spent.
        for (const old of superseded) stageLinkToken(tx, groupId, old, "invite", now, true);
        stageLinkToken(tx, groupId, invite.token, "invite", now);
        return invite;
      }),
    );
    await this.settle();
    return result;
  }

  async createLink(profileId: string): Promise<Result<GroupLink>> {
    const now = nowIso();
    const result = attempt(() =>
      this.db.transaction((tx) => {
        const { link, superseded } = createGroupLink(tx, this.contextFor(tx, profileId, now));
        const groupId = this.groupId(tx);
        if (superseded) stageLinkToken(tx, groupId, superseded, "group_link", now, true);
        stageLinkToken(tx, groupId, link.token, "group_link", now);
        return link;
      }),
    );
    await this.settle();
    return result;
  }

  /**
   * Whether there is a link to share, asked by somebody already inside.
   *
   * Requires membership, which is the whole reason it is not simply `peek`
   * with a null token: `peek` answers whoever holds a URL, and this hands a
   * working URL *out*. Anyone who could call it could invite the world in.
   */
  async liveLink(profileId: string): Promise<Result<LiveLink>> {
    return attempt(() =>
      this.db.transaction((tx) => {
        const now = nowIso();
        this.contextFor(tx, profileId, now);
        return { link: liveLink(tx, now) };
      }),
    );
  }

  /**
   * The index deliberately keeps the token.
   *
   * Revoking sets a column; the object still holds the row and can still say
   * what the link was and that it is off. Dropping it from `link_tokens` would
   * strand that answer — the token would stop routing, and somebody tapping a
   * link a friend shared last month would be told it was never valid rather
   * than that the group turned it off. The row is not an authorization; the
   * object refuses the join either way. It is cleared when a new link
   * overwrites this one, which is the point at which the object does forget.
   */
  async revokeLink(profileId: string): Promise<Result<LinkRevocation>> {
    const now = nowIso();
    const result = attempt(() => this.db.transaction((tx) => ({ revoked: revokeGroupLink(tx, this.contextFor(tx, profileId, now)) })));
    await this.settle();
    return result;
  }

  /**
   * Callable with no session, because at this moment the caller is by design
   * nobody yet. `viewer` is null then, and `isMember` is false.
   */
  async peekLink(token: string, viewer: string | null): Promise<Result<LinkPreview | null>> {
    return attempt(() => this.db.transaction((tx) => peek(tx, token, viewer, nowIso())));
  }

  async placeholders(token: string, viewer: string | null): Promise<Result<Placeholder[]>> {
    return attempt(() => this.db.transaction((tx) => placeholders(tx, token, viewer, nowIso())));
  }

  async join(token: string, profileId: string, options: { memberId?: string | null; displayName?: string | null } = {}): Promise<Result<Member>> {
    const now = nowIso();
    const result = attempt(() =>
      this.db.transaction((tx) => {
        const member = join(tx, token, profileId, { now, ...options });
        stageMembership(tx, this.groupId(tx), profileId, null, now);
        return member;
      }),
    );
    await this.settle();
    // The arrival is the actor, even though the event records no one: nobody
    // did this to them, and they do not need telling they just joined.
    if (result.ok) this.announce(profileId);
    return result;
  }

  /**
   * An account is being deleted. This is what that means here.
   *
   * Not a `Result`: there is nothing to refuse. A profile that is not a member
   * is not an error, it is the answer for every group in the index that turned
   * out to be stale.
   */
  async forgetProfile(profileId: string): Promise<{ forgotten: boolean; purged: boolean }> {
    const now = nowIso();
    const outcome = this.db.transaction((tx) => {
      const groupId = this.groupId(tx);
      const result = forgetProfile(tx, profileId, { now });
      if (result.purged) stagePurge(tx, groupId, now);
      return result;
    });
    await this.settle();
    return outcome;
  }

  // -------------------------------------------------------------- housekeeping

  /**
   * Bring this group's housekeeping up to date as of an instant.
   *
   * Takes `now` rather than reading the clock, because that is what makes
   * dormancy testable without waiting three months, and because the weekly
   * reconciliation wants to ask the same question.
   */
  async runUpkeep(now: number = Date.now()): Promise<UpkeepOutcome> {
    const outcome = this.db.transaction((tx) => runDormancy(tx, now));
    await this.settle();
    return outcome;
  }

  /**
   * Tell D1 what this object actually believes.
   *
   * The object is the truth and the index is derived, so reconciling means
   * overwriting the index with the object's answer rather than comparing them
   * and guessing which is right. Restaged through the ordinary outbox so there
   * is one flush path and not two.
   */
  async reconcile(): Promise<number> {
    const now = nowIso();
    const staged = this.db.transaction((tx) => restageAllMemberships(tx, now) + restageLiveTokens(tx, now));
    await this.settle();
    return staged;
  }

  /**
   * The one alarm, doing whatever is owed.
   *
   * Three things want it — a failed D1 flush, the dormancy clock, and the
   * collection that follows it — so the deadlines are rows in `schedule` and
   * this re-arms at the earliest one still outstanding. An alarm that fires
   * early finds nothing due and simply re-arms, because `runDormancy`
   * recomputes from the ledger rather than trusting the schedule.
   */
  override async alarm(): Promise<void> {
    await this.flush();
    this.db.transaction((tx) => runDormancy(tx, Date.now()));
    await this.settle();
  }

  // ------------------------------------------------------------------ private

  /**
   * Who is calling, once the group is established to exist.
   *
   * The order matters and is the whole reason this is a method. Resolving the
   * member first means a group that was collected last year answers "you are
   * not a member of this group", which is true and useless — the caller was a
   * member, of something that is gone. Asking about the group first lets the
   * refusal say which kind of nothing this is.
   */
  private contextFor(tx: Tx, profileId: string, now: string = nowIso()) {
    requireMeta(tx);
    return { now, actor: requireActiveMember(tx, profileId) };
  }

  private groupId(tx: Tx): string {
    const meta = tx.select({ id: schema.meta.id }).from(schema.meta).get();
    return meta?.id ?? this.ctx.id.name ?? "";
  }

  /** Flush what is owed to D1, then arm the alarm for whatever is left. */
  private async settle(): Promise<void> {
    await this.flush();
    await this.armAlarm();
  }

  /**
   * Wake the other members, if this change was worth waking them for.
   *
   * Read from what was appended rather than from what the caller intended —
   * see `notices.ts` — and dispatched through `waitUntil`, so the response goes
   * back as soon as the write has committed. A person recording an expense
   * should not wait on Google to hear that it saved.
   *
   * Nothing here can fail the write. It runs after the transaction, its errors
   * are swallowed inside `wakeDevices`, and push is the one feature this app is
   * entirely usable without.
   */
  private announce(actorProfileId: string | null): void {
    const notices = this.db.transaction((tx) => pendingNotices(tx, this.groupId(tx), actorProfileId));
    if (notices.length === 0) return;

    this.ctx.waitUntil(
      wakeDevices(this.env, notices).catch((error) => {
        console.error("[group] push failed", error);
      }),
    );
  }

  private async armAlarm(): Promise<void> {
    const due = this.db.transaction((tx) => nextDue(tx));
    if (due === null) return;

    const current = await this.ctx.storage.getAlarm();
    if (current === due) return;
    await this.ctx.storage.setAlarm(due);
  }

  /**
   * Push staged index writes to D1.
   *
   * At-least-once, because every statement below is an idempotent upsert or
   * delete: a retry that repeats a write which already landed changes nothing.
   * A failed flush backs off and leaves the rows where they are, so the index
   * converges rather than diverging silently — which is the failure mode an
   * inline write inside the transaction would have had no way to recover from.
   *
   * Capped at a page, because a Worker invocation has a subrequest budget and
   * spending it all here would starve the request that triggered the flush.
   */
  private async flush(): Promise<void> {
    const rows = this.db.transaction((tx) => pendingOutbox(tx, 20));
    if (rows.length === 0) return;

    const ids = rows.map((row) => row.id);
    try {
      const db = drizzleD1(this.env.DB);
      for (const row of rows) await this.apply(db, row);
      this.db.transaction((tx) => clearOutbox(tx, ids));
    } catch (error) {
      console.error("[group] index flush failed", error);
      this.db.transaction((tx) => backoffOutbox(tx, ids, Date.now()));
    }
  }

  /**
   * One staged write, applied.
   *
   * Every statement here is an idempotent upsert, a conflict-free insert or a
   * delete, which is what makes at-least-once delivery enough.
   */
  private async apply(db: ReturnType<typeof drizzleD1>, row: OutboxRow): Promise<void> {
    switch (row.kind) {
      case "membership": {
        const { profileId, groupId, leftAt, updatedAt } = row.payload;
        await db
          .insert(d1.memberships)
          .values({ profileId, groupId, leftAt, updatedAt })
          .onConflictDoUpdate({ target: [d1.memberships.profileId, d1.memberships.groupId], set: { leftAt, updatedAt } });
        return;
      }

      case "link_token": {
        const { token, groupId, tokenKind, revoked } = row.payload;
        if (revoked) {
          // A link that is no longer live must stop resolving here too, or a
          // URL from a chat history still routes to a group it cannot open.
          await db.delete(d1.linkTokens).where(eq(d1.linkTokens.token, token));
          return;
        }
        await db.insert(d1.linkTokens).values({ token, groupId, kind: tokenKind, createdAt: row.createdAt }).onConflictDoNothing();
        return;
      }

      case "group_purged": {
        await db.delete(d1.memberships).where(eq(d1.memberships.groupId, row.payload.groupId));
        await db.delete(d1.linkTokens).where(eq(d1.linkTokens.groupId, row.payload.groupId));
        return;
      }
    }
  }
}
