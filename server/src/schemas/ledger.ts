import { z } from "@hono/zod-openapi";

import { IdSchema, TimestampSchema } from "./common";

/**
 * The ledger, on the wire.
 *
 * These schemas are the contract in all three senses at once: the validator
 * the Worker runs before a Durable Object is ever woken, the TypeScript types
 * the object's own methods are written against, and the OpenAPI definitions
 * the Dart client is generated from. There is no second description of the
 * wire format, so there is nowhere for one to drift from another.
 *
 * The division of labour with the Durable Object is deliberate. Shape lives
 * here — is this a string, is that a positive integer, is this a plausible UPI
 * handle. Meaning lives in the object — are you a member, does this balance,
 * has somebody else changed it since. The first can be answered without
 * touching storage and so should be, on the cheapest thing in the path; the
 * second cannot be answered anywhere else.
 */

/** A calendar date, `YYYY-MM-DD`. An expense happens on a day, not at an instant. */
export const DateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .openapi({ example: "2026-09-23" });

/**
 * A UPI virtual payment address.
 *
 * Checked here rather than by a CHECK constraint, because SQLite has no
 * regular expressions and `GLOB` cannot express this. One regex in the schema
 * that already validates the request beats an approximation in the storage
 * layer that would have to be kept in step with it.
 */
export const UpiVpaSchema = z
  .string()
  .regex(/^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,64}$/)
  .openapi({ example: "ravi@okhdfcbank" });

/** ISO 4217. Validated against the bundled currency list at the edge. */
export const CurrencySchema = z
  .string()
  .regex(/^[A-Z]{3}$/)
  .openapi({ example: "INR" });

/**
 * Registered as named schemas rather than left inline, for two reasons.
 *
 * One shared `EntryKind` across `Entry`, `EntryInput` and `EntrySnapshot`
 * beats three structurally identical `EntryInputKindEnum`-style classes that
 * cannot be assigned to one another.
 *
 * And an inline enum carrying a `default` makes the Dart generator emit
 * `const EntryInputKindEnum._('expense')` as a parameter default, which is a
 * generative enum constructor call and does not compile. A `$ref` gives it a
 * real enum value to point at.
 */
export const EntryKindSchema = z.enum(["expense", "settlement"]).openapi("EntryKind");
export const SplitKindSchema = z.enum(["equal", "exact", "shares", "percent"]).openapi("SplitKind");

export const EventKindSchema = z.enum(["entry", "member_added", "member_joined", "member_left", "member_renamed", "group_renamed", "group_archived", "group_restored", "link_created", "link_revoked"]).openapi("EventKind");

/**
 * The sequence number a change was committed at.
 *
 * One integer per committed change, strictly increasing, handed out by the
 * group's Durable Object because it is the only writer. It is the sync cursor,
 * the version a conflicting edit is judged against, and the total order the
 * activity feed is read in — three jobs that used to need `updated_at`, a
 * `(timestamp, id)` keyset pair, and `clock_timestamp()` respectively.
 */
export const SeqSchema = z.int().nonnegative().openapi({ example: 412 });

/** One member and one amount: what the snapshot's payers and shares reduce to. */
export const MoneyRowSchema = z
  .object({
    memberId: IdSchema,
    amountMinor: z.int(),
  })
  .openapi("MoneyRow");

export const PayerSchema = z
  .object({
    memberId: IdSchema,
    /** Zero is not a payment. Somebody who put nothing down is not a payer. */
    amountMinor: z.int().positive(),
  })
  .openapi("Payer");

export const ShareSchema = z
  .object({
    memberId: IdSchema,
    /**
     * Zero is legitimate — somebody present who owes nothing for this bill —
     * but negative would manufacture a debt out of a balancing pair.
     */
    amountMinor: z.int().nonnegative(),
    /** The original weight scaled by a million. Null for an exact split. */
    weightMicros: z.int().nullable().default(null),
  })
  .openapi("Share");

