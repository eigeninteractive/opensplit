import { env } from "cloudflare:workers";
import { expect } from "vitest";
import type { Result } from "../src/do/group/refusal";
import type { Entry, EntryInput, Group, GroupUpdate, JoinRequest, Member, MemberUpdate } from "../src/schemas/ledger";

/** A group with people in it. */

/** Stable ids, so a failure names a person rather than a UUID. */
export const RAVI = "11111111-1111-4111-8111-111111111111";
export const PRIYA = "22222222-2222-4222-8222-222222222222";
export const ZARA = "99999999-9999-4999-8999-999999999999";

export function stub(groupId: string) {
  return env.GROUP.getByName(groupId);
}

/** Unwraps a `Result`, failing the test with the refusal's own words. */
export function ok<T>(result: Result<T>): T {
  if (!result.ok) expect.unreachable(`Refused with ${result.error.code}: ${result.error.message}`);
  return result.value;
}

export function refusal<T>(result: Result<T>): { code: string; message: string } {
  if (result.ok) expect.unreachable("Expected a refusal, got a value.");
  return result.error;
}

export interface Fixture {
  groupId: string;
  group: Group;
  /** Ravi: made the group, has an account. */
  ravi: Member;
  /** Priya: a placeholder, added by Ravi, with no account of her own. */
  priya: Member;
}

let counter = 0;

/** A fresh id per call, so suites in one file cannot collide. */
export function freshId(prefix = "g"): string {
  counter += 1;
  return `${prefix}${counter.toString().padStart(4, "0")}-0000-4000-8000-000000000000`;
}

export async function makeGroup(options: { groupId?: string; name?: string; currency?: string; owner?: string } = {}): Promise<Fixture> {
  const groupId = options.groupId ?? freshId();
  const object = stub(groupId);

  const group = ok(
    await object.create(
      {
        id: groupId,
        name: options.name ?? "Goa trip",
        defaultCurrency: options.currency ?? "INR",
        isDirect: false,
        simplifyDebts: true,
        memberId: `${groupId}-ravi`,
        displayName: "Ravi",
      },
      options.owner ?? RAVI,
    ),
  );

  const priya = ok(await object.addMember({ id: `${groupId}-priya`, displayName: "Priya", upiVpa: null }, options.owner ?? RAVI));

  const changes = ok(await object.changes(options.owner ?? RAVI, 0, 500));
  const ravi = changes.members.find((member) => member.profileId === (options.owner ?? RAVI));
  if (!ravi) expect.unreachable("The creator has no member row.");

  return { groupId, group, ravi, priya };
}

/** An expense, balanced, with sensible defaults. */
export function expense(overrides: Partial<EntryInput> & Pick<EntryInput, "id" | "amountMinor" | "payers" | "shares">): EntryInput {
  return {
    kind: "expense",
    description: "Dinner",
    categoryId: null,
    currency: "INR",
    entryDate: "2026-09-23",
    occurredAt: null,
    timeZone: null,
    splitKind: "equal",
    fxRate: null,
    fxSource: null,
    notes: null,
    clientKey: null,
    baseSeq: null,
    ...overrides,
  };
}

/** One member pays, two split it evenly. The shape most tests need. */
export function evenly(id: string, payer: string, between: string[], amountMinor: number): EntryInput {
  const each = Math.floor(amountMinor / between.length);
  const shares = between.map((memberId, index) => ({
    memberId,
    amountMinor: index === 0 ? amountMinor - each * (between.length - 1) : each,
    weightMicros: 1_000_000,
  }));

  return expense({ id, amountMinor, payers: [{ memberId: payer, amountMinor }], shares });
}

/** The same group, with Priya's place claimed by a real account. */
export async function makeGroupOfTwo(): Promise<Fixture & { priyaProfile: string }> {
  const fixture = await makeGroup();
  const object = stub(fixture.groupId);

  const invite = ok(await object.createInvite(fixture.priya.id, RAVI));
  const { member: priya } = ok(await object.join(invite.token, PRIYA, BY_INVITE));

  return { ...fixture, priya, priyaProfile: PRIYA };
}

/** An invite names its own placeholder, so the request chooses nothing. */
export const BY_INVITE: JoinRequest = { memberId: null, displayName: null };

/** Changes some of a group's fields the way the app does: read the row, send all of it. */
export async function editGroup(groupId: string, profileId: string, changes: Partial<GroupUpdate>) {
  const object = stub(groupId);
  const group = ok(await object.changes(profileId, 0, 500)).group;
  if (!group) expect.unreachable("No group row to edit.");
  const { name, simplifyDebts, archivedAt } = group;
  return object.update({ name, simplifyDebts, archivedAt, ...changes }, profileId);
}

/** The same for a member row. */
export async function editMember(groupId: string, memberId: string, profileId: string, changes: Partial<MemberUpdate>) {
  const object = stub(groupId);
  const member = await memberRow(groupId, memberId, profileId);
  const { displayName, upiVpa, leftAt } = member;
  return object.updateMember(memberId, { displayName, upiVpa, leftAt, ...changes }, profileId);
}

/** A member row as the group object currently holds it. Read as `RAVI`, who is in every fixture. */
async function memberRow(groupId: string, memberId: string, profileId: string): Promise<Member> {
  const page = await stub(groupId).changes(profileId, 0, 500);
  const fallback = page.ok ? page : await stub(groupId).changes(RAVI, 0, 500);
  const member = ok(fallback).members.find((row) => row.id === memberId);
  if (!member) expect.unreachable(`No member ${memberId}.`);
  return member;
}

export function sumOf(rows: { amountMinor: number }[]): number {
  return rows.reduce((total, row) => total + row.amountMinor, 0);
}

export type { Entry };
