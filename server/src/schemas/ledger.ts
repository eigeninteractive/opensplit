import { z } from "@hono/zod-openapi";

import * as tables from "../db/group/schema";
import { entryKinds, eventKinds, splitKinds } from "../db/group/schema";
import { createSelectSchema, IdSchema, TimestampSchema } from "./common";

/**
 * The ledger, on the wire.
 *
 * Shape lives here; meaning (membership, balance, staleness) lives in the
 * group's Durable Object, which is the only place that can answer it.
 *
 * A row the server returns is derived from its table, so a column exists in
 * one place. The overrides give a column its wire type where SQLite has none
 * (a timestamp, a date, a named enum). Request bodies are written out, because
 * they are deliberately narrower than the rows they write and carry the
 * validation.
 *
 * Every body field is required, and null is the only way to say "none". The
 * generated Dart client drops a null optional field, so an optional field
 * would be three states on the server and two on the device.
 */

/** A calendar date, `YYYY-MM-DD`. An expense happens on a day, not at an instant. */
export const DateSchema = z.iso.date().openapi({ example: "2026-09-23" });

/** A UPI virtual payment address. SQLite has no regular expressions, so this is the only check. */
export const UpiVpaSchema = z
  .string()
  .regex(/^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,64}$/)
  .openapi({ example: "ravi@okhdfcbank" });

/** ISO 4217. */
export const CurrencyCodeSchema = z
  .string()
  .regex(/^[A-Z]{3}$/)
  .openapi({ example: "INR" });

/**
 * Named, so `Entry`, `EntryInput` and `EntrySnapshot` share one Dart enum
 * rather than three structurally identical ones.
 */
export const EntryKindSchema = z.enum(entryKinds).openapi("EntryKind");
export const SplitKindSchema = z.enum(splitKinds).openapi("SplitKind");
export const EventKindSchema = z.enum(eventKinds).openapi("EventKind");

/**
 * The sequence number a change was committed at: one per change, strictly
 * increasing, handed out by the group's Durable Object. It is the sync
 * cursor, the version an edit is judged against, and the feed's order.
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
    /** Zero is not a payment. */
    amountMinor: z.int().positive(),
  })
  .openapi("Payer");

export const ShareSchema = z
  .object({
    memberId: IdSchema,
    /** Zero is somebody present who owes nothing; negative would invent a debt. */
    amountMinor: z.int().nonnegative(),
    /** The original weight scaled by a million. Null for an exact split. */
    weightMicros: z.int().nullable(),
  })
  .openapi("Share");

export const EntrySchema = createSelectSchema(tables.entries, {
  kind: EntryKindSchema,
  amountMinor: z.int().positive(),
  fxRate: z.number().positive().nullable(),
  entryDate: DateSchema,
  splitKind: SplitKindSchema,
  fxAt: TimestampSchema.nullable(),
  createdAt: TimestampSchema,
  updatedAt: TimestampSchema,
  deletedAt: TimestampSchema.nullable(),
  seq: SeqSchema,
})
  .extend({ payers: z.array(PayerSchema), shares: z.array(ShareSchema) })
  .openapi("Entry");

/**
 * What a device sends to record or edit an expense.
 *
 * No `createdBy`: authorship is the caller's own member row, resolved from the
 * session, so there is nothing to spoof. No `fxAt`, `updatedAt` or `seq`:
 * those are the server's bookkeeping about the write.
 */
export const EntryInputSchema = z
  .object({
    id: IdSchema,
    kind: EntryKindSchema,
    description: z.string().max(500),
    categoryId: IdSchema.nullable(),
    currency: CurrencyCodeSchema,
    amountMinor: z.int().positive(),
    entryDate: DateSchema,
    splitKind: SplitKindSchema,
    fxRate: z.number().positive().nullable(),
    fxSource: z.string().max(64).nullable(),
    notes: z.string().max(2000).nullable(),
    clientKey: IdSchema.nullable(),
    payers: z.array(PayerSchema).min(1),
    shares: z.array(ShareSchema).min(1),

    /**
     * The version this edit was composed against, or null for a new row. A
     * stale base is refused only when the write would move money.
     */
    baseSeq: SeqSchema.nullable(),
  })
  .openapi("EntryInput");