export const EntrySchema = z
  .object({
    id: IdSchema,
    kind: EntryKindSchema,
    description: z.string(),
    categoryId: IdSchema.nullable(),
    currency: CurrencySchema,
    amountMinor: z.int().positive(),
    entryDate: DateSchema,
    splitKind: SplitKindSchema,
    fxRate: z.number().positive().nullable(),
    fxSource: z.string().nullable(),
    fxAt: TimestampSchema.nullable(),
    notes: z.string().nullable(),
    createdBy: IdSchema,
    clientKey: IdSchema.nullable(),
    createdAt: TimestampSchema,
    updatedAt: TimestampSchema,
    deletedAt: TimestampSchema.nullable(),
    payers: z.array(PayerSchema),
    shares: z.array(ShareSchema),
    seq: SeqSchema,
  })
  .openapi("Entry");

/**
 * What a device sends to record or edit an expense.
 *
 * `createdBy` is absent, and its absence is the rule: authorship is the
 * caller's own member row, resolved by the Durable Object from the session.
 * There is no parameter to point at somebody else, which is what made the
 * corresponding Postgres trigger necessary and is why there is no trigger here.
 *
 * `fxAt` is absent for the same reason — it is when the rate was taken, which
 * only the server can say. `updatedAt` and `seq` are absent because they are
 * the server's bookkeeping about the write, not facts the writer supplies.
 */
export const EntryInputSchema = z
  .object({
    id: IdSchema,
    kind: EntryKindSchema.default("expense"),
    description: z.string().max(500).default(""),
    categoryId: IdSchema.nullable().default(null),
    currency: CurrencySchema,
    amountMinor: z.int().positive(),
    entryDate: DateSchema,
    splitKind: SplitKindSchema.default("equal"),
    fxRate: z.number().positive().nullable().default(null),
    fxSource: z.string().max(64).nullable().default(null),
    notes: z.string().max(2000).nullable().default(null),
    clientKey: IdSchema.nullable().default(null),
    payers: z.array(PayerSchema).min(1),
    shares: z.array(ShareSchema).min(1),

    /**
     * The version this edit was composed against, or null for a row this
     * device invented.
     *
     * A stale base is refused only when applying the write would move money —
     * two people fixing a typo do not have to arbitrate, an edit carrying a
     * stale amount does. See `ledger.ts` for the comparison.
     */
    baseSeq: SeqSchema.nullable().default(null),
  })
  .openapi("EntryInput");

export const MemberSchema = z
  .object({
    id: IdSchema,
    /** Null means a placeholder: a real person with no account, yet. */
    profileId: IdSchema.nullable(),
    displayName: z.string(),
    upiVpa: z.string().nullable(),
    joinedAt: TimestampSchema,
    leftAt: TimestampSchema.nullable(),
    updatedAt: TimestampSchema,
    seq: SeqSchema,
  })
  .openapi("Member");

export const GroupSchema = z
  .object({
    id: IdSchema,
    name: z.string(),
    defaultCurrency: CurrencySchema,
    isDirect: z.boolean(),
    simplifyDebts: z.boolean(),
    createdBy: IdSchema,
    createdAt: TimestampSchema,
    archivedAt: TimestampSchema.nullable(),
    updatedAt: TimestampSchema,
    seq: SeqSchema,
  })
  .openapi("Group");

export const GroupCreateSchema = z
  .object({
    id: IdSchema,
    name: z.string().trim().min(1).max(100),
    defaultCurrency: CurrencySchema,
    isDirect: z.boolean().default(false),
    simplifyDebts: z.boolean().default(true),

    /**
     * The creator's own member row, minted on the device alongside the group.
     *
     * Creating a group is one call that writes both rows in one transaction,
     * which is what removes the bootstrap problem Postgres had: gating member
     * writes on membership is unsatisfiable for the first member, so
     * `groups.created_by` had to double as an authorization — and a column
     * that is an authorization is a column somebody will write themselves into.
     */
    memberId: IdSchema,
    displayName: z.string().trim().min(1).max(100),
  })
  .openapi("GroupCreate");

