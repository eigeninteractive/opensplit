# OpenSplit UI and UX

Design review: 10 October 2026. The selected direction is **indigo and Google
Sans Flex**, rendered in the real Flutter expense editor alongside violet and
teal alternatives. The slashed O remains the product mark.

## Product journey

OpenSplit keeps a shared record of spending and payments. Its main decisions
are who paid, who shares the cost, and who still owes whom. The visual hierarchy
should help people verify those decisions before recording them.

| Journey | Presentation and purpose |
| --- | --- |
| Start, sign in, save a guest account | A clear primary action, ordinary filled fields, and outlined alternative identity actions. Recovery is available from Account and Settings. |
| Groups and archive | Group identity, name, and balance remain scannable. Standard FABs create groups; navigation becomes a drawer or rail as space permits. |
| Group journal | A tonal cover identifies the group. Expenses are grouped by day; amounts and payer summaries remain distinct. Expenses and balances use stock tabs, with both panels visible on wide screens. |
| Add or edit expense | Amount and currency form the headline. Description, category, and day follow. Separate payer and split cards group the two money decisions. Optional time is in a stock expansion tile. |
| People and invitations | Member avatars use the active palette by default. Membership actions, placeholders, and invite sheets retain standard lists, buttons, menus, and sheets. |
| Balances and settlement | Credit and debit use harmonised semantic colours with explanatory text. Settlement shares the expense editor's amount component, followed by payer and payee fields. Currencies remain separate. |
| Insights and activity | Existing totals, charts, and change history provide context; the same type scale and theme apply. |
| Account, group settings, and appearance | Readable lists lead to focused editors and confirmation dialogs. Appearance follows the device or a user override. Settings explains whether a device palette is available. |

## Component policy

Use `package:material_ui`, the current decoupled Material widget library already
adopted by the repository. Retain its defaults for shape, interaction, motion,
elevation, and type scale. Use the available Material 3 Expressive icon-button
variant. Further Expressive components can be adopted as that library ships
stable implementations; do not emulate their behaviour with custom controls.

- **Fields:** ordinary text fields and `DropdownMenu` share a filled decoration
  with the stock underline indicator. A dropdown has its own component theme,
  so both themes are configured together. Filled and outlined fields are both
  valid Material choices; this app chooses one consistent default.
- **Transaction headline:** `AmountCard` composes a stock filled card, text
  field, outlined currency button, and `SearchAnchor`. The amount deliberately
  keeps an always-floating **Amount** label, a currency-specific zero
  placeholder and the stock underline indicator. The placeholder does not
  prefill a value. Both expense and settlement use the same presentation and
  the existing decimal formatter.
- **Actions:** filled buttons commit or advance a main task; tonal buttons
  perform supporting actions; outlined buttons offer alternatives; text
  buttons perform low-emphasis contextual actions. FABs create primary content.
  Error colour identifies failure or a consequential destructive confirmation.
- **Selection:** choice chips select a payer; checkboxes select participants.
  Split methods use a segmented button when they fit and a stock dropdown on
  narrow screens or with large text. No custom popup or selection state logic
  is introduced.
- **Supporting details:** category and day are action chips, with Material
  sheets and pickers. The expense's optional time is disclosed progressively;
  its default timestamp and saved values keep their existing meaning.
- **Feedback:** a failed expense save appears immediately in a snackbar and
  remains explained inline. Loading, empty, offline, unsynced, and conflict
  states retain their existing flows and controls.

Contained account, sync, and conflict notices use `Card.filled` with its stock
shape, an icon, a title, supporting text, and an `OverflowBar` of Material
buttons. Failed writes use `errorContainer` and `onErrorContainer`; advice and
refresh notices use the card's surface role. The action bar stacks at narrow
widths or large text. Rectangular `MaterialBanner` is reserved for a notice
attached to the screen's top, rather than inset among cards.

Group rows use the same cover artwork as the detail header across the full
background, with the pattern softened beneath the name and standing. Opening a group shares
its cover, avatar and name through Flutter's built-in `Hero`, including the
return journey. The cover crops one fixed composition so its category icons do
not reflow during the flight. Its segmented row corners open into the header. The
expanded header groups name and standing beside the avatar; the collapsed
toolbar retains the name without duplicating its Hero.

The group picture opens into its larger editable preview. Existing expenses
share their category, description and amount with the editor. Suggested
payments share payer, recipient and amount with the settlement fields. Text
flights interpolate explicit Material styles and carry only the text, keeping
editable controls on their route. Local forms initialize synchronously when
their saved data is ready, making these endpoints available on the first frame;
deep links still wait for missing local data. Only the active navigation branch
participates, and reduced motion disables every shared flight. The existing
router, deep links, Back behaviour, page transitions, and fade-through between
top-level destinations remain in place. No second navigation stack or custom
animation controller is added.

