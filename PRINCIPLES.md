# Principles

These are commitments, not aspirations. They are published here so that they
can be held against us.

### 1. Free for everyone, forever

Every feature, for everyone. No premium tier, no daily caps, no expense limits,
no interstitials, no "you've used 3 of your 4 free entries this month".
Recording what you spent is the entire function of this app, and gating it is
the specific friction that cost the incumbent its goodwill.

### 2. Open source

The code is public under the AGPL-3.0. Anyone can read it, use it, change it
and share it. What is built from it stays open source too: if you run a
modified OpenSplit as a service, your users get your changes.

### 3. No ads. No analytics SDKs. No data sale. Ever.

There is no third-party analytics SDK in the app and there never will be.
Product metrics come from aggregate database counts — how many groups exist —
never from watching what you do. Your expense history describes where you go,
who you go with, and what you can afford. It is not a dataset.

### 4. No venture funding

Apps like this one rarely start paywalling because their founders turn bad.
Venture money mandates growth, growth mandates revenue, and revenue mandates
extraction. The structure produces the outcome. Refusing that structure is the
actual defence here; every other principle on this page is downstream of it.

### 5. You can always leave, and take everything with you

The journal is yours and it is already on your device: plain SQLite, exported to
CSV whenever you ask. The backend stores rows and enforces one invariant; every
number you see is computed on your device from data you already hold. The client
is generated from a published OpenAPI contract (`docs/openapi.json`), so a fork
points at a different server by serving that contract and changing one URL.

The backend itself runs on Cloudflare Durable Objects, D1 and KV, which you
cannot run yourself. There is no self-host path and we will not imply one with a
portability layer nobody tests.

### 6. The app survives this project being abandoned

Your data lives on your device in a plain SQLite database. If the servers
disappear tomorrow, the app keeps working with what it has, and you can export
everything to CSV. Nothing here is designed so that our disappearance takes your
records with it.