/** A null `profileId` is a placeholder: a real person with no account yet. */
export const MemberSchema = createSelectSchema(tables.members, {
  joinedAt: TimestampSchema,
  leftAt: TimestampSchema.nullable(),
  updatedAt: TimestampSchema,
  seq: SeqSchema,
}).openapi("Member");

export const GroupSchema = createSelectSchema(tables.meta, {
  createdAt: TimestampSchema,
  archivedAt: TimestampSchema.nullable(),
  updatedAt: TimestampSchema,
  seq: SeqSchema,
}).openapi("Group");

const NameSchema = z.string().trim().min(1).max(100);

export const GroupCreateSchema = z
  .object({
    id: IdSchema,
    name: NameSchema,
    defaultCurrency: CurrencyCodeSchema,
    isDirect: z.boolean(),
    simplifyDebts: z.boolean(),

    /**
     * The creator's own member row, written in the same transaction. Gating
     * member writes on membership is otherwise unsatisfiable for the first
     * member.
     */
    memberId: IdSchema,
    displayName: NameSchema,
  })
  .openapi("GroupCreate");

/**
 * A group's editable fields, all of them. There are no fields for `id`,
 * `createdAt` or `createdBy`, so nothing needs to forbid rewriting them.
 */
export const GroupUpdateSchema = z
  .object({
    name: NameSchema,
    simplifyDebts: z.boolean(),
    /** An instant to archive, or null to restore. */
    archivedAt: TimestampSchema.nullable(),
  })
  .openapi("GroupUpdate");

export const MemberCreateSchema = z
  .object({
    id: IdSchema,
    displayName: NameSchema,
    upiVpa: UpiVpaSchema.nullable(),
  })
  .openapi("MemberCreate");

/**
 * A member's editable fields, all of them. No `profileId`: claiming a place
 * is what an invite does, and nothing else may hand a seat to somebody.
 */
export const MemberUpdateSchema = z
  .object({
    displayName: NameSchema,
    upiVpa: UpiVpaSchema.nullable(),
    /** An instant to leave or remove, or null to rejoin. */
    leftAt: TimestampSchema.nullable(),
  })
  .openapi("MemberUpdate");

export const InviteSchema = createSelectSchema(tables.invites, {
  createdAt: TimestampSchema,
  expiresAt: TimestampSchema,
  redeemedAt: TimestampSchema.nullable(),
}).openapi("Invite");

/** A group's open link, as it stands. */
export const GroupLinkSchema = z
  .object({
    token: IdSchema,
    expiresAt: TimestampSchema,
  })
  .openapi("GroupLink");

/**
 * The group's live link, or the fact that there is not one.
 *
 * Wrapped rather than a nullable `GroupLink` at the top level, because a
 * nullable `$ref` in OpenAPI 3.0.3 becomes an `allOf` the Dart generator
 * flattens into a non-nullable class — so "no link yet", which is the state
 * every group starts in, would arrive as a decode failure.
 */
export const LiveLinkSchema = z
  .object({
    link: GroupLinkSchema.nullable(),
  })
  .openapi("LiveLink");

/** What revoking did. Null when there was nothing live to revoke. */
export const LinkRevocationSchema = z
  .object({
    revoked: IdSchema.nullable(),
  })
  .openapi("LinkRevocation");

/**
 * What a link is for, answered before anybody has said who they are.
 *
 * One shape for both kinds, with `kind` saying which. The person holding the
 * URL cannot know which kind it is and should not have to: they tapped a link.
 * Two endpoints returning two row types would mean the client guessing first
 * and asking again when it guessed wrong.
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
 * The unclaimed places a link's group is holding.
 *
 * An object around the array rather than the array itself, matching every
 * other response here. A bare array is a shape nothing can ever be added to
 * without breaking every client that reads it.
 */
export const PlaceholderListSchema = z
  .object({
    placeholders: z.array(PlaceholderSchema),
  })
  .openapi("PlaceholderList");

