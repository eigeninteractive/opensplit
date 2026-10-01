/** A `.sql` import is its text (wrangler's `Text` rule); drizzle-kit's `migrations.js` imports them. */
declare module "*.sql" {
  const content: string;
  export default content;
}
