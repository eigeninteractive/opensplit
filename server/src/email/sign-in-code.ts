import type { EmailMessage } from "./sender";

/**
 * The sign-in code email, in the landing page's palette and type (site/site.css).
 *
 * Mail clients are not browsers: Gmail drops <style> rules it cannot place, loads no web fonts and
 * no SVG, and Outlook lays out only tables. So every rule is inline, the layout is tables, and the
 * lockup is a PNG (tool/store_graphics.py) rather than the site's inline mark. Instrument Sans is
 * named first for the clients that have it, with the site's fallbacks after. The code is set the
 * way the app sets a figure it wants read: the same face, large, with tabular figures.
 *
 * Light only, declared so: the lockup is drawn on the card's surface, and a client inverting the
 * card around it would leave it a pale rectangle.
 */

/** Where the email's image and links point: the production site, wherever the message is sent from. */
const SITE = "https://opensplit.eigeninteractive.com";

/** The site's tokens, as named there. */
const PAPER = "#fcf8ff";
const WASH = "#f6f2fa";
const INK = "#1c1b21";
const SLATE = "#47464f";
const MUTED = "#625f6b";
const LINE = "#e4e0ea";
const VIOLET = "#5b5891";
const VIOLET_DEEP = "#434078";
const LILAC = "#e3dfff";

const SANS = `'Instrument Sans',system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif`;

/** A code rather than a magic link: links open in the wrong browser and mail scanners consume them. */
export function signInCodeMessage(to: string, code: string): EmailMessage {
  const text = `Your OpenSplit code is ${code}

It expires in ten minutes and can be used once.
If you did not ask for this, you can ignore this message — nothing has
changed on your account.

OpenSplit · free, open-source expense splitting
${SITE}
`;

  return { to, subject: `${code} is your OpenSplit code`, text, html: html(code) };
}

function html(code: string): string {
  const link = `color:${VIOLET};text-decoration:underline;white-space:nowrap`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>Your OpenSplit code</title>
<style>
@font-face{font-family:'Instrument Sans';font-weight:400;src:url(${SITE}/fonts/InstrumentSans-Regular.ttf) format('truetype')}
@font-face{font-family:'Instrument Sans';font-weight:600;src:url(${SITE}/fonts/InstrumentSans-SemiBold.ttf) format('truetype')}
:root{color-scheme:light;supported-color-schemes:light}
</style>
</head>
<body style="margin:0;padding:0;background:${WASH};color:${INK};font-family:${SANS};-webkit-font-smoothing:antialiased">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${WASH}">It expires in ten minutes and can be used once.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${WASH}">
<tr><td align="center" style="padding:40px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:480px">
<tr><td style="background:${PAPER};border:1px solid ${LINE};border-radius:24px;padding:36px 32px;box-shadow:0 1px 2px rgba(67,64,120,0.08),0 8px 24px -8px rgba(67,64,120,0.16)">
<a href="${SITE}" style="text-decoration:none"><img src="${SITE}/email/wordmark.png" width="128" height="25" alt="OpenSplit" style="display:block;border:0;width:128px;height:25px;color:${INK};font-size:20px;font-weight:600"></a>
<h1 style="margin:36px 0 8px;font-size:28px;line-height:1.15;letter-spacing:-0.03em;font-weight:600;color:${INK}">Your code</h1>
<p style="margin:0 0 24px;font-size:16px;line-height:1.6;color:${SLATE}">Enter it in OpenSplit to carry on.</p>
<div style="background:${LILAC};border-radius:16px;padding:20px 12px;text-align:center;font-size:36px;line-height:1.2;font-weight:600;letter-spacing:0.12em;color:${VIOLET_DEEP};font-variant-numeric:tabular-nums">${code}</div>
<p style="margin:24px 0 0;font-size:16px;line-height:1.6;color:${SLATE}">It expires in ten minutes and can be used once.</p>
<p style="margin:24px 0 0;padding-top:20px;border-top:1px solid ${LINE};font-size:14px;line-height:1.6;color:${MUTED}">If you did not ask for this, you can ignore this message — nothing has changed on your account.</p>
</td></tr>
<tr><td style="padding:24px 8px 0;font-size:13px;line-height:1.6;color:${MUTED};text-align:center">
Free, open-source expense splitting for Android and the web.<br>
<a href="${SITE}" style="${link}">opensplit.eigeninteractive.com</a> · <a href="${SITE}/privacy" style="${link}">Privacy</a> · <a href="https://github.com/eigeninteractive/opensplit" style="${link}">Source code</a>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;
}