/**
 * Renaming, archiving, and the two settings.
 *
 * Every field is optional and an absent field means "leave it alone", so this
 * is a patch rather than the whole row. The Postgres version was a full upsert
 * of every column, which is what made `id`, `created_at` and `created_by`
 * rewritable and took a trigger to close. A patch that has no field for them
 * needs no trigger.
 */
export const GroupPatchSchema = z
  .object({
    name: z.string().trim().min(1).max(100).optional(),
    simplifyDebts: z.boolean().optional(),
    /** An instant to archive, or null to restore. */
    archivedAt: TimestampSchema.nullable().optional(),
  })
  .openapi("GroupPatch");

export const MemberCreateSchema = z
  .object({
    id: IdSchema,
    displayName: z.string().trim().min(1).max(100),
    upiVpa: UpiVpaSchema.nullable().default(null),
  })
  .openapi("MemberCreate");

/**
 * What one member may have changed about another, or about themselves.
 *
 * `profileId` is absent: claiming a place is what an invite does, and it is
 * the one transition this column is allowed to make. Exposing it here would
 * be exposing "hand your seat to somebody else", which nothing should.
 */
export const MemberPatchSchema = z
  .object({
    displayName: z.string().trim().min(1).max(100).optional(),
    upiVpa: UpiVpaSchema.nullable().optional(),
    /** An instant to leave or remove, or null to rejoin. */
    leftAt: TimestampSchema.nullable().optional(),
  })
  .openapi("MemberPatch");

export const InviteSchema = z
  .object({
    token: IdSchema,
    memberId: IdSchema,
    createdBy: IdSchema,
    createdAt: TimestampSchema,
    expiresAt: TimestampSchema,
    redeemedAt: TimestampSchema.nullable(),
    redeemedBy: IdSchema.nullable(),

    /**
     * Tokens this one invalidated: one live link per slot, so a link found in
     * a chat history cannot still be spent. Returned rather than merely done,
     * because the derived index in D1 has to forget them too.
     */
    superseded: z.array(z.object({ token: IdSchema })),
  })
  .openapi("Invite");

export const GroupLinkSchema = z
  .object({
    token: IdSchema,
    expiresAt: TimestampSchema,
    /** The link this one replaced, if there was a live one. */
    superseded: IdSchema.nullable(),
  })
  .openapi("GroupLink");

/**
 * What a link is for, answered before anybody has said who they are.
 *
 * One shape for both kinds, with `kind` saying which. The person holding the
 * URL cannot know which kind it is and should not have to: they tapped a link.
 * Postgres answered this with two functions returning two different row types,
 * which meant the client had to guess and then ask again.
 *
 * Flat, with nullable fields, rather than a discriminated union. The Dart
 * generator's `oneOf` support is the weakest part of it, and the difference
 * here is three fields.
 */
export const LinkPreviewSchema = z
  .object({
    kind: z.enum(["invite", "group_link"]),
    groupId: IdSchema,
    groupName: z.string(),
    inviterName: z.string().nullable(),
    memberCount: z.int().nonnegative(),

    /** The name on the slot an invite hands over. Null for an open link. */
    memberName: z.string().nullable(),

    isRedeemed: z.boolean(),
    isExpired: z.boolean(),
    isRevoked: z.boolean(),

    /**
     * Whether whoever is asking is already in this group under some other
     * name. False with no session, which is the common case here. Reported so
     * the screen can say so instead of offering a Join button that is going to
     * be refused.
     */
    isMember: z.boolean(),
  })
  .openapi("LinkPreview");

export const PlaceholderSchema = z
  .object({
    memberId: IdSchema,
    displayName: z.string(),
  })
  .openapi("Placeholder");

