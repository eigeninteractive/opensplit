/**
 * Sending email, behind one method.
 *
 * Cloudflare's own Email Sending would be the obvious choice — `env.EMAIL.send()`,
 * no third party, no API key — but it is Workers Paid only, and this runs on
 * Free. Resend's free tier is 3,000 a month against an already-verified domain,
 * so that is what is wired up.
 *
 * The interface exists so that swapping back is this file and nothing else.
 */
export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
  html: string;
}

export interface EmailSender {
  send(message: EmailMessage): Promise<void>;
}

export class EmailNotSent extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EmailNotSent";
  }
}

/**
 * Where sign-in codes come from.
 *
 * A subdomain of the brand's zone rather than the app's own host, because that
 * is the domain already verified with the sending provider — and a sending
 * domain's reputation is a separate thing from where the app is served.
 */
const FROM = "OpenSplit <no-reply@support.eigeninteractive.com>";

class ResendSender implements EmailSender {
  constructor(private readonly apiKey: string) {}

  async send(message: EmailMessage): Promise<void> {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM,
        to: [message.to],
        subject: message.subject,
        text: message.text,
        html: message.html,
      }),
    });

    if (!response.ok) {
      // The body carries Resend's reason; the address never does, so this is
      // safe to log and useful when a domain falls out of verification.
      throw new EmailNotSent(`Resend refused the message: ${response.status} ${await response.text()}`);
    }
  }
}

/**
 * What runs when no API key is configured.
 *
 * Deliberately not a failure. A local `wrangler dev` with no Resend account
 * must still be able to complete a sign-in, so the code goes to the console
 * where the developer can read it. Anything that reaches production without a
 * key would be silently not sending mail, which is why `createEmailSender`
 * says so loudly on construction rather than per message.
 */
class ConsoleSender implements EmailSender {
  async send(message: EmailMessage): Promise<void> {
    console.log(`[email] to=${message.to} subject=${message.subject}`);
    console.log(message.text);
  }
}

export function createEmailSender(env: Env): EmailSender {
  if (!env.RESEND_API_KEY) {
    console.warn("[email] RESEND_API_KEY is not set; codes will be logged, not sent.");
    return new ConsoleSender();
  }
  return new ResendSender(env.RESEND_API_KEY);
}

/**
 * The one message this application sends.
 *
 * A code rather than a magic link, and that is a decision worth keeping: links
 * open in whichever browser the mail app prefers, lose the app's context
 * entirely, and are routinely consumed by corporate mail scanners before the
 * recipient sees them.
 */
export function signInCodeMessage(to: string, code: string): EmailMessage {
  const text = `Your OpenSplit code is ${code}

It expires in ten minutes and can be used once.
If you did not ask for this, you can ignore this message — nothing has
changed on your account.
`;

  const html = [
    '<div style="font-family:system-ui,-apple-system,Segoe UI,sans-serif;font-size:16px;line-height:1.5;color:#212121">',
    "<p>Your OpenSplit code is</p>",
    `<p style="font-size:32px;font-weight:600;letter-spacing:0.12em;font-family:ui-monospace,SFMono-Regular,Menlo,monospace">${code}</p>`,
    "<p>It expires in ten minutes and can be used once.</p>",
    '<p style="color:#5f5f5f">If you did not ask for this, you can ignore this message — nothing has changed on your account.</p>',
    "</div>",
  ].join("");

  return { to, subject: `${code} is your OpenSplit code`, text, html };
}
