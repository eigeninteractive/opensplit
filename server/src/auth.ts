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
 * Better Auth on D1. Its tables are generated into `src/auth-schema.ts`;
 * application data about a person lives in `profiles`, outside them.
 *
 * The whole membership model rests on a user id surviving an identity being
 * attached, so linking goes through `linkSocial` and email-OTP `changeEmail`
 * (both keep the session's user) and the anonymous plugin only mints guests.
 */
export function build(env: Env) {
  const email = createEmailSender(env);

  return betterAuth({
    database: drizzleAdapter(drizzle(env.DB, { schema: authSchema }), { provider: "sqlite", schema: authSchema }),
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.APP_ORIGIN,
    basePath: "/api/auth",
    trustedOrigins: [env.APP_ORIGIN],

    // No passwords: Google, an emailed code, or a guest.
    emailAndPassword: { enabled: false },

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
      // Identity is attached in place, so the plugin's migrate-and-delete path must never fire.
      anonymous({ disableDeleteAnonymousUser: true }),

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
  await drizzle(env.DB).insert(profiles).values({ id: user.id, displayName: chosen, upiVpa: null, updatedAt: new Date().toISOString() }).onConflictDoNothing();
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
