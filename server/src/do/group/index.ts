import { DurableObject } from "cloudflare:workers";
import { eq, sql } from "drizzle-orm";
import { type DrizzleD1Database, drizzle as drizzleD1 } from "drizzle-orm/d1";
import { drizzle } from "drizzle-orm/durable-sqlite";
import { migrate } from "drizzle-orm/durable-sqlite/migrator";

import { user } from "../../auth-schema";
import * as d1 from "../../db/d1/schema";
import * as schema from "../../db/group/schema";
import { wakeDevices } from "../../push/fcm";
import type { EntryInput, GroupChanges, GroupInput, JoinRequest, MemberInput } from "../../schemas/ledger";
import { changesSince } from "./changes";
import { createGroupLink, createInvite, join, liveLink, peek, placeholders, revokeGroupLink } from "./invites";
import { putEntry } from "./ledger";
import migrations from "./migrations/migrations";
import { pendingNotices } from "./notices";
import { attempt, type Result } from "./refusal";
import { createGroup, forgetProfile, handOver, putMember, updateGroup } from "./roster";
import { currentSeq, findMeta, findTombstone, type GroupDb, nowIso, requireActiveMember, requireMeta, type Tx, type WriteContext } from "./store";
import { backoffOutbox, clearOutbox, nextDue, type OutboxRow, pendingOutbox, runDormancy, type UpkeepOutcome } from "./upkeep";

/**
 * One group's ledger and its authorization boundary. The object runs one
 * request at a time, so membership, column rules and the balance invariant are
 * plain code, and it can hand out a strictly increasing sequence number.
 *
 * Methods take the caller's profile id from the session and resolve their own
 * member row; nobody names who they are. Refusals are `Result` values.
 */
export class Group extends DurableObject<Env> {
  private readonly db: GroupDb;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.db = drizzle(ctx.storage, { schema, logger: false });
    // Each object migrates itself lazily, on its first open after a deploy.
    ctx.blockConcurrencyWhile(() => migrate(this.db, migrations));
  }

  async ping(): Promise<string> {
    return "group";
  }

  async changes(profileId: string, since: number, limit: number): Promise<Result<GroupChanges>> {
    return this.read((tx) => changesSince(tx, profileId, since, limit));
  }

  /** Creates the group at this object's id, or edits it. Creating needs no membership; editing does. */
  async putGroup(groupId: string, input: GroupInput, profileId: string) {
    return this.write(profileId, (tx, now) => (findMeta(tx) === undefined && findTombstone(tx) === undefined ? createGroup(tx, groupId, input, profileId, now) : updateGroup(tx, input, as(tx, profileId, now))));
  }

  async putMember(memberId: string, input: MemberInput, profileId: string) {
    return this.write(profileId, (tx, now) => putMember(tx, memberId, input, as(tx, profileId, now)));
  }

  async putEntry(entryId: string, input: EntryInput, profileId: string) {
    return this.write(profileId, (tx, now) => putEntry(tx, entryId, input, as(tx, profileId, now)));
  }

  async createInvite(memberId: string, profileId: string) {
    return this.write(profileId, (tx, now) => createInvite(tx, memberId, as(tx, profileId, now)));
  }

  async createLink(profileId: string) {
    return this.write(profileId, (tx, now) => createGroupLink(tx, as(tx, profileId, now)));
  }

  async revokeLink(profileId: string) {
    return this.write(profileId, (tx, now) => ({ revoked: revokeGroupLink(tx, as(tx, profileId, now)) }));
  }

  /** The link to share. Membership required: this hands a working URL out. */
  async liveLink(profileId: string) {
    return this.read((tx, now) => {
      as(tx, profileId, now);
      return { link: liveLink(tx, now) };
    });
  }

  /** Callable with no session: whoever tapped the link is nobody yet. */
  async peekLink(token: string, viewer: string | null) {
    return this.read((tx, now) => peek(tx, token, viewer, now));
  }

  /** Other people's names: the route requires a session. */
  async placeholders(token: string) {
    return this.read((tx, now) => ({ placeholders: placeholders(tx, token, now) }));
  }

  async join(token: string, profileId: string, request: JoinRequest) {
    return this.write(profileId, (tx, now) => {
      const member = join(tx, token, profileId, request, now);
      return { groupId: requireMeta(tx).id, member };
    });
  }

  /** An account is being deleted. Not a `Result`: a profile that is not here is an answer. */
  async forgetProfile(profileId: string, displayName: string | null): Promise<{ forgotten: boolean; purged: boolean }> {
    const outcome = this.db.transaction((tx) => forgetProfile(tx, profileId, displayName, nowIso()));
    await this.settle();
    return outcome;
  }

  /** A guest became an account they already had. Not a `Result`, for the same reason as `forgetProfile`. */
  async handOver(profileId: string, heirId: string): Promise<{ forgotten: boolean; purged: boolean }> {
    const outcome = this.db.transaction((tx) => handOver(tx, profileId, heirId, nowIso()));
    await this.settle();
    return outcome;
  }

  /** Housekeeping as of an instant, so dormancy is testable without waiting months. */
  async runUpkeep(now: number = Date.now()): Promise<UpkeepOutcome> {
    const outcome = this.db.transaction((tx) => runDormancy(tx, now));
    await this.settle();
    return outcome;
  }

  override async alarm(): Promise<void> {
    this.db.transaction((tx) => runDormancy(tx, Date.now()));
    // Re-armed unconditionally: the alarm that is firing is spent once this returns.
    await this.settle({ rearm: true });
  }

  private async read<T>(body: (tx: Tx, now: string) => T): Promise<Result<T>> {
    const now = nowIso();
    return attempt(() => this.db.transaction((tx) => body(tx, now)));
  }

  /**
   * One change: run it, flush what it owes D1, and wake the other members if it
   * committed something. A write that changed nothing spends no sequence
   * number and so notifies nobody, which is what keeps retries quiet.
   */
  private async write<T>(profileId: string, body: (tx: Tx, now: string) => T): Promise<Result<T>> {
    const now = nowIso();
    const result = attempt(() =>
      this.db.transaction((tx) => {
        const before = currentSeq(tx);
        const value = body(tx, now);
        const after = currentSeq(tx);
        return { value, spent: after > before ? after : null };
      }),
    );
    await this.settle();
    if (!result.ok) return result;

    const { value, spent } = result.value;
    if (spent !== null) this.announce(spent, profileId);
    return { ok: true, value };
  }

  /** Push runs after the commit, inside `waitUntil`, and can never fail the write. */
  private announce(seq: number, actorProfileId: string): void {
    const { groupId, messages } = this.db.transaction((tx) => ({ groupId: requireMeta(tx).id, messages: pendingNotices(tx, seq) }));
    if (messages.length === 0) return;
    this.ctx.waitUntil(wakeDevices(this.env, groupId, actorProfileId, messages).catch((error) => console.error("[group] push failed", error)));
  }

  private async settle({ rearm = false } = {}): Promise<void> {
    await this.flush();
    const due = this.db.transaction((tx) => nextDue(tx));
    if (due !== null && (rearm || (await this.ctx.storage.getAlarm()) !== due)) await this.ctx.storage.setAlarm(due);
  }

  /** The flush in progress, if any. Flushes run one after another, never side by side. */
  private flushing: Promise<void> = Promise.resolve();

  /**
   * Sends every staged index write to D1, oldest first, and resolves once the
   * outbox is empty or D1 has refused one (the alarm retries it). Queued behind
   * any flush already running, so two requests can never interleave their
   * writes, and a caller's own rows are always sent before its promise settles.
   */
  private flush(): Promise<void> {
    this.flushing = this.flushing
      .then(() => this.drain())
      .catch((error) => {
        // A bug, not D1 refusing: keep the chain usable and leave the rows for the alarm.
        console.error("[group] index flush crashed", error);
        this.db.transaction((tx) =>
          backoffOutbox(
            tx,
            pendingOutbox(tx, 1).map((row) => row.id),
            Date.now(),
          ),
        );
      });
    return this.flushing;
  }

  private async drain(): Promise<void> {
    const db = drizzleD1(this.env.DB);
    for (;;) {
      const rows = this.db.transaction((tx) => pendingOutbox(tx, 20));
      if (rows.length === 0) return;

      for (const row of rows) {
        let outcome: Applied;
        try {
          outcome = await apply(db, row);
        } catch (error) {
          console.error("[group] index flush failed", error);
          this.db.transaction((tx) => backoffOutbox(tx, [row.id], Date.now()));
          return;
        }
        this.db.transaction((tx) => {
          clearOutbox(tx, [row.id]);
          // The account was deleted before this reached D1: finish what deleting it would have done here.
          if (outcome === "account_gone" && row.kind === "membership") forgetProfile(tx, row.payload.profileId, null, nowIso());
        });
      }
    }
  }
}

