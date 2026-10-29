## Changes

Describe the resulting behavior and relevant validation.

## Production release

Every merge to `main` submits a production release, including maintenance PRs.

- [ ] Updated from the latest `main` and selected the appropriate patch, minor,
      or major version with `dart run cider bump`.
- [ ] Added release notes with `dart run cider log` and finalized them with
      `dart run cider release`.
- [ ] Ran `dart run tool/check_release.dart --base-ref=origin/main`.
- [ ] Regenerated artwork provenance with `dart run tool/store_artifacts.dart`
      after the version bump.
- [ ] Checked that server/schema changes remain compatible with installed clients.
