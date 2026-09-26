import { z } from "@hono/zod-openapi";

import { linkKinds } from "../db/d1/schema";
import * as tables from "../db/group/schema";
import { CurrencyCodeSchema, createSelectSchema, DateSchema, IdSchema, NameSchema, SeqSchema, TimestampSchema, TimeZoneSchema, UpiVpaSchema } from "./common";

/**
 * The ledger on the wire. Rows are the group object's tables; request bodies
 * pick the columns a client may write. Every body field is required and null
 * means "none".
 */

export const EntryKindSchema = z.enum(tables.entryKinds).openapi("EntryKind");
export const SplitKindSchema = z.enum(tables.splitKinds).openapi("SplitKind");
export const EventKindSchema = z.enum(tables.eventKinds).openapi("EventKind");
export const LinkKindSchema = z.enum(linkKinds).openapi("LinkKind");

const payerRow = createSelectSchema(tables.entryPayers, { memberId: () => IdSchema, amountMinor: () => z.int().positive() });
const shareRow = createSelectSchema(tables.entryShares, { memberId: () => IdSchema, amountMinor: () => z.int().nonnegative(), weightMicros: () => z.int() });

export const PayerSchema = payerRow.pick({ memberId: true, amountMinor: true }).openapi("Payer");
export const ShareSchema = shareRow.pick({ memberId: true, amountMinor: true, weightMicros: true }).openapi("Share");
/** A member and an amount: what a snapshot's payers and shares reduce to. */
export const MoneyRowSchema = shareRow.pick({ memberId: true, amountMinor: true }).openapi("MoneyRow");

const entryRow = createSelectSchema(tables.entries, {
  id: () => IdSchema,
  kind: () => EntryKindSchema,
  description: () => z.string().max(500),
  categoryId: () => IdSchema,
  currency: () => CurrencyCodeSchema,
  amountMinor: () => z.int().positive(),
  entryDate: () => DateSchema,
  occurredAt: () => TimestampSchema,
  timeZone: () => TimeZoneSchema,
  splitKind: () => SplitKindSchema,
  fxRate: () => z.number().positive(),
  fxSource: () => z.string().max(64),
  fxAt: () => TimestampSchema,
  notes: () => z.string().max(2000),
  createdBy: () => IdSchema,
  clientKey: () => IdSchema,
  createdAt: () => TimestampSchema,
  updatedAt: () => TimestampSchema,
  deletedAt: () => TimestampSchema,
  seq: () => SeqSchema,
});

export const EntrySchema = entryRow.extend({ payers: z.array(PayerSchema), shares: z.array(ShareSchema) }).openapi("Entry");

/** The entry columns a device writes. Authorship and bookkeeping are the server's. */
export const editableEntryColumns = ["kind", "description", "categoryId", "currency", "amountMinor", "entryDate", "occurredAt", "timeZone", "splitKind", "fxRate", "fxSource", "notes"] as const;

const pickAll = <K extends string>(keys: readonly K[]) => Object.fromEntries(keys.map((key) => [key, true])) as { [P in K]: true };

/** Record or edit an expense, whole. */
export const EntryInputSchema = entryRow
  .pick(pickAll(["id", "clientKey", ...editableEntryColumns]))
  .extend({
    payers: z.array(PayerSchema).min(1),
    shares: z.array(ShareSchema).min(1),
    /** The version this edit was composed against; null for a new row. */
    baseSeq: SeqSchema.nullable(),
  })
  .refine((input) => (input.occurredAt === null) === (input.timeZone === null), {
    path: ["timeZone"],
    message: "occurredAt and timeZone are both set or both null.",
  })
  .openapi("EntryInput");

/**
 * An expense after a change, for the activity feed's field-level diff. No fx
 * columns, `updatedAt` or `seq`: those move without the expense changing.
 */
export const EntrySnapshotSchema = entryRow
  .pick({ kind: true, description: true, currency: true, amountMinor: true, entryDate: true, splitKind: true, categoryId: true, notes: true, deletedAt: true })
  .extend({ payers: z.array(MoneyRowSchema), shares: z.array(MoneyRowSchema) })
  .openapi("EntrySnapshot");

