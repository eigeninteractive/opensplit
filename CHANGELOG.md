# Changelog
What changed in each version of the app, newest first. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow
[Semantic Versioning](https://semver.org/), and the file is kept by
[cider](https://pub.dev/packages/cider): see "Versions" in docs/runbook.md.

## [Unreleased]
### Added
- On the web, notifications now arrive when OpenSplit isn't open, and tapping one opens the group.
- On the web, OpenSplit tells you when an update is ready, and restarts into it when you choose.
- Groups and people have pictures: initials, an emoji or an icon, on a colour you choose. Tap a picture to change it.
- Each group has a cover drawn from what it spends on, so a trip fills with flights and dinners and a flat with bills.

### Changed
- Sign-in code emails have a new look to match the app.
- Empty screens show their picture above the words rather than behind them.
- The Account page shows your profile, and editing it, or saving a guest account, opens its own screen.
- The amount is the biggest thing on the expense screen, with the currency beside it and Save at the top. Category, day and time are chips.
- A group opens on where you stand in it, with its expenses grouped by day and each one shown by its category.
- Balances lead with the payments you are part of, and every person has their picture.
- Insights open on the total spent.
- Renaming a group happens in a dialog rather than a field that is always open.
- Amounts use the app's own typeface, with figures that line up.

### Fixed
- A group where you're owed one currency and owe another now says both on the groups list, instead of calling it all owed to you.
- Signing in with Google on Android works again.
- A name you give while creating your first group now shows on your profile straight away.
- Reloading the web app no longer flashes "This site can't be reached" first.
- Signing out stops notifications for that account on the device.

## [2.0.0] - 2026-10-01
### Changed
- OpenSplit has moved to opensplit.eigeninteractive.com, and links to the old opensplit.web.app addresses take you there.
- A new server. Groups and accounts from earlier test builds do not carry over: sign in again, and start your groups afresh.

### Fixed
- About shows the build number on the web too, the same one as on Android.

## [1.0.0] - 2026-08-27
### Added
- The first build, to Play internal testing.

[Unreleased]: https://github.com/eigeninteractive/opensplit/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/eigeninteractive/opensplit/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/eigeninteractive/opensplit/releases/tag/v1.0.0
