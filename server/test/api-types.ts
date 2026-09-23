/**
 * The wire types, as a client sees them.
 *
 * Re-exported through one file rather than imported from `schemas/ledger`
 * everywhere, because the HTTP suite is deliberately written from outside: it
 * parses JSON and asserts on the result, the way the Dart client will. Pulling
 * the types from the schemas keeps that honest — if a response shape changes,
 * this suite stops compiling rather than silently asserting on `any`.
 */
export type { Bootstrap } from "../src/api/ledger";
export type { ChangePage, Entry, Group, Member } from "../src/schemas/ledger";
