# Automatic split remainders

## Behaviour

New amount and percentage splits start evenly across selected participants.
Typing a value fixes only that person's value. The unedited rows divide the
remainder evenly. The same rule applies to selected people who paid when
several people paid. Share counts remain ratios, initially one each.

The default fields show just their values. Custom values have a small pin
button; its tooltip describes the action, **Let [name]'s value adjust**.
Tapping the pin or clearing the value lets that person share the remainder
again. **Split evenly** resets the selected participants, and **Divide evenly**
does the same for multiple payers. These actions appear only when the section
has custom values. There are no repeated Auto/Manual labels or instructional
footers. Screen-reader hints still distinguish fixed values from ones that
follow the remainder; validation errors remain visible and announced.

While typing, the field keeps the raw text and caret; a cleared field shows
its computed value when focus leaves. Focusing a value does not fix it.

Amounts use integer currency minor units. Automatic percentages retain the
model's six-decimal precision so rounding percentages does not skew an
otherwise equal money split. Largest-remainder allocation distributes
indivisible units in a stable order. A new expense generates its UUID locally
when the draft opens, so the preview and saved allocation use the same rounding
seed. This allocates an identifier in memory; it does not create an expense,
insert a placeholder row, enqueue a sync operation, or reserve anything on the
server. Cancel discards the unsaved draft. Save supplies that UUID to the normal
repository transaction, which writes the complete entry, history and outbox
item together. The server already accepts client-generated entry identifiers.

Manual values never change to force a balance. If they exceed the total, if
every row is manual and a remainder is left, or if an input cannot be parsed,
the editor explains the problem and refuses saving. A selected payer must pay
more than zero; a participant may owe zero.

Changing the total, currency, or selection recalculates automatic rows.
Currency changes reinterpret the raw typed amounts with the chosen currency's
precision; invalid manual values must be corrected explicitly. Deselected
rows do not contribute, but retain their overrides if selected again. Switching
methods retains each method's own overrides rather than translating unrelated
weights into amounts or percentages.

When reopening an expense, all saved values of its active amount/percentage
method, and saved values for multiple payers, start manual. This preserves the
agreed allocation. The user can release individual overrides or reset that
section to automatic. No automatic/manual metadata is persisted: it describes
the editing session, not the recorded transaction.

## Structure

`RemainderAllocation` is a pure integer calculation shared by money,
percentages and payers. Form state stores selections and raw manual overrides;
automatic values are derived. The same derivation drives fields, previews,
validation and the saved draft. The domain's existing split and payer
validators remain the final write boundary. No API or database migration is
required.

Material text fields, checkboxes and icon/text buttons provide interactions.
The field adapter owns only Flutter's text controller and focus lifecycle; it
does not own financial values or implement another input widget.

## Verification

Cover fixed-value preservation, exact conservation, stable rounding, all
manual and no-member cases, zero and invalid inputs, selection/method/total/
currency changes, reopening, multiple payers, and preview/save equivalence.
Exercise typing and clearing while focused, reset actions, field refresh after
external form changes, and narrow layouts with large text in widget tests.
Regenerate product screenshots and their promotional derivatives after the
visible UI changes, then build and render through local Wrangler.

Validated on 11 October 2026:

- All 657 Flutter tests passed with `REQUIRE_BACKEND=true` against the local
  Worker, including domain, form, repository and widget regressions.
- Static analysis reported no issues; the production web build succeeded.
- Actual Flutter renders and the regenerated store/landing assets were checked.
- At a 390 × 844 browser viewport, amount and multiple-payer overrides of ₹120
  left ₹180 for the other automatic row on a ₹300 expense. Reset restored
  ₹150 each. A 40% override produced 60% and matching ₹120/₹180 previews.

After simplifying the controls, all 53 targeted domain, form and widget tests
passed, including screen-reader hints, individual pins, section resets and
narrow layouts. Static analysis remained clean and the fix dry run found
nothing to fix. Flutter screenshots, promotional derivatives and the
production web bundle were regenerated. The rebuilt local Wrangler preview
confirmed ₹120/₹180 and the pin restoring ₹150 each without status helper rows.

The live demo draft was left unsaved. Browser rendering and automated tests
cover this change; it has not been verified on a physical Android device.
