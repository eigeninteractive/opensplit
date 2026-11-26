# Changelog
What changed in each version of the app, newest first. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow
[Semantic Versioning](https://semver.org/), and the file is kept by
[cider](https://pub.dev/packages/cider): see "Versions" in docs/runbook.md.

## [4.3.2] - 2026-11-26
### Added
- Prepare an Android build for F-Droid with email sign-in and no push notifications.

## [4.3.1] - 2026-11-26
### Fixed
- Animate the Add expense button as you scroll.
- Android Back closes the keyboard before leaving an expense or payment.

## [4.3.0] - 2026-11-26
### Added
- Turn on notifications in shared groups, including weekly reminders for unpaid balances.

### Changed
- Payment notifications go to the people involved. Reusable invite links show the group name.

### Fixed
- Open Android invite links during startup and refresh the preview when you open another link.

## [4.2.6] - 2026-11-25
### Changed
- Edit date and time together. Expand expense and payment sheets to full height.
- Open Account from Home. Your picture expands into its editor.
- Branded navigation with a labeled sidebar on wide screens.
- Continue with Google or email. Find the same recovery prompt on Home and Account.
- Shorter confirmations and clearer offline and cloud sync wording.

### Fixed
- Changing the split method on Android keeps the editor in place.
- Date and time icons line up. The details header stays inside its sheet.

## [4.2.5] - 2026-11-21
### Changed
- Restored the group name, picture and cover animation. Expense and payment details expand from their rows and close faster.

## [4.2.4] - 2026-11-19
### Changed
- Group cards, expenses and payments now expand into their details, with simpler transitions for editing.

### Fixed
- Add expense stays in the Expenses pane on wide screens so it leaves settlement actions accessible.

## [4.2.3] - 2026-11-19
### Fixed
- Updated the local database library for faster reads and more reliable batch updates.
- Keep group names, pictures, and covers visible when returning quickly from an expense, payment, or picture editor.

## [4.2.2] - 2026-11-19
### Fixed
- Kept web controls clear of screen cutouts and improved status bar contrast across light and dark themes.

### Security
- Updated Android certificate validation to reject compromised certificates.

## [4.2.1] - 2026-11-18
### Changed
- Updated the libraries that handle connectivity, notifications, settings and Material controls.

### Fixed
- Removed duplicate screen reader tap targets from the expense and currency search buttons.

## [4.2.0] - 2026-11-16
### Added
- Invite links preview with the group's name and who invited you, instead of the general OpenSplit card.
- Activity is grouped by day, shows who made each change, and opens the expense when you tap a line.
- Opening an expense or payment shows it to read first: what it cost you, who paid, how it was split and its history. Edit is one tap away.
- The groups list adds up what you owe and are owed across groups, and folds groups that are settled and quiet for a month under Settled groups.
- A dot marks groups with changes since you last opened them, and Activity marks what is new. This follows your account, so a group read on one device is read on the others.
- Payments on Balances have their own actions: Pay when you owe. When you are owed: Settle, Remind, which sends a notification at most once a day, or Share a ready-made message.

### Changed
- Expense rows show what each expense means for you on the right, with the full description and who paid. Recorded payments appear as a tinted row, without red or green.
- Balances lead with your own payments. Everyone's balances and payments between others are folded underneath, and names are shown in full.
- Activity and expense history name the expense or payment they are about, with real category names, amounts and dates.
- Insights is rebuilt: switch between the group's spending and your own share, pick a period, and tap a category or a bar to see the expenses behind it. It also shows who paid and who spent, and the biggest expenses.
- The expense form is shorter. Paid by and Split fold to a one-line summary until you need them.
- Insights no longer has its own search; use search in the group toolbar. Exporting saves all of the group's expenses.
- Your own row reads "You" throughout. The Add expense button shrinks to its icon as you scroll down and returns as you scroll up.

### Fixed
- Removing someone who is not settled up explains why and offers to settle. Group settings rows line up.

## [4.1.0] - 2026-10-16
### Added
- Search expenses and recorded payments from the group toolbar, across currencies, using descriptions and notes saved on this device.

### Changed
- Groups use connected rows with clearer, softer Material surfaces and more visible artwork in light mode. Neutral cards share the same surface treatment, and expense sections use outlined cards.

### Fixed
- Expense and payment editors ask before discarding changes. The whole export settings row opens the format picker, which remains scrollable with large text.
- Clearing Insights search or filters also clears the visible search text, and restored searches display their saved query.

## [4.0.0] - 2026-10-15
### Changed
- When a numbered API version is retired, saved data stays readable and pending uploads pause. Update OpenSplit through Play or restart into the new web release to edit again.
- This testing release opens a fresh local ledger and requires signing in again. Old device databases remain unused; older builds can no longer change server data.
- The archive option has been removed. Leaving a group ends access on all devices.
- The last account holder can leave a fully settled group, permanently deleting it. Groups with active account holders are retained without an inactivity deadline.
- Groups have larger names and avatars with quieter cover art. Forms use consistent filled fields, and app wording is shorter.

### Fixed
- Departed members cannot open group screens or edit cached data. Confirmed access loss clears the local cache without a retry loop. Stale group and member edits cannot overwrite newer versions.
- Store screenshots and the feature graphic are refreshed together, with CI detecting stale artwork.
- Improved browser database transaction reliability.

### Security
- Updated sign-in protections.

## [3.1.0] - 2026-10-11
### Added
- Amount and percentage splits, and multiple payers, start evenly and share the remainder as you edit. Saved splits keep their values.

### Changed
- A refreshed Material design with indigo colours, Google Sans Flex, consistent fields and clearer expense entry.
- Groups share their cover art and name as they open, with transitions that respect reduced motion.
- Recorded payments open in a dedicated editor showing who paid whom, with an optional note.
- Custom split values have a small pin and an even-split reset.
- The launch screen, landing page, emails and Play artwork match the new design.

### Fixed
- Android device colours refresh when you return to the app or switch light and dark mode. Settings can check colour availability again.
- A saved payment keeps its sender, recipient and payment type while editing.
- Expense previews and saved splits assign leftover cents to the same people.

## [3.0.0] - 2026-10-10
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
- Earlier versions of OpenSplit can no longer sync. Update to this one to keep your groups syncing.

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

[4.3.2]: https://github.com/eigeninteractive/opensplit/compare/v4.3.1...v4.3.2
[4.3.1]: https://github.com/eigeninteractive/opensplit/compare/v4.3.0...v4.3.1
[4.3.0]: https://github.com/eigeninteractive/opensplit/compare/v4.2.6...v4.3.0
[4.2.6]: https://github.com/eigeninteractive/opensplit/compare/v4.2.5...v4.2.6
[4.2.5]: https://github.com/eigeninteractive/opensplit/compare/v4.2.4...v4.2.5
[4.2.4]: https://github.com/eigeninteractive/opensplit/compare/v4.2.3...v4.2.4
[4.2.3]: https://github.com/eigeninteractive/opensplit/compare/v4.2.2...v4.2.3
[4.2.2]: https://github.com/eigeninteractive/opensplit/compare/v4.2.1...v4.2.2
[4.2.1]: https://github.com/eigeninteractive/opensplit/compare/v4.2.0...v4.2.1
[4.2.0]: https://github.com/eigeninteractive/opensplit/compare/v4.1.0...v4.2.0
[4.1.0]: https://github.com/eigeninteractive/opensplit/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/eigeninteractive/opensplit/compare/v3.1.0...v4.0.0
[3.1.0]: https://github.com/eigeninteractive/opensplit/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/eigeninteractive/opensplit/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/eigeninteractive/opensplit/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/eigeninteractive/opensplit/releases/tag/v1.0.0