/**
 * Where you ended up.
 *
 * The one response that names its group, and it has to: the caller held a
 * token, which is deliberately opaque about what it points at, and the next
 * thing they do is open the group and sync it. Everywhere else the group id is
 * a property of the page rather than of a row — see `ChangePage` — because
 * every other caller already had it.
 */
export const JoinedSchema = z
  .object({
    groupId: IdSchema,
    member: MemberSchema,
  })
  .openapi("Joined");

/**
 * Walking in on a link.
 *
 * `memberId` names one of the unclaimed places to take over; `displayName` is
 * for an arrival who is not one of them. Exactly one is used, decided by the
 * link's kind and by what the person picked, and the Durable Object is what
 * decides which — see `invites.ts`.
 */
export const JoinRequestSchema = z
  .object({
    /** One of the places from `PlaceholderList`, or null to arrive as new. */
    memberId: IdSchema.nullable(),

    /** The name to arrive under. Ignored when `memberId` is set. */
    displayName: NameSchema.nullable(),
  })
  .openapi("JoinRequest");

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
    currency: CurrencyCodeSchema,
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
 * The after-image, whose shape is decided by the sibling `kind`.
 *
 * `z.custom` rather than `z.union`, because the union emits `oneOf`, which the
 * Dart generator flattens into one class with every branch's fields required.
 * The four shapes are registered as components in `app.ts`, so the generated
 * client has a class for each and decodes `payload` per `kind`. The check
 * function is what makes the field required: a bare `z.custom` accepts
 * `undefined`, so it would be emitted as optional.
 *
 * `additionalProperties: {nullable: true}` rather than `true`: the latter
 * generates `Map<String, Object>`, whose lazy cast throws on the first null
 * value, and every payload has one.
 */
export const EventPayloadSchema = z
  .custom<EntrySnapshot | MemberEventPayload | GroupEventPayload | LinkEventPayload>((value) => typeof value === "object" && value !== null)
  .openapi({
    type: "object",
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

/** Read the feed ordered by `(seq, ordinal)`: one change can append several lines at one `seq`. */
export const EventSchema = createSelectSchema(tables.events, {
  createdAt: TimestampSchema,
  kind: EventKindSchema,
  payload: EventPayloadSchema,
  seq: SeqSchema,
  ordinal: z.int().nonnegative(),
}).openapi("Event");

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
    /**
     * Which group this page describes. Stated once per page rather than on
     * each row: the Durable Object *is* the group, so its rows have no such
     * column.
     */
    groupId: IdSchema,

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
export type GroupUpdate = z.infer<typeof GroupUpdateSchema>;
export type MemberCreate = z.infer<typeof MemberCreateSchema>;
export type MemberUpdate = z.infer<typeof MemberUpdateSchema>;
export type Invite = z.infer<typeof InviteSchema>;
export type GroupLink = z.infer<typeof GroupLinkSchema>;
export type LiveLink = z.infer<typeof LiveLinkSchema>;
export type LinkRevocation = z.infer<typeof LinkRevocationSchema>;
export type LinkPreview = z.infer<typeof LinkPreviewSchema>;
export type Placeholder = z.infer<typeof PlaceholderSchema>;
export type PlaceholderList = z.infer<typeof PlaceholderListSchema>;
export type JoinRequest = z.infer<typeof JoinRequestSchema>;
export type Joined = z.infer<typeof JoinedSchema>;
export type Event = z.infer<typeof EventSchema>;
export type EntrySnapshot = z.infer<typeof EntrySnapshotSchema>;
export type MemberEventPayload = z.infer<typeof MemberEventPayloadSchema>;
export type GroupEventPayload = z.infer<typeof GroupEventPayloadSchema>;
export type LinkEventPayload = z.infer<typeof LinkEventPayloadSchema>;
export type EventPayload = z.infer<typeof EventPayloadSchema>;
export type EventKind = z.infer<typeof EventKindSchema>;
export type ChangePage = z.infer<typeof ChangePageSchema>;
