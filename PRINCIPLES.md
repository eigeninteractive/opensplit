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

### 6. Self-hosting is a first-class path, not a courtesy

`docker compose up` gives you a working instance in under fifteen minutes. The
backend is deliberately thin — it stores rows and enforces one invariant, and
computes nothing — so that replacing it is a weekend's work rather than a
reimplementation. Every release is tested against a self-hosted instance.

### 7. The app survives this project being abandoned

Your data lives on your device in a plain SQLite database. If the servers
disappear tomorrow, the app keeps working with what it has, and you can export
everything to CSV. Nothing here is designed so that our disappearance takes your
records with it.