The navigation shell and group scaffold keep the same widget ancestry across
their responsive breakpoints. This preserves the mounted navigator and app-bar
focus nodes while a route restores keyboard focus. Desktop mouse and route
resize checks exercise the transition and verify that its controls stay mounted.
The outer app group uses Flutter's built-in `WidgetOrderTraversalPolicy` to
order route scopes without measuring their transitional geometry. Each screen
keeps the standard `ReadingOrderTraversalPolicy`, so Tab follows its visual
layout. Native view-focus restoration and app-bar keyboard order are included
in the regression check.

## Colour and type

Material indigo 500, `Colors.indigo` (`#3F51B5`), generates the complete light
and dark schemes. It is a source colour, not a literal colour to scatter across
widgets. The generated light
primary is `#515B92`; the dark primary is `#BAC3FF`.

Use surface containers for grouping and depth. Use primary for key actions,
secondary containers for the amount headline, and the three accent containers
for automatic avatars. Always pair a container with its matching `on` colour.
Avoid adding arbitrary gradients, glows, or textures to the app's Material
surfaces. The static website keeps its existing composition in the same palette.

Automatic avatar colour is stable for an identity and follows the active app
scheme, including wallpaper colours. Explicit avatar hues remain personal
choices harmonised with the active scheme. **Automatic** clears a previous hue
without changing the picture. Group motifs use the cover's matching foreground
at low opacity.

Google Sans Flex uses the unchanged Material type scale, with the 400, 500, and
600 faces bundled locally. Their byte lengths and SHA-256 values were checked
against the descriptors in `google_fonts` 9.0.0. The full OFL and the fonts'
embedded copyright notice travel with the bundle. Amounts retain tabular
figures. The web engine's fallback family also uses the bundled face; runtime
font fetching remains disabled.

The website, email template, launcher, web manifest, and native/web splash
colours follow the same generated roles. See [brand generation](brand/README.md)
for the commands that keep those surfaces in step.

## Adaptive colours and Samsung

The Android plugin reads the OS's five tonal palettes, encoded as an Int32List.
OpenSplit converts those to light and dark schemes through `dynamic_color`.
The device palette is now re-read on foreground resume and system brightness
changes. A palette PlatformException no longer skips the separate system-accent
fallback; unsupported platforms retain the brand scheme. The opt-out remains
persistent. Settings previews the palette for its current brightness and offers
**Check again** when native colours are unavailable.

On the Galaxy F54, check **Samsung Settings → Wallpaper and style → Colour
palette**, then return to OpenSplit with device colours enabled in the app.
Repeat after choosing a visibly different palette. A web preview cannot test
Android's native palette. The device was not attached during this review, so
these code fixes do not establish the cause of the reported F54 behaviour.

## Validation

Automated coverage includes all four split methods, multiple payers, saved
values, optional time, decimal-comma settlement, and save-error visibility.
Responsive editor checks cover 360 × 640 at 100% and 200% text and 1280 × 900.
Theme checks cover launch resources, readable balance colours, and avatar
foreground contrast of at least 4.5:1 in light/dark and alternate palettes.
Native-channel tests cover palette conversion, absence, failures, persistent
opt-out, and a changed palette on resume.

The actual app is built with `dart run tool/build_web.dart` and served through
`cd server && pnpm dev` on the same localhost origin. This preserves the real
Worker, OPFS database, session, and headers. The committed product screenshots
are rendered by `flutter test tool/screenshots_test.dart` from repository demo
data. Browser verification and native-device limits are reported with the
change; automated tests do not replace TalkBack or physical One UI acceptance.

Recorded validation for this change:

- Flutter suite with the local Worker running: **607 passed, no skips**,
  including the real API adapter tests. A run without the Worker also passed
  with the environment-dependent tests skipped.
- Dart analyzer: **no issues**; automatic-fix dry run: **nothing to fix**.
- Production Flutter web and Android debug builds: **successful**.
- Bundled-font licensing, native/web launch consistency, and generated product
  screenshot checks: **passed**.
- Email template: **2 tests passed**; site/template formatting: **passed**.
- Live Wrangler flow: saved a ₹2,400 expense split by two people, verified the
  ₹1,200 balance and prefilled settlement, then recorded the local test payment
  and verified **All settled up**. Light/dark phone and desktop renders were
  captured under `build/ui-review/`.
- Live route exit while resizing from phone to desktop: **no new browser
  errors**, after checking the active rebuilt service-worker release.