/**
 * What an expense looked like after a change.
 *
 * The one payload that is an after-image rather than a description, because an
 * expense line has to read "Ravi's share, from ₹200 to ₹300" and a chain of
 * snapshots yields that field-level diff for free. See `events.ts`.
 *
 * `fxRate` and friends are absent on purpose — they move whenever the currency
 * does and would make every currency edit read as two changes. `updatedAt` and
 * `seq` are absent because they move on every write by definition, which would
 * make a save that altered nothing read as an edit.
 */
export const EntrySnapshotSchema = z
  .object({
    kind: EntryKindSchema,
    description: z.string(),
    currency: CurrencySchema,
    amountMinor: z.int().positive(),
    entryDate: DateSchema,
    splitKind: SplitKindSchema,
    categoryId: IdSchema.nullable(),
    notes: z.string().nullable(),
    deletedAt: TimestampSchema.nullable(),
    payers: z.array(MoneyRowSchema),
    shares: z.array(MoneyRowSchema),
  })
  .openapi("EntrySnapshot");

/** Somebody added, arriving, leaving or renamed. `previousName` is set by a rename alone. */
export const MemberEventPayloadSchema = z
  .object({
    displayName: z.string(),
    previousName: z.string().nullable(),
  })
  .openapi("MemberEventPayload");

export const GroupEventPayloadSchema = z
  .object({
    name: z.string(),
    previousName: z.string().nullable(),
  })
  .openapi("GroupEventPayload");

export const LinkEventPayloadSchema = z
  .object({
    expiresAt: TimestampSchema,
  })
  .openapi("LinkEventPayload");

/**
 * Every shape the record can hold, enumerated — in TypeScript.
 *
 * There are four, they are closed, and which one an event carries is decided
 * entirely by its `kind`, so a free-form map was never the honest *type* for
 * this. `append()` in `events.ts` takes a discriminated parameter, which is
 * where the pairing is enforced: a `member_renamed` carrying a group's payload
 * does not compile.
 *
 * ## Why the contract says `object` and not `oneOf`
 *
 * It was `z.union([...])`, which emits `oneOf` — and `oneOf` is where the Dart
 * generator gives up. It does not produce a sealed class or even a `dynamic`.
 * It flattens all four branches into **one class carrying every field from
 * every branch, all required**, so `EventPayload.fromJson` asserts that a
 * "Priya joined" payload has an `amountMinor`, an `entryDate` and an
 * `expiresAt`, and throws when it does not. That is not a weaker client, it is
 * a client that cannot read the feed at all.
 *
 * So `z.custom` keeps the precise TypeScript type and tells the document what
 * this genuinely is: an object whose shape depends on a sibling field, which
 * OpenAPI 3.0.3 cannot express in a form this generator handles. The four
 * shapes are still registered as named schemas above, so the contract
 * documents them even though `payload` does not point at them.
 *
 * Nothing is lost at runtime. `Event` is a response type and responses are not
 * validated — the payload is written by this server from what it committed and
 * never arrives from a client. And the Dart side already reads it as
 * `Map<String, Object?>` and parses per kind, which is what this produces.
 */
export const EventPayloadSchema = z.custom<EntrySnapshot | MemberEventPayload | GroupEventPayload | LinkEventPayload>().openapi({
  type: "object",

  /**
   * `{nullable: true}` rather than `true`, and it is load-bearing. Plain
   * `additionalProperties: true` generates `Map<String, Object>` in Dart, and
   * `.cast<String, Object>()` is lazy — it throws on the first read of a key
   * whose value is null. Every payload here has one: `previousName`,
   * `categoryId`, `deletedAt`. The feed would break on the first rename.
   */
  additionalProperties: { nullable: true },
  description: "The after-image, in whatever shape `kind` calls for: EntrySnapshot, MemberEventPayload, GroupEventPayload or LinkEventPayload.",
});

