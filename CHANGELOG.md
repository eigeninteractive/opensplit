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
- With "Suggest the fewest payments" off, balances show what each person owes each person they shared expenses with, each with its own Settle button.
- Somebody who left a group can come back with an invite link, to the same place they had.

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
- Lists are grouped the Material 3 Expressive way, as connected rows rather than separate cards, and icon buttons change shape as you press them.
- The sign-in code email sets its code in the app's own typeface.
- Groups are listed by their newest activity rather than when they were made.
- You need to be settled up before leaving a group, as you already did to remove somebody else.
- Groups you have left move to the archived list, read-only, and stop syncing.
- Amounts can be typed with a comma as the decimal point. Thousands separators are no longer accepted while typing.
- Exchange-rate estimates only use a rate from within a week of the expense's day, and the server keeps a full year of rates to draw on.
- Two people editing the same expense at once no longer quietly lose one edit: whichever arrives second is set aside, with the newer version shown, to be applied again on top of it.
- Saving something syncs that group alone, and all your groups are read in one request, so syncing uses far less data and battery.
- OpenSplit opens straight onto what is saved on this device, behind one launch screen, with a thin bar while it checks for changes.
- When you are offline, a cloud icon at the top of the screen says so.
- Moving between Groups, Account and Settings fades from one to the next.
- The Android launch screen shows the logo without a tile behind it.
- Text on screen is no longer selectable, as in other apps. Invite links can still be copied.

### Fixed
- Settling up with somebody and then removing them while offline no longer leaves the removal refused once you are back online.
- One group that can't be read yet, such as one created offline, no longer stops your other groups from syncing.
- A group is no longer archived as unused while people are still editing its expenses.
- A name change could occasionally never reach the people you share groups with.
- Updates the app received in the background now show on screen as soon as you return, and screens no longer redraw after every sync when nothing changed.
- A group where you're owed one currency and owe another now says both on the groups list, instead of calling it all owed to you.
- Signing in with Google on Android works again.
- A name you give while creating your first group now shows on your profile straight away.
- Reloading the web app no longer flashes "This site can't be reached" first.
- Signing out stops notifications for that account on the device.
- Changing who is being paid in Settle up now changes the UPI ID handed to your payment app too, instead of keeping the previous person's.
- An amount typed as 12,50 is no longer read as 1,250.
- A very long amount no longer breaks the Settle up screen.
- You can no longer record a payment from someone to themselves.
- Changing the email address or Google account an account signs in with now needs a recent sign-in, like deleting the account does.
- Nobody can add a new expense that charges somebody who has left a group.
- An expense split among 26 or more people now saves; before, the server refused it and the app kept retrying.
- In Settle up, making the person being paid the payer now clears "Who is being paid" on screen too, not just behind it.
- Swiping back with the date or time picker open closes the picker, not the screen behind it.
- The Account page opens with your name and UPI ID already showing, instead of filling them in a moment later.
- Syncing tries again as soon as you are back online, rather than waiting for its next turn.

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
