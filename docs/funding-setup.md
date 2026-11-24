# Maintaining OpenSplit funding

The [public support page](https://opensplit.eigeninteractive.com/support)
explains how contributions fund OpenSplit and lists the people who help the
project.

## Update a funding route

1. Open the public checkout and verify the amount or currency, payment
   options and frequency. Check payout readiness in the provider dashboard.
   List a recurring payment option once its public checkout supports it.
2. Update [the support page](../site/support.html) and
   [funding.json](../site/funding.json). Active plans must point to a verified
   channel. When a provider link changes, also check the repository's
   [Sponsor button configuration](../.github/FUNDING.yml).
3. Run `flutter test test/site_meta_test.dart` and validate the manifest
   against the [funding.json schema](https://fundingjson.org/). The
   [repository](../.well-known/funding-manifest-urls) and
   [website](../site/.well-known/funding-manifest-urls) provenance files
   both point to the canonical manifest.
4. Use the [normal release workflow](runbook.md#every-release) to publish the
   full bundle. After deployment, check the support page, manifest, provenance
   files, Sponsor button and public checkout links.

## Acknowledge supporters

Keep one list on the support page for people who help with testing, feedback,
documentation, code or funding. Use their chosen name or handle and give them a
chance to opt out before publishing it. Respect provider privacy choices and
honor corrections and removal requests sent to `hello@eigeninteractive.com`.
Keep billing names, payment amounts and contact details private.
