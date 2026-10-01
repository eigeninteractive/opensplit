import { env } from "cloudflare:workers";
import { expect } from "vitest";
import type { Result } from "../src/do/group/refusal";
import type { Entry, EntryInput, Group, GroupInput, JoinRequest, Member, MemberInput } from "../src/schemas/ledger";

/** A group with people in it. */

/** Stable ids, so a failure names a person rather than a UUID. */
export const RAVI = "11111111-1111-4111-8111-111111111111";
export const PRIYA = "22222222-2222-4222-8222-222222222222";
export const ZARA = "99999999-9999-4999-8999-999999999999";

/** A real account (a `user` row) at a fresh id: D1 refuses memberships for any other kind. */
export async function makeAccount(displayName: string | null = null): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.batch([env.DB.prepare("insert into user (id, name, email, updated_at) values (?, ?, ?, ?)").bind(id, "", `${id}@fixture.invalid`, Date.now()), env.DB.prepare("insert into profiles (id, display_name, updated_at) values (?, ?, ?)").bind(id, displayName, new Date().toISOString())]);
  return id;
}

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
    await object.putGroup(
      groupId,
      {
        name: options.name ?? "Goa trip",
        defaultCurrency: options.currency ?? "INR",
        isDirect: false,
        simplifyDebts: true,
        archivedAt: null,
        creatorId: `${groupId}-ravi`,
        creatorName: "Ravi",
      },
      options.owner ?? RAVI,
    ),
  );

  const priya = ok(await object.putMember(`${groupId}-priya`, { displayName: "Priya", upiVpa: null, leftAt: null }, options.owner ?? RAVI));

  const changes = ok(await object.changes(options.owner ?? RAVI, 0, 500));
  const ravi = changes.members.find((member) => member.profileId === (options.owner ?? RAVI));
  if (!ravi) expect.unreachable("The creator has no member row.");

  return { groupId, group, ravi, priya };
}

/** An expense and the id it is written at, as a device holds it. */
export type EntryDraft = EntryInput & { id: string };

/** An expense, balanced, with sensible defaults. */
export function expense(overrides: Partial<EntryDraft> & Pick<EntryDraft, "id" | "amountMinor" | "payers" | "shares">): EntryDraft {
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
    deletedAt: null,
    baseSeq: null,
    ...overrides,
  };
}

/** One member pays, two split it evenly. The shape most tests need. */
export function evenly(id: string, payer: string, between: string[], amountMinor: number): EntryDraft {
  const each = Math.floor(amountMinor / between.length);
  const shares = between.map((memberId, index) => ({
    memberId,
    amountMinor: index === 0 ? amountMinor - each * (between.length - 1) : each,
    weightMicros: 1_000_000,
  }));

  return expense({ id, amountMinor, payers: [{ memberId: payer, amountMinor }], shares });
}

type GroupStub = ReturnType<typeof stub>;

/** Writes an expense at its own id, the way the app pushes one. */
export function saveEntry(object: GroupStub, { id, ...input }: EntryDraft, profileId: string) {
  return object.putEntry(id, input, profileId);
}

/** A stored expense as the device would send it back, composed against the version it holds. */
export function draftOf(entry: Entry, changes: Partial<EntryDraft> = {}): EntryDraft {
  const { id, kind, description, categoryId, currency, amountMinor, entryDate, occurredAt, timeZone, splitKind, fxRate, fxSource, notes, deletedAt, payers, shares, seq } = entry;
  return { id, kind, description, categoryId, currency, amountMinor, entryDate, occurredAt, timeZone, splitKind, fxRate, fxSource, notes, deletedAt, payers, shares, baseSeq: seq, ...changes };
}

/** Deletes an expense the way the app does: the whole row with `deletedAt` set, against `baseSeq`. */
export function deleteEntry(object: GroupStub, entry: Entry, profileId: string, baseSeq: number = entry.seq) {
  return saveEntry(object, draftOf(entry, { deletedAt: new Date().toISOString(), baseSeq }), profileId);
}

/** Puts a deleted expense back. */
export function restoreEntry(object: GroupStub, entry: Entry, profileId: string) {
  return saveEntry(object, draftOf(entry, { deletedAt: null }), profileId);
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
export async function editGroup(groupId: string, profileId: string, changes: Partial<GroupInput>) {
  const object = stub(groupId);
  const group = ok(await object.changes(profileId, 0, 500)).group;
  if (!group) expect.unreachable("No group row to edit.");
  const { name, defaultCurrency, isDirect, simplifyDebts, archivedAt, createdBy } = group;
  return object.putGroup(groupId, { name, defaultCurrency, isDirect, simplifyDebts, archivedAt, creatorId: createdBy, creatorName: "Ravi", ...changes }, profileId);
}

/** The same for a member row. */
export async function editMember(groupId: string, memberId: string, profileId: string, changes: Partial<MemberInput>) {
  const object = stub(groupId);
  const member = await memberRow(groupId, memberId, profileId);
  const { displayName, upiVpa, leftAt } = member;
  return object.putMember(memberId, { displayName, upiVpa, leftAt, ...changes }, profileId);
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