Follow-up validation, 11 October 2026: notice actions stack and dismiss at
200% text on a 320dp phone; the group avatar flies across the nested navigator
in both directions and is disabled for reduced motion. The focused UI and
launch checks passed (65 tests), as did colour and native-palette checks
(31 tests, including repeated launch checks), screenshot rendering, and the
two email tests. Static analysis and the production web build passed. The local
Wrangler preview was checked in light/dark phone layouts and light desktop,
including opening and returning from a group, with no browser errors.

Shared-identity and input follow-up, 11 October 2026: **617 Flutter tests passed
with `REQUIRE_BACKEND=true`**, including the real local Worker API and serving
checks. First-frame expense and settlement flights, the group picture preview,
group name/cover flights in both directions, reduced motion, long names on a
320dp phone at 200% text, and tapping the unfocused amount placeholder are
covered. Static analysis found no issues; the automatic-fix dry run found
nothing to fix. The production web build and regenerated product screenshots
passed. Local Wrangler is restarted after rebuilding its replaced assets tree;
the browser's update prompt switches to the new release before visual review.
Live light/dark phone and light desktop captures are under `build/ui-review/`.

## References

- [Flutter Material design documentation](https://docs.flutter.dev/ui/design/material)
- [Current Material UI package](https://pub.dev/packages/material_ui)
- [Material colour roles](https://api.flutter.dev/flutter/material/ColorScheme-class.html)
- [Flutter's Material 3 Expressive tracking issue](https://github.com/flutter/flutter/issues/168813)
- [Google Sans Flex](https://design.google/library/google-sans-flex-font)
- [Dynamic colour plugin](https://pub.dev/packages/dynamic_color)
- [Samsung wallpaper and colour palette settings](https://www.samsung.com/ae/support/mobile-devices/how-to-customize-a-wallpaper-and-color-palette/)


## Payment editing and full-card artwork

Group list artwork fills each complete Material row. A transparency Material
above it keeps stock ink interactions visible. Pattern opacity is softened
under the text, and stock Hero animations interpolate that treatment and the
segmented outline into the full header. Colours remain generated Material
container roles; the opacity mask adds no new palette colours.

Recorded settlements keep the existing `/g/:groupId/e/:entryId` URL and open
the payment editor. It shares the amount, member menus and optional details
with Settle up, offers date, optional time and payment note, and keeps the
shared entry history. UPI handoff and outstanding-debt suggestions belong to
recording a new payment and do not appear while editing a recorded one.
Payment titles are derived from the sender and recipient. Notes and older
stored descriptions remain available without requiring a redundant name.

Local and server writes prevent changing an existing entry's kind. Settlement
composition and server writes enforce one sender and one distinct recipient,
with both sides matching the total. A malformed older payment can still be
soft-deleted on the server. These are validation changes; no database columns,
wire fields or migration are added. Existing misclassified data is not guessed
at or rewritten.

Regression checks cover unchanged payment saves, amount and note changes,
date/time preservation, date-only changes, stale edits, soft deletion and
history, shared full-row artwork, and light/dark layouts at 320px and 200% text.
At larger text sizes, the entry's balance explanation moves beneath its title
and wraps instead of overflowing the trailing amount slot.

Validation: all 625 Flutter tests passed with `REQUIRE_BACKEND=true`, and all
280 server tests passed. Static analysis, server type checking, the production
web build and regenerated Flutter product screenshots passed. The local
Wrangler preview confirmed the full-row artwork and payment editor at phone
and desktop sizes; saving the demo payment unchanged kept its payment kind
and fully settled balances. Dark-mode artwork was also rendered in the browser.

Amount and percentage splits now start with automatic values. Manual overrides
remain fixed while automatic rows divide the remainder; multiple payers use
the same calculation. Saved allocations start manual when reopened. See
[automatic split remainders](automatic-splits.md) for the interaction rules,
rounding guarantees, state design and regression scope.

The split editor keeps this behaviour quiet: default fields show only values,
custom values have a small pin action, and the section can be reset with
**Split evenly** (**Divide evenly** for payers). Repeated Auto/Manual helper
labels and instructional footers are removed. Tooltips and screen-reader hints
explain which values remain fixed without adding visual rows.

Final branch verification on 11 October 2026: all 657 Flutter tests passed
against the running local Worker, and all 280 backend tests passed. Dart
formatting and analysis, repository lint and server type checking passed.
The final web bundle and regenerated product assets were rendered through
local Wrangler, and the final Android debug APK compiled successfully.
Physical Galaxy F54 / One UI palette acceptance remains
unverified.
