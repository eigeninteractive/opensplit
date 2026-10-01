import { describe, expect, it } from "vitest";

import { signInCodeMessage } from "../src/email/sign-in-code";

describe("the sign-in code email", () => {
  const message = signInCodeMessage("ana@example.com", "12345678");

  it("puts the code in the subject, the text and the HTML", () => {
    expect(message.to).toBe("ana@example.com");
    expect(message.subject).toBe("12345678 is your OpenSplit code");
    expect(message.text).toContain("Your OpenSplit code is 12345678");
    expect(message.html).toContain(">12345678</div>");
  });

  it("loads its lockup from the public site, since a mail client cannot reach anything else", () => {
    expect(message.html).toContain('src="https://opensplit.eigeninteractive.com/email/wordmark.png"');
  });
});
