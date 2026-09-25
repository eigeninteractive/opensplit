# Principles

These are commitments, not aspirations. They are published here so that they
can be held against us.

### 1. Never gate the act of logging an expense

No daily caps, no expense limits, no interstitials, no "you've used 3 of your
4 free entries this month". Recording what you spent is the entire function of
this app, and it stays free for everyone forever. This is the specific friction
that cost the incumbent its goodwill, and it is the first thing anyone
monetising an app like this reaches for.

### 2. No ads. No analytics SDKs. No data sale. Ever.

There is no third-party analytics SDK in the app and there never will be.
Product metrics come from aggregate database counts — how many groups exist —
never from watching what you do. Your expense history describes where you go,
who you go with, and what you can afford. It is not a dataset.

### 3. No venture funding

Splitwise did not paywall because its founders turned bad. It took money that
mandated growth, growth mandated revenue, and revenue mandated extraction. The
structure produced the outcome. Refusing that structure is the actual defence
here; every other principle on this page is downstream of it.

### 4. AGPL-3.0

Chosen specifically so that a proprietary hosted fork cannot take this work,
close it, and outcompete the project it came from. If you run a modified
OpenSplit as a service, your users get your changes.

### 5. If monetisation ever happens, charge for convenience, never for function

A hosted tier, a one-time purchase, sponsorship — all legitimate. A feature
gate is not. The test is simple: does paying make something *easier*, or does
not paying make something *impossible*? Only the first is allowed.

### 6. Your records are portable, even though the server is not

The hosted backend runs on Cloudflare Durable Objects, D1 and KV. Those are not
products you can stand up yourself. There is no self-host path, we are not
going to imply one by shipping a portability seam that nobody tests, and this
is the only principle on this page that is a limitation rather than a promise.

What protects you is the larger half, and it is not a consolation. The backend
stores rows and enforces one invariant; it computes nothing. Every number you
see — every split, every balance, every simplified debt — is worked out on your
device from a journal that lives there, in plain SQLite, exports to CSV, and
works with no server at all. See #7. The client reaches the server through one
Dart interface over an HTTP API published as OpenAPI, so pointing it somewhere
else is writing one class against a documented contract. And AGPL-3.0 obliges
anyone running a modified OpenSplit as a service to publish their changes.

We chose a backend we cannot hand you, and kept the thing that means you do not
need one.

### 7. The app survives this project being abandoned

Your data lives on your device in a plain SQLite database. If the servers
disappear tomorrow, the app keeps working with what it has, and you can export
everything to CSV. Nothing here is designed so that our disappearance takes your
records with it.
