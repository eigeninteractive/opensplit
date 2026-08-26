# Email templates

Three templates, and every one of them exists to emit `{{ .Token }}` and
nothing else.

Supabase's stock templates send `{{ .ConfirmationURL }}` — a magic link. The
app asks for a six-digit code, so against the stock templates the "check your
email" step waits for a number that is never sent, on every path: signing in,
signing in on a second device, and attaching an address to an anonymous
account. There is no code change that fixes that; the token has to be in the
mail.

The reason it is a code rather than a link is in
`lib/presentation/widgets/account_section.dart`, and it is worth repeating
here, because it is also why these templates deliberately do **not** offer the
link as a fallback:

* A link opens in whichever browser the mail app prefers, which is not the one
  holding the session. On mobile it leaves the app entirely.
* Corporate mail scanners follow links in incoming mail. A `ConfirmationURL` is
  single-use, so the scanner spends it and the recipient gets an error — for a
  message they had not opened yet.

A template carrying both a link and a code has the second problem anyway. So
these carry the code alone.

| Template | Sent when | Verified as |
|---|---|---|
| `confirmation.html` | signing in with an address that has no account yet | `OtpType.email` |
| `magic_link.html` | signing in with an address that already has one | `OtpType.email` |
| `email_change.html` | attaching an address to an anonymous session | `OtpType.emailChange` |

`email_change` is the one that matters most and the one most easily missed:
it is the entire "save my account" flow, and it uses a different token type
from the other two.

## Local

Already wired up — `supabase/config.toml` points at these files under
`[auth.email.template.*]`, and `supabase start` picks them up. Changing a
template needs a `supabase stop && supabase start`, not a `db reset`.

## Hosted

Templates are **not** deployed by `supabase db push` or `supabase functions
deploy`. Paste them by hand, once, into
Authentication → Emails → Templates, matching the table above. Until you do,
every hosted build sends magic links and no code ever arrives.

Check it the way it actually fails, which is silently:

```bash
# Attach an address to a fresh anonymous session, then read what was sent.
# Locally, http://127.0.0.1:54324 is Mailpit.
```

If the mail contains a URL and no six-digit number, the template did not take.
