import { drizzle } from "drizzle-orm/d1";
import type { Context } from "hono";
import type { z } from "zod";

import { groupFor } from "./api/invites";
import { group } from "./api/routing";
import type { AppEnv } from "./context";
import type { LinkPreviewSchema } from "./schemas/ledger";

type LinkPreview = z.infer<typeof LinkPreviewSchema>;

/** The client's route for a link somebody was sent: `/app/join/:token`. */
const joinPath = /^\/app\/join\/([A-Za-z0-9_-]{1,128})\/?$/;

/** The token a path carries, when it is a join link. */
export function joinToken(pathname: string): string | null {
  return joinPath.exec(pathname)?.[1] ?? null;
}

/** What a chat app shows under a pasted link: who is asking, and into what. */
export function previewText(link: LinkPreview): { title: string; description: string } {
  const people = `${link.memberCount} ${link.memberCount === 1 ? "person" : "people"}`;
  const title = `Join ${link.groupName} on OpenSplit`;
  const description = link.inviterName ? `${link.inviterName} invited you to split expenses with ${people}.` : `Split expenses with ${people}. Open the link to join.`;
  return { title, description };
}

/**
 * The client's document with its link preview rewritten for one invite, so a
 * pasted link unfurls as an invitation to a named group rather than as the
 * landing page.
 *
 * Says nothing the link does not already say to whoever holds it: this is
 * what `GET /links/:token` answers with no session. A link that is dead, or
 * a lookup that fails, leaves the document as it was. A preview is never a
 * reason not to serve the app.
 */
export async function withLinkPreview(c: Context<AppEnv>, token: string, document: Response): Promise<Response> {
  if (!document.ok || !document.headers.get("content-type")?.includes("text/html")) return document;

  let link: LinkPreview | null = null;
  try {
    const groupId = await groupFor(drizzle(c.env.DB), token);
    if (!groupId) return document;
    const result = await group(c, groupId).peekLink(token, null);
    link = result.ok ? result.value : null;
  } catch (error) {
    console.error("link preview", error);
    return document;
  }
  if (!link || link.isRevoked || link.isExpired) return document;

  const origin = new URL(c.req.url).origin;
  const { title, description } = previewText(link);
  const image = `${origin}/store/og-invite.png`;
  const alt = "OpenSplit: you're invited to a group.";
  const content = new Map([
    ["og:title", title],
    ["og:description", description],
    ["og:url", `${origin}/app/join/${token}`],
    ["og:image", image],
    ["og:image:alt", alt],
    ["twitter:title", title],
    ["twitter:description", description],
    ["twitter:image", image],
    ["twitter:image:alt", alt],
  ]);

  // setAttribute escapes: a group's name is whatever its members typed.
  return new HTMLRewriter()
    .on("meta", {
      element(meta) {
        const value = content.get(meta.getAttribute("property") ?? meta.getAttribute("name") ?? "");
        if (value !== undefined) meta.setAttribute("content", value);
      },
    })
    .transform(document);
}