/** The caller as a member of an existing group. The group is checked first, so a collected one says so. */
function as(tx: Tx, profileId: string, now: string): WriteContext {
  requireMeta(tx);
  return { now, actor: requireActiveMember(tx, profileId) };
}

/** Whether D1 took a membership, or the account behind it no longer exists. */
type Applied = "applied" | "account_gone";

/**
 * One staged write. Each is safe to repeat and safe to arrive late: a
 * membership only replaces an older version of itself, and nothing is written
 * for a group D1 has been told is purged.
 */
async function apply(db: DrizzleD1Database, row: OutboxRow): Promise<Applied> {
  const notPurged = (groupId: string) => sql`not exists (select 1 from ${d1.purgedGroups} where ${d1.purgedGroups.groupId} = ${groupId})`;

  switch (row.kind) {
    case "membership": {
      const { profileId, groupId, leftAt, updatedAt } = row.payload;
      const accountExists = sql`exists (select 1 from ${user} where ${user.id} = ${profileId})`;
      await db.run(sql`
        insert into ${d1.memberships} (profile_id, group_id, left_at, updated_at, version)
        select ${profileId}, ${groupId}, ${leftAt}, ${updatedAt}, ${row.id}
         where ${accountExists} and ${notPurged(groupId)}
        on conflict (profile_id, group_id) do update
           set left_at = excluded.left_at, updated_at = excluded.updated_at, version = excluded.version
         where excluded.version > ${d1.memberships}.version`);

      // Read after the write, so an account deleted either side of it is caught: before, and this
      // sees it gone; after, and the deletion finds the row this wrote.
      const account = await db.select({ id: user.id }).from(user).where(eq(user.id, profileId)).get();
      return account ? "applied" : "account_gone";
    }
    case "link_token": {
      const { token, groupId, tokenKind } = row.payload;
      await db.run(sql`
        insert into ${d1.linkTokens} (token, group_id, kind, created_at)
        select ${token}, ${groupId}, ${tokenKind}, ${row.createdAt}
         where ${notPurged(groupId)}
        on conflict (token) do nothing`);
      return "applied";
    }
    case "group_purged": {
      const { groupId } = row.payload;
      await db.batch([db.insert(d1.purgedGroups).values({ groupId, purgedAt: row.createdAt }).onConflictDoNothing(), db.delete(d1.memberships).where(eq(d1.memberships.groupId, groupId)), db.delete(d1.linkTokens).where(eq(d1.linkTokens.groupId, groupId))]);
      return "applied";
    }
  }
}