const memberRow = createSelectSchema(tables.members, {
  id: () => IdSchema,
  profileId: () => IdSchema,
  displayName: () => NameSchema,
  upiVpa: () => UpiVpaSchema,
  joinedAt: () => TimestampSchema,
  leftAt: () => TimestampSchema,
  updatedAt: () => TimestampSchema,
  seq: () => SeqSchema,
});

export const MemberSchema = memberRow.openapi("Member");
export const MemberCreateSchema = memberRow.pick({ id: true, displayName: true, upiVpa: true }).openapi("MemberCreate");
/** No `profileId`: only an invite hands a place to an account. */
export const MemberUpdateSchema = memberRow.pick({ displayName: true, upiVpa: true, leftAt: true }).openapi("MemberUpdate");

const groupRow = createSelectSchema(tables.meta, {
  id: () => IdSchema,
  name: () => NameSchema,
  defaultCurrency: () => CurrencyCodeSchema,
  createdBy: () => IdSchema,
  createdAt: () => TimestampSchema,
  archivedAt: () => TimestampSchema,
  updatedAt: () => TimestampSchema,
  seq: () => SeqSchema,
});

export const GroupSchema = groupRow.openapi("Group");

/** The group and its creator's member row, in one change. */
export const GroupCreateSchema = groupRow.pick({ id: true, name: true, defaultCurrency: true, isDirect: true, simplifyDebts: true }).extend({ memberId: memberRow.shape.id, displayName: memberRow.shape.displayName }).openapi("GroupCreate");

export const GroupUpdateSchema = groupRow.pick({ name: true, simplifyDebts: true, archivedAt: true }).openapi("GroupUpdate");

export const InviteSchema = createSelectSchema(tables.invites, {
  token: () => IdSchema,
  memberId: () => IdSchema,
  createdBy: () => IdSchema,
  createdAt: () => TimestampSchema,
  expiresAt: () => TimestampSchema,
  redeemedAt: () => TimestampSchema,
}).openapi("Invite");

export const GroupLinkSchema = createSelectSchema(tables.groupLink, { token: () => IdSchema, expiresAt: () => TimestampSchema })
  .pick({ token: true, expiresAt: true })
  .openapi("GroupLink");

export const LiveLinkSchema = z.object({ link: GroupLinkSchema.nullable() }).openapi("LiveLink");

/** The token that stopped being live, or null when none was. */
export const LinkRevocationSchema = z.object({ revoked: IdSchema.nullable() }).openapi("LinkRevocation");

/** What a link is for, answered before anybody has said who they are. */
export const LinkPreviewSchema = z
  .object({
    kind: LinkKindSchema,
    groupId: IdSchema,
    groupName: z.string(),
    inviterName: z.string().nullable(),
    memberCount: z.int().nonnegative(),
    /** The placeholder an invite hands over; null for an open link. */
    memberName: z.string().nullable(),
    isRedeemed: z.boolean(),
    isExpired: z.boolean(),
    isRevoked: z.boolean(),
    /** Whether the caller already holds a place in this group. */
    isMember: z.boolean(),
  })
  .openapi("LinkPreview");

export const PlaceholderSchema = memberRow.pick({ id: true, displayName: true }).openapi("Placeholder");

export const PlaceholderListSchema = z.object({ placeholders: z.array(PlaceholderSchema) }).openapi("PlaceholderList");

export const JoinedSchema = z.object({ groupId: IdSchema, member: MemberSchema }).openapi("Joined");

/** Take one of the link's placeholders (`memberId`), or arrive as somebody new (`displayName`). */
export const JoinRequestSchema = z
  .object({
    memberId: IdSchema.nullable(),
    displayName: NameSchema.nullable(),
  })
  .openapi("JoinRequest");

