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
