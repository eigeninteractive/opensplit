import { env } from "cloudflare:workers";
import { importJWK, type JWK, SignJWT } from "jose";

/**
 * A Google sign-in, driven through the real verification path.
 *
 * Better Auth verifies an ID token properly: RS256, against the JWKS at
 * `googleapis.com/oauth2/v3/certs`, checking the audience against the
 * configured client id and refusing anything stale. None of that is stubbed —
 * `vitest.config.ts` generates a keypair, serves its public half where Google's
 * would be, and hands the private half in as a binding so these tokens are
 * genuinely signed.
 *
 * Which matters, because the branches these tests cover decide whether
 * somebody's ledger survives attaching an account. A test that bypassed
 * verification would prove the branch ran, not that it ran for a token the
 * server actually accepted.
 */

export interface GoogleIdentity {
  /**
   * Google's own stable id for the account. Two tokens sharing it are one
   * Google account, which is what the already-claimed cases turn on.
   */
  sub: string;
  email: string;
  name?: string;
}

export async function googleIdToken(identity: GoogleIdentity): Promise<string> {
  const jwk = env.TEST_GOOGLE_PRIVATE_JWK as JWK;
  const key = await importJWK(jwk, "RS256");

  return new SignJWT({
    email: identity.email,
    email_verified: true,
    name: identity.name ?? identity.email.split("@")[0],
  })
    .setProtectedHeader({ alg: "RS256", kid: jwk.kid })
    .setIssuer("https://accounts.google.com")
    .setAudience(env.GOOGLE_CLIENT_ID)
    .setSubject(identity.sub)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
}
