import { drizzleAdapter } from "@better-auth/drizzle-adapter/relations-v2";
import { betterAuth } from "better-auth";
import { anonymous } from "better-auth/plugins/anonymous";
import { bearer } from "better-auth/plugins/bearer";
import { emailOTP } from "better-auth/plugins/email-otp";
import { drizzle } from "drizzle-orm/d1";

import * as authSchema from "./auth-schema";
import { nextProfileVersion, profileVersion } from "./db/d1/profile-version";
import { profiles } from "./db/d1/schema";
import { createEmailSender } from "./email/sender";
import { signInCodeMessage } from "./email/sign-in-code";
import { handOverGuest } from "./forget";

/**
 * Better Auth on D1. Its tables are generated into `src/auth-schema.ts`;
 * application data about a person lives in `profiles`, outside them.
 *
 * The whole membership model rests on a user id surviving an identity being
 * attached, so linking goes through `linkSocial` and email-OTP `changeEmail`
 * (both keep the session's user) and the anonymous plugin only mints guests.
 */
/** Seconds a session lives after it was last used. */
export const SESSION_LIFETIME = 60 * 60 * 24 * 365;

export function build(env: Env) {
  const email = createEmailSender(env);

  return betterAuth({
    database: drizzleAdapter(drizzle(env.DB, { relations: authSchema.authRelations }), { provider: "sqlite", schema: authSchema }),
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.APP_ORIGIN,
    basePath: "/api/auth",
    trustedOrigins: [env.APP_ORIGIN],

    // No passwords: Google, an emailed code, or a guest.
    emailAndPassword: { enabled: false },

    /**
     * A year from last use, extended at most daily. The app is opened for trips,
     * not every day, and a guest whose session lapses can never get back in.
     * Under Chrome's 400-day cap on cookie lifetimes, so the web lasts as long.
     * Sessions are rows, so a long one is still revocable at any moment.
     */
    session: { expiresIn: SESSION_LIFETIME, updateAge: 60 * 60 * 24 },

    socialProviders: {
      google: { clientId: env.GOOGLE_CLIENT_ID, clientSecret: env.GOOGLE_CLIENT_SECRET },
    },

    account: {
      accountLinking: {
        enabled: true,
        trustedProviders: ["google"],
        // A guest's email is a placeholder that matches nothing, so linking needs this. Safe
        // because only Google is trusted, and its verified email is checked by signature.
        allowDifferentEmails: true,
      },
    },

    plugins: [
      /**
       * Attaching an identity keeps the guest's user id, so that path never
       * reaches this hook. Signing in to an account that already existed does:
       * the guest's places go to that account, and `handOverGuest` ends the
       * guest itself (the plugin's own deletion stays off, so it happens only
       * after the handover).
       */
      anonymous({
        disableDeleteAnonymousUser: true,
        async onLinkAccount({ anonymousUser, newUser }) {
          if (newUser.user.id === anonymousUser.user.id || newUser.user.isAnonymous) return;
          await handOverGuest(env, anonymousUser.user.id, newUser.user.id);
        },
      }),

      emailOTP({
        otpLength: 8,
        expiresIn: 600,
        allowedAttempts: 3,
        resendStrategy: "rotate",
        storeOTP: "hashed",
        // Attaching an address to the session in hand: how a guest keeps their groups.
        changeEmail: { enabled: true },
        async sendVerificationOTP({ email: address, otp }) {
          await email.send(signInCodeMessage(address, otp));
        },
      }),

      // `Authorization: Bearer` on Android; the web uses its cookie.
      bearer(),
    ],

    databaseHooks: {
      user: { create: { after: (user) => createProfile(env, user) } },
    },
  });
}

/**
 * Every account gets a profile. A guest's is nameless on purpose: claiming a
 * placeholder adopts its name only into a profile that has none.
 */
async function createProfile(env: Env, user: { id: string; name?: string | null; isAnonymous?: boolean | null }): Promise<void> {
  const chosen = user.isAnonymous ? null : user.name?.trim() || null;
  const db = drizzle(env.DB);
  await db.batch([nextProfileVersion(db), db.insert(profiles).values({ id: user.id, displayName: chosen, upiVpa: null, updatedAt: new Date().toISOString(), version: profileVersion }).onConflictDoNothing()]);
}

export type Auth = ReturnType<typeof build>;

/** One instance per env object, so isolated test storage gets its own. */
const instances = new WeakMap<Env, Auth>();

export function createAuth(env: Env): Auth {
  let auth = instances.get(env);
  if (!auth) {
    auth = build(env);
    instances.set(env, auth);
  }
  return auth;
}
