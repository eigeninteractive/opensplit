import { env } from "cloudflare:workers";
import { expect } from "vitest";
import type { Result } from "../src/do/group/refusal";
import type { Entry, EntryInput, Group, Member } from "../src/schemas/ledger";

/**
 * A group with people in it.
 *
 * Every row below is written through the same method the app calls, by a
 * caller who has to be allowed to write it — never by reaching past the rules
 * to insert directly. A fixture that needs a privilege the app does not have
 * is a fixture setting up a state the app cannot reach, and the test standing
 * on it proves nothing about the product.
 */

/** Stable ids, so a failure names a person rather than a UUID. */
export const RAVI = "11111111-1111-4111-8111-111111111111";
export const PRIYA = "22222222-2222-4222-8222-222222222222";
export const ZARA = "99999999-9999-4999-8999-999999999999";

export function stub(groupId: string) {
  return env.GROUP.getByName(groupId);
}

/**
 * Unwraps a `Result`, failing the test with the refusal's own words.
 *
 * Worth a helper rather than a `!`: a refused call here should read as "the
 * object said no, and this is what it said", not as a `TypeError` on the next
 * line about reading a property of undefined.
 */
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

/**
 * An expense, balanced, with sensible defaults.
 *
 * Defaults matter here: a test about authorship should not have to spell out a
 * split, and a test about splits should not have to spell out a currency.
 */
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

/**
 * The same group, with Priya's place claimed by a real account.
 *
 * Most of the column rules are only expressible with two account holders in
 * one group — "a member cannot rename another account holder" needs another
 * account holder — and the only way to produce one is the way the app does:
 * mint an invite and spend it.
 */
export async function makeGroupOfTwo(): Promise<Fixture & { priyaProfile: string }> {
  const fixture = await makeGroup();
  const object = stub(fixture.groupId);

  const invite = ok(await object.createInvite(fixture.priya.id, RAVI));
  const priya = ok(await object.join(invite.token, PRIYA));

  return { ...fixture, priya, priyaProfile: PRIYA };
}

export function sumOf(rows: { amountMinor: number }[]): number {
  return rows.reduce((total, row) => total + row.amountMinor, 0);
}

export type { Entry };
