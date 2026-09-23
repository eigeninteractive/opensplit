/**
 * A `.sql` import is the file's text.
 *
 * Wrangler's `Text` rule in `wrangler.jsonc` makes this true at build time;
 * this is what makes it true at typecheck time. Used only by drizzle-kit's
 * generated `src/do/migrations/migrations.js`, which imports each migration
 * so the Durable Object can apply it to itself.
 */
declare module "*.sql" {
  const content: string;
  export default content;
}
