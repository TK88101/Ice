# Ice on macOS 27 -- what this fork does and does not do

**In one line: on macOS 27 this fork can *see* the menu bar but cannot *hide*
anything.** It lists your items and sorts them into sections. Hiding a section
has no effect, and the fork detects and reports that.

Every row is tagged. **MEASURED** means it was observed on the build and date
given, on one machine: macOS 27.0 (26A428), Apple Silicon, one 1728 x 1117
built-in display, the owner's own menu bar items. **INFERRED** means it was read
from the code or reasoned from measurements, and was not observed. No row is a
general guarantee: other machines, displays, item sets and macOS builds are
untested. The evidence and its limits are in [FINDINGS.md](FINDINGS.md).

## What works

| what | status | tag |
|---|---|---|
| Launch no longer sticks at "Loading menu bar items..." | setup finished 1.1 s after start; the text appeared in none of three search panels and none of two layout panes | MEASURED, Ice `2e0c553`, 2026-09-25 |
| Items are found through Accessibility | the search panel's names and right-to-left order matched the bar | MEASURED, Ice `2e0c553`, 2026-09-25 |
| Discovery keeps up | 41 passes in five minutes; 40 `complete` (median 36.5 ms); only the cold launch pass was `incomplete` | MEASURED, Ice `28b89c2`, 2026-09-25 19:18 |
| Sections follow Ice's dividers | after a divider had been collapsed for at least 1 s: Visible 6 / Hidden 5, matching the items' positions, over two show/hide cycles | MEASURED, Ice `2e0c553`, 2026-09-25 |
| Your items survive a collapse, an expand and Ice quitting | 9 collapses: no `«` chevron, no item lost, items moved by 1 pt or less; after quitting, all 10 items were back in the same order | MEASURED, Ice `2e0c553`, 2026-09-25 |
| Permissions | all checks passed and no prompt appeared | MEASURED, Ice `2e0c553`, 2026-09-25 |

## What does not work

| what | status | tag |
|---|---|---|
| **Hiding** | an expanded hidden divider hides nothing: in 10 of 10 checks the item was still drawn | MEASURED, Ice `2e0c553`, 2026-09-25 |
| The hiding check tells you so | the layout settings showed `Hiding did not take effect for 5 item(s)` | MEASURED, Ice `2e0c553`, 2026-09-25 |
| The check after a collapse of under 1 s | `Not checked: noBaseline` | MEASURED, Ice `2e0c553`, 2026-09-25 |
| The check in IceBar mode | `Not checked: iceBarMode`: no click collapses a divider there, so nothing is sectioned or checked | INFERRED (code) |
| Item images in the search panel | blank grey placeholders | MEASURED, Ice `2e0c553`, 2026-09-25 |
| Moving, clicking or temporarily showing an item | refused and logged; a click in the search panel does nothing | INFERRED (code) |
| Apple's own items (the clock, Control Centre) and apps that refuse Accessibility | not listed | INFERRED (code) |
| Before a divider has first been collapsed for 1 s after launch | every item is listed under Visible | INFERRED (code) |
| Ice's menu bar item service (XPC) | fails to start within 45 ms, and setup, which waits for it, then goes on. That build was ad-hoc signed with no team, while the service only accepts a peer from the same team; a signed release was not run on 27 | MEASURED, Ice `2e0c553`, 2026-09-25; the signing cause INFERRED |

## Why hiding does not work, and what is next

Ice hides items by widening its own status item so that the items to its left
are pushed off the bar. On macOS 27, at the width Ice uses (10 000 pt) the
widened item gives the room back and nothing is hidden. At the narrower widths
that do push an item out, the item lands in the system's overflow, which shows a
`«` chevron. Both were MEASURED on test helpers on 2026-09-18; that the same
holds for Ice's own item is INFERRED. The owner has stopped the push-out
approach.
The hiding study (`docs/plans/2026-09-25-hiding-feasibility.md`) tested a
different mechanism: a spacer of a chosen length. Results, on this machine:

| what | status | tag |
|---|---|---|
| A spacer hides one item without `«` | at 616-840 pt every 16 pt step hid the helper; 5/5 at 728 pt | MEASURED, 2026-09-28, owner's bar |
| Ice can verify that with a long frontmost menu | no: menus right of the notch make the check unreadable, so the item cannot be reported hidden | MEASURED, 2026-09-29, isolated account |

The study required verification in every layout, so its outcome is NO-GO
(owner accepted, 2026-09-30). The next study, route C, aims at IceBar with a
narrower scope: items hidden and shown in Ice's panel while the frontmost menu
ends left of the notch, shown on the bar otherwise
(`docs/plans/2026-09-30-icebar-route-c.md`). If it ends NO-GO, this fork will
state that macOS 27 support is read-only.

Route C's first sitting (S0 -> S-adv -> S1, isolated account, run
`20261003-134859-icebar`, macOS 27.0.1 26A434, 2026-10-03):

| what | status | tag |
|---|---|---|
| Sitting result | `結果：失敗｜S0 not shown: a cycle inconclusive three times`; ended after S0 (1 min 55 s); S-adv and S1 not run | MEASURED, run `20261003-134859-icebar`, 2026-10-03 |
| Why S0 was not shown | all 130 captures inconclusive: the window server listed no single status window for the visible helper `reference` (`OverlapGuard`: `missing("reference")`), so every control failed and three cycles at 728 pt were inconclusive. No claim was granted (no NO-GO) | MEASURED, same run |
| C3 (window-server bounds usable) | does not hold: `notListed(reference)` (the first helper unlisted; the runner records no per-helper list) | MEASURED, same run |
| Section 8 numbers | unmeasured: every S0 baseline refused at the frozen fold (`unreadable`), as risk K1 expected | MEASURED, same run |
| `«` (b) control, S1 capacity | not reached | -- |
| Replication of that S0 failure | not run | -- |
| Can this instrument certify route C on macOS 27 | no: C3 needs a window per helper, and macOS 27 lists none (0 bar-shaped windows); without C3 the oracle misses an overlapped member in 16,874 of 160,740 synthetic overlap cases (10.5 %). Route C's continuation is the owner's decision | MEASURED, 26A434 window list and an offline sweep, 2026-10-03 |

Not verifiable on this machine: macOS 14 to 26 (the machine runs 27 only).

## IceBar spikes (T0, 2026-10-04)

| what | status | tag |
|---|---|---|
| A spacer hides 1 to 8 helper items without `«` | one band, 632-840 pt, for k = 1, 2, 4, 8 under short and mid frontmost menus; isolated account, helpers only | MEASURED, 26A434, run `20261004-105226-spike` |
| AXPress opens a pushed-off item's menu | 5 of 5 within 15 ms at 736 pt; no need to show the item first | MEASURED, 26A434, run `20261004-105226-spike` |

## IceBar built, not yet run (T4-T6, 2026-10-04)

| what | status | tag |
|---|---|---|
| IceBar mode hides the hidden section at a calibrated length | wired: the hidden divider walks T0's band from rest and rests at its middle, only when every hidden item was seen gone with no `«`; any doubt, a long frontmost menu or a layout change puts the items back on the bar, and the layout pane says why | INFERRED (code and unit tests), not run on a bar |
| IceBar cells | the owning app's icon, desaturated; else the item's title, else a generic glyph | INFERRED (code), not seen |
| Clicking an IceBar cell | presses the item over Accessibility where it is; a press that fails dims the cell ("Cannot open on macOS 27"); right click does nothing | INFERRED (code), not run |
| macOS 26 and IceBar mode off on 27 | unchanged | INFERRED (diff review) |
| The first run of all this on a bar (T7) | prepared, not run: `stage-t7.sh` staged the build and helpers for the isolated account, `run-t7.sh` is the one command (dry check passed) | MEASURED (staging and dry check), 26A434, 2026-10-05 |
