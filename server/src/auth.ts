import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { anonymous } from "better-auth/plugins/anonymous";
import { bearer } from "better-auth/plugins/bearer";
import { emailOTP } from "better-auth/plugins/email-otp";
import { drizzle } from "drizzle-orm/d1";

import * as authSchema from "./auth-schema";
import { profiles } from "./db/d1/schema";
import { createEmailSender, signInCodeMessage } from "./email/sender";

/**
 * Identity, on D1.
 *
 * Better Auth owns `user`, `session`, `account` and `verification`. Its schema
 * is emitted as a Drizzle schema by `npm run auth:generate` into
 * `src/auth-schema.ts`, and `drizzle-kit` turns that plus our own tables into
 * one migration set. Neither generated file is ever hand-edited: an upgrade
 * should arrive as a reviewable diff rather than as a surprise at runtime.
 *
 * Application data — a person's display name and payment handle — lives in
 * `profiles`, deliberately outside those tables. Auth tables are the
 * generator's to rewrite, and the ledger's idea of who somebody is should not
 * be in the blast radius of that.
 *
 * ## The anonymous plugin is here for exactly one thing
 *
 * It mints guest accounts. Its linking path — which creates a *new* user on
 * sign-in, hands you `onLinkAccount`, and deletes the guest — is deliberately
 * not used, and `disableDeleteAnonymousUser` keeps it from firing.
 *
 * The reason is that this app's whole membership model rests on the user id
 * surviving. A member row in a group points at a profile id; attaching Google
 * to a guest session has to leave every one of those alone. Better Auth's own
 * `linkSocial` and email-OTP `changeEmail` do exactly that — they operate on
 * the session in hand and preserve its user — so the linking happens through
 * those, in `identity/`, and the plugin never sees a sign-in with a guest
 * session to migrate.
 */
export function build(env: Env) {
  const email = createEmailSender(env);

  return betterAuth({
    database: drizzleAdapter(drizzle(env.DB, { schema: authSchema }), {
      provider: "sqlite",
      schema: authSchema,
    }),
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.APP_ORIGIN,
    basePath: "/api/auth",
    trustedOrigins: [env.APP_ORIGIN],

    // There are no passwords in this product and there will not be. Sign-in
    // is Google, an emailed code, or being a guest.
    emailAndPassword: { enabled: false },

    socialProviders: {
      google: {
        clientId: env.GOOGLE_CLIENT_ID,
        clientSecret: env.GOOGLE_CLIENT_SECRET,
      },
    },

    /**
     * Linking has to be on, and Google has to be trusted, or every attempt to
     * attach an identity to a guest session fails — which is the one failure
     * that silently strands somebody's ledger under an account they can never
     * sign into again.
     */
    account: {
      accountLinking: {
        enabled: true,
        trustedProviders: ["google"],

        /**
         * Required, not lax.
         *
         * Better Auth otherwise refuses to link a social account whose email
         * differs from the one on the session — and a guest's email is the
         * anonymous plugin's `@anonymous.placeholder.invalid`, which never
         * matches anything. With this off, attaching Google to a guest
         * account is impossible, which is the single most common thing
         * anybody does in this app.
         *
         * What makes it safe is the line above: only Google is trusted, and
         * its ID tokens carry a verified email that this server checks the
         * signature of. The risk this option normally guards against is
         * linking an address nobody proved they own, and that cannot happen
         * through a provider on the trusted list.
         */
        allowDifferentEmails: true,
      },
    },

    plugins: [
      anonymous({
        // See the note above: the migration path is not used, and a guest
        // whose identity was attached in place must not be deleted out from
        // under the groups it owns.
        disableDeleteAnonymousUser: true,
      }),

      emailOTP({
        // Eight digits, matching what the app has always said it sends.
        otpLength: 8,
        expiresIn: 600,
        allowedAttempts: 3,
        // A fresh code on every request, so an old mail cannot be replayed.
        resendStrategy: "rotate",
        // Codes are stored hashed: a leaked database row should not be a
        // working credential.
        storeOTP: "hashed",

        /**
         * Off by default, and this app cannot work without it.
         *
         * This is the endpoint that attaches an address to the session you
         * already have — the linking half of the email flow, and the reason
         * a guest can become a real account without losing a single group.
         * Without it, every email arrival would be a sign-in.
         */
        changeEmail: { enabled: true },
        async sendVerificationOTP({ email: address, otp }) {
          await email.send(signInCodeMessage(address, otp));
        },
      }),

      // Lets Android send `Authorization: Bearer …`. The web build sends
      // nothing and relies on its cookie; both resolve to the same session.
      bearer(),
    ],

    databaseHooks: {
      user: {
        create: {
          async after(user) {
            await createProfile(env, user);
          },
        },
      },
    },
  });
}

/**
 * The replacement for `handle_new_user()`.
 *
 * `display_name` is null for a guest, and that null is load-bearing. Somebody
 * arriving on an invite link is signed in as a guest a moment earlier and has
 * no name of their own, while the group already knows them as whatever a friend
 * typed on the placeholder. Claiming the slot adopts that name — but only if
 * the profile has none, which is the check that stops a name somebody actually
 * chose being overwritten by a friend's guess.
 *
 * The anonymous plugin invents a display name of its own. Storing it would make
 * that check always false, so it is discarded here.
 */
async function createProfile(env: Env, user: { id: string; name?: string | null; isAnonymous?: boolean | null }): Promise<void> {
  const chosen = user.isAnonymous ? null : (user.name?.trim() ?? "") || null;

  await drizzle(env.DB)
    .insert(profiles)
    .values({
      id: user.id,
      displayName: chosen,
      upiVpa: null,
      updatedAt: new Date().toISOString(),
    })
    .onConflictDoNothing();
}

export type Auth = ReturnType<typeof build>;

/**
 * One instance per environment.
 *
 * Keyed on the env object rather than a module-level singleton so that a test
 * file with its own isolated storage gets its own instance, and so that nothing
 * survives between them.
 */
const instances = new WeakMap<Env, Auth>();

export function createAuth(env: Env): Auth {
  const existing = instances.get(env);
  if (existing) return existing;

  const auth = build(env);
  instances.set(env, auth);
  return auth;
}
