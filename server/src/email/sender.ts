/** Sign-in codes go out through Resend (Cloudflare Email Sending needs Workers Paid). */
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

/** The brand domain already verified with the provider. */
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
      // Resend's reason, never the address.
      throw new EmailNotSent(`Resend refused the message: ${response.status} ${await response.text()}`);
    }
  }
}

/** Local development without a key: the code goes to the console. */
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

/** A code rather than a magic link: links open in the wrong browser and mail scanners consume them. */
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