/** `previousName` is set by a rename alone. */
export const MemberEventPayloadSchema = z.object({ displayName: z.string(), previousName: z.string().nullable() }).openapi("MemberEventPayload");
export const GroupEventPayloadSchema = z.object({ name: z.string(), previousName: z.string().nullable() }).openapi("GroupEventPayload");
export const LinkEventPayloadSchema = z.object({ expiresAt: TimestampSchema }).openapi("LinkEventPayload");

/** One line of activity. Exactly one of `entry`, `member`, `group` and `link` is set, per `kind`. */
export const EventSchema = createSelectSchema(tables.events, {
  id: () => IdSchema,
  actorId: () => IdSchema,
  createdAt: () => TimestampSchema,
  kind: () => EventKindSchema,
  subjectId: () => IdSchema,
  entry: () => EntrySnapshotSchema,
  member: () => MemberEventPayloadSchema,
  group: () => GroupEventPayloadSchema,
  link: () => LinkEventPayloadSchema,
  seq: () => SeqSchema,
  ordinal: () => z.int().nonnegative(),
}).openapi("Event");

/**
 * One group's changes since a cursor. `limit` counts changes, not rows, and a
 * page is only cut between sequence numbers, so a write arrives whole.
 */
export const ChangePageSchema = z
  .object({
    groupId: IdSchema,
    /** The cursor to send next time. */
    seq: SeqSchema,
    hasMore: z.boolean(),
    /** Null when the group row has not changed since the cursor. */
    group: GroupSchema.nullable(),
    members: z.array(MemberSchema),
    entries: z.array(EntrySchema),
    events: z.array(EventSchema),
    /** Set once, on the page that says the group was collected. */
    purgedAt: TimestampSchema.nullable(),
  })
  .openapi("ChangePage");

/** The kinds that wake a device: an expense, somebody arriving, somebody leaving. */
export const notifiableKinds = ["entry", "member_joined", "member_left"] as const satisfies readonly (typeof tables.eventKinds)[number][];

/** The data-only push message: which event to fetch, not what it says. */
export const PushDataSchema = z
  .object({
    groupId: IdSchema,
    eventId: IdSchema,
    kind: EventKindSchema,
    subjectId: IdSchema,
  })
  .openapi("PushData");

export type Payer = z.infer<typeof PayerSchema>;
export type Share = z.infer<typeof ShareSchema>;
export type MoneyRow = z.infer<typeof MoneyRowSchema>;
export type Entry = z.infer<typeof EntrySchema>;
export type EntryInput = z.infer<typeof EntryInputSchema>;
export type EntrySnapshot = z.infer<typeof EntrySnapshotSchema>;
export type Member = z.infer<typeof MemberSchema>;
export type MemberCreate = z.infer<typeof MemberCreateSchema>;
export type MemberUpdate = z.infer<typeof MemberUpdateSchema>;
export type Group = z.infer<typeof GroupSchema>;
export type GroupCreate = z.infer<typeof GroupCreateSchema>;
export type GroupUpdate = z.infer<typeof GroupUpdateSchema>;
export type Invite = z.infer<typeof InviteSchema>;
export type GroupLink = z.infer<typeof GroupLinkSchema>;
export type LiveLink = z.infer<typeof LiveLinkSchema>;
export type LinkRevocation = z.infer<typeof LinkRevocationSchema>;
export type LinkPreview = z.infer<typeof LinkPreviewSchema>;
export type Placeholder = z.infer<typeof PlaceholderSchema>;
export type PlaceholderList = z.infer<typeof PlaceholderListSchema>;
export type JoinRequest = z.infer<typeof JoinRequestSchema>;
export type Joined = z.infer<typeof JoinedSchema>;
export type MemberEventPayload = z.infer<typeof MemberEventPayloadSchema>;
export type GroupEventPayload = z.infer<typeof GroupEventPayloadSchema>;
export type LinkEventPayload = z.infer<typeof LinkEventPayloadSchema>;
export type Event = z.infer<typeof EventSchema>;
export type ChangePage = z.infer<typeof ChangePageSchema>;
export type PushData = z.infer<typeof PushDataSchema>;