/**
 * Reading a payload back, at the one place the type system cannot help.
 *
 * `kind` and `payload` are separate columns, so nothing proves to the compiler
 * that an `entry` row carries a snapshot — only `append()` does, at the write.
 * These guards are that fact stated once, in the open, instead of a cast at
 * every call site. A reader that forgets to narrow does not compile.
 */
export function isEntryEvent(event: Event): event is Event & { payload: EntrySnapshot } {
  return event.kind === "entry";
}

export function isMemberEvent(event: Event): event is Event & { payload: MemberEventPayload } {
  return event.kind === "member_added" || event.kind === "member_joined" || event.kind === "member_left" || event.kind === "member_renamed";
}

export function isGroupEvent(event: Event): event is Event & { payload: GroupEventPayload } {
  return event.kind === "group_renamed" || event.kind === "group_archived" || event.kind === "group_restored";
}

export function isLinkEvent(event: Event): event is Event & { payload: LinkEventPayload } {
  return event.kind === "link_created" || event.kind === "link_revoked";
}

export const EventSchema = z
  .object({
    id: IdSchema,
    actorId: IdSchema.nullable(),
    createdAt: TimestampSchema,
    kind: EventKindSchema,
    subjectId: IdSchema.nullable(),
    payload: EventPayloadSchema,
    seq: SeqSchema,
  })
  .openapi("Event");

/**
 * One group's changes since a cursor. One request, one integer, one page.
 *
 * `limit` counts **changes, not rows**. A save that writes an entry, four
 * shares and an event is one change and shares one `seq`, and a page is never
 * cut inside one — so a device either sees a whole write or none of it. Paging
 * by rows would let a client observe an entry whose shares had not arrived,
 * which is a balance that does not add up on somebody's screen.
 */
export const ChangePageSchema = z
  .object({
    /** The cursor to send next time. Unchanged from `since` when nothing moved. */
    seq: SeqSchema,
    hasMore: z.boolean(),

    /** Null when the group itself has not changed since the cursor. */
    group: GroupSchema.nullable(),
    members: z.array(MemberSchema),
    entries: z.array(EntrySchema),
    events: z.array(EventSchema),

    /**
     * Set once, on the page that carries the end of the group.
     *
     * A group archived, a year silent and settled is collected, and everything
     * about it is deleted. A device reading this drops its local copy — which
     * it can only do if somebody tells it, and the sequence feed is what makes
     * telling it possible at all.
     */
    purgedAt: TimestampSchema.nullable(),
  })
  .openapi("ChangePage");

export type Payer = z.infer<typeof PayerSchema>;
export type Share = z.infer<typeof ShareSchema>;
export type Entry = z.infer<typeof EntrySchema>;
export type EntryInput = z.infer<typeof EntryInputSchema>;
export type Member = z.infer<typeof MemberSchema>;
export type Group = z.infer<typeof GroupSchema>;
export type GroupCreate = z.infer<typeof GroupCreateSchema>;
export type GroupPatch = z.infer<typeof GroupPatchSchema>;
export type MemberCreate = z.infer<typeof MemberCreateSchema>;
export type MemberPatch = z.infer<typeof MemberPatchSchema>;
export type Invite = z.infer<typeof InviteSchema>;
export type GroupLink = z.infer<typeof GroupLinkSchema>;
export type LinkPreview = z.infer<typeof LinkPreviewSchema>;
export type Placeholder = z.infer<typeof PlaceholderSchema>;
export type Event = z.infer<typeof EventSchema>;
export type EntrySnapshot = z.infer<typeof EntrySnapshotSchema>;
export type MemberEventPayload = z.infer<typeof MemberEventPayloadSchema>;
export type GroupEventPayload = z.infer<typeof GroupEventPayloadSchema>;
export type LinkEventPayload = z.infer<typeof LinkEventPayloadSchema>;
export type EventPayload = z.infer<typeof EventPayloadSchema>;
export type EventKind = z.infer<typeof EventKindSchema>;
export type ChangePage = z.infer<typeof ChangePageSchema>;
