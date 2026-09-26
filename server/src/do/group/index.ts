import { DurableObject } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { type DrizzleD1Database, drizzle as drizzleD1 } from "drizzle-orm/d1";
import { drizzle } from "drizzle-orm/durable-sqlite";
import { migrate } from "drizzle-orm/durable-sqlite/migrator";

import * as d1 from "../../db/d1/schema";
import * as schema from "../../db/group/schema";
import { wakeDevices } from "../../push/fcm";
import type { ChangePage, EntryInput, GroupCreate, GroupUpdate, JoinRequest, MemberCreate, MemberUpdate } from "../../schemas/ledger";
import { changesSince } from "./changes";
import { createGroupLink, createInvite, join, liveLink, peek, placeholders, revokeGroupLink } from "./invites";
import { deleteEntry, restoreEntry, upsertEntry } from "./ledger";
import migrations from "./migrations/migrations";
import { pendingNotices } from "./notices";
import { attempt, type Result } from "./refusal";
import { addMember, createGroup, forgetProfile, updateGroup, updateMember } from "./roster";
import { currentSeq, type GroupDb, nowIso, requireActiveMember, requireMeta, type Tx, type WriteContext } from "./store";
import { backoffOutbox, clearOutbox, nextDue, type OutboxRow, pendingOutbox, restageIndex, runDormancy, type UpkeepOutcome } from "./upkeep";

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

  async changes(profileId: string, since: number, limit: number): Promise<Result<ChangePage>> {
    return this.read((tx) => changesSince(tx, profileId, since, limit));
  }

  async create(input: GroupCreate, profileId: string) {
    return this.write(profileId, (tx, now) => createGroup(tx, input, profileId, now));
  }

  async update(input: GroupUpdate, profileId: string) {
    return this.write(profileId, (tx, now) => updateGroup(tx, input, as(tx, profileId, now)));
  }

  async addMember(input: MemberCreate, profileId: string) {
    return this.write(profileId, (tx, now) => addMember(tx, input, as(tx, profileId, now)));
  }

  async updateMember(memberId: string, input: MemberUpdate, profileId: string) {
    return this.write(profileId, (tx, now) => updateMember(tx, memberId, input, as(tx, profileId, now)));
  }

  async upsertEntry(input: EntryInput, profileId: string) {
    return this.write(profileId, (tx, now) => upsertEntry(tx, input, as(tx, profileId, now)));
  }

  async deleteEntry(entryId: string, baseSeq: number, profileId: string) {
    return this.write(profileId, (tx, now) => deleteEntry(tx, entryId, baseSeq, as(tx, profileId, now)));
  }

  async restoreEntry(entryId: string, baseSeq: number, profileId: string) {
    return this.write(profileId, (tx, now) => restoreEntry(tx, entryId, baseSeq, as(tx, profileId, now)));
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
  async forgetProfile(profileId: string): Promise<{ forgotten: boolean; purged: boolean }> {
    const outcome = this.db.transaction((tx) => forgetProfile(tx, profileId, nowIso()));
    await this.settle();
    return outcome;
  }

  /** Housekeeping as of an instant, so dormancy is testable without waiting months. */
  async runUpkeep(now: number = Date.now()): Promise<UpkeepOutcome> {
    const outcome = this.db.transaction((tx) => runDormancy(tx, now));
    await this.settle();
    return outcome;
  }

  /** Overwrites D1's index with what this object believes, through the ordinary outbox. */
  async reconcile(): Promise<number> {
    const staged = this.db.transaction((tx) => restageIndex(tx, nowIso()));
    await this.settle();
    return staged;
  }

  override async alarm(): Promise<void> {
    this.db.transaction((tx) => runDormancy(tx, Date.now()));
    await this.settle();
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
    const notices = this.db.transaction((tx) => pendingNotices(tx, seq, actorProfileId));
    if (notices.length === 0) return;
    this.ctx.waitUntil(wakeDevices(this.env, notices).catch((error) => console.error("[group] push failed", error)));
  }

  private async settle(): Promise<void> {
    await this.flush();
    const due = this.db.transaction((tx) => nextDue(tx));
    if (due !== null && (await this.ctx.storage.getAlarm()) !== due) await this.ctx.storage.setAlarm(due);
  }

  /** Pushes staged index writes to D1, at least once; a failure backs off and the alarm retries. */
  private async flush(): Promise<void> {
    const rows = this.db.transaction((tx) => pendingOutbox(tx, 20));
    if (rows.length === 0) return;

    const ids = rows.map((row) => row.id);
    try {
      const db = drizzleD1(this.env.DB);
      for (const row of rows) await apply(db, row);
      this.db.transaction((tx) => clearOutbox(tx, ids));
    } catch (error) {
      console.error("[group] index flush failed", error);
      this.db.transaction((tx) => backoffOutbox(tx, ids, Date.now()));
    }
  }
}

/** The caller as a member of an existing group. The group is checked first, so a collected one says so. */
function as(tx: Tx, profileId: string, now: string): WriteContext {
  requireMeta(tx);
  return { now, actor: requireActiveMember(tx, profileId) };
}

/** One staged write; every statement is an idempotent upsert or delete. */
async function apply(db: DrizzleD1Database, row: OutboxRow): Promise<void> {
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
        await db.delete(d1.linkTokens).where(eq(d1.linkTokens.token, token));
        return;
      }
      await db.insert(d1.linkTokens).values({ token, groupId, kind: tokenKind, createdAt: row.createdAt }).onConflictDoNothing();
      return;
    }
    case "group_purged":
      await db.delete(d1.memberships).where(eq(d1.memberships.groupId, row.payload.groupId));
      await db.delete(d1.linkTokens).where(eq(d1.linkTokens.groupId, row.payload.groupId));
      return;
  }
}
