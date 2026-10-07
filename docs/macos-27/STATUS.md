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
| The first run of all this on a bar (T7) | first attempt `20261007-012252-t7` did not hide at all: Ice reported `shown(menuUnreadable)` within 1 s and never `active` (plan 2026-10-07-icebar-menu-frame-fix). Fixed. Second and third attempts (`20261007-160812-t7`, `20261007-182404-t7`): the menu frame was read, the baseline failed for want of a reference (T7 launched no visible helper). The runner now starts two reference helpers, checks Ice's own reference rule on the live bar, and runs phases 1-3 to `active` unattended before any question; restaged, not run again yet | MEASURED (the failed run's log; staging and dry check), 26A434, 2026-10-07 |
| Where the work stands (2026-10-07, evening) | T7 is frozen after seven owner sittings that never reached `active`. The goal was restated by the owner (preference hiding; `«` is not the problem) and the work re-planned with Codex: `docs/plans/2026-10-07-icebar-preference-hiding.md` (converged, not implemented). Open defect: with a never-seen bundle id Ice's icon still lands left of its divider (run `20261007-213730-t7`); cause unknown until the plan's S1 trace | MEASURED (the runs), 26A434 |
| A fresh Ice on 27 put its icon left of its hidden divider | upstream seeds the icon's preferred position with 0, which 27 reads as none (leftmost); with no visible section nothing could be a reference. Now seeded 0.1 on 27 (a stored 0 is re-seeded) | MEASURED (runs `20261007-201416-t7`, `-201704-t7`; probe and rehearsal with sacrificial helpers in the owner's account), 26A434, 2026-10-07; the fix on a bar with Ice itself: not run yet |
| macOS 27 remembers where status items were dragged | MenuBarAgent's `TrailingItemPreferredPositions` (group container `com.apple.MenuBar`), keyed by bundle id and autosave name; a remembered position overrides the app's own preferred position. A user whose record has Ice's icon left of its divider stays that way despite the seed: Ice does not detect or repair this yet | MEASURED (the store, owner's account; run `20261007-211145-t7` landing on the dragged coordinates), INFERRED (that the record is what overrode the seed), 26A434, 2026-10-07 |
| IceBar hiding needs a reference | at least one identifiable third-party item between Ice's hidden divider and its icon (the visible section); a bar with system items only gets `cannotAssess` and nothing is hidden | MEASURED (run `20261007-182404-t7`: `skip(noReference)`; `CheckPlan.swift:47-80`), 26A434, 2026-10-07 |
| The application menu's frame on 27 | upstream's hit test at the display origin returns a `MenuBarAgent` `AXWindow`, so the frame was always nil; now read from the menu bar owner's own `AXMenuBar` (27 only) | MEASURED (read-only probe 3/3, `icewatch menu-frame` live), 26A434, 2026-10-07 |
| Upstream features that read that frame on 27 (hide app menus, temporary show, show on click in empty bar space, overlay) | now get a frame where they got nil; in IceBar mode only the click path is reached (T7 row 1b) | INFERRED (code), not run |

## Ice's trace mode (T1, 2026-10-07, plan 2026-10-07-icebar-preference-hiding S1)

| what | status | tag |
|---|---|---|
| Trace mode | `-IceLabTrace YES` under a `com.icespike4.` identity: Ice creates its control items by its own code path in IceBar mode with uncalibrated dividers, logs the three status-item defaults at five points and the frames, and quits; refused under any other identity; inert without the argument | MEASURED (6 runs) / unit-tested (`LabTraceRule`) |
| P2 in the owner's account | not reproduced: 6 of 6 runs from a never-seen identity (3 with the always-hidden section off, 3 on) put the hidden divider at x 1492 and Ice's icon at 1508, icon right of divider; the seeds (icon 0.1, hidden 1) held at all five points; the always-hidden divider (no seed) landed at 1009, left of everything | MEASURED, 26A434, run `20261007-225415-trace`; the same in 12 more runs after review (`20261007-230408-LzSmZE-trace`, `20261007-231100-cM6U06-trace`, the latter with the start handshake, completeness check and settled store guard) |
| Fresh Ice's layout here | divider and icon both right of every other item: everything else would be left of the divider, so a hidden-section member (section 5, "S2, added" aims at divider, then the others, then the icon) | MEASURED, same run |
| MenuBarAgent's store | no entry recorded for any lab identity, no other entry changed (before/after guard, all 6 runs) | MEASURED, same run; read from the store via `defaults export` after a 2 s wait |
| Why P2 differed in `icetest` | unknown; the same trace becomes the lab's first scenario (S4) | TBD |

## Where a fresh Ice puts its items (T2a, 2026-10-08, plan 2026-10-07-icebar-preference-hiding, S2 design)

| what | status | tag |
|---|---|---|
| The hidden divider's seed on 27 | none any more (it was 1): the divider lands leftmost, the icon (0.1) rightmost of the status items. A stored value is never replaced. macOS 26 and earlier: unchanged | unit-tested (`ControlItemPositionSeed`) |
| Fresh Ice's layout here | hidden divider at x 1033, Ice's icon at x 1517, all ten other on-bar status items between them, none left of the divider; with the always-hidden section on, its divider at x 1017, left of the hidden one; as many items on the bar as before Ice's items were added (10); 3 of 3 with the section off and 3 of 3 with it on, two agreeing discovery passes each | MEASURED, 26A434, run `20261008-004241-1qFWAA-trace` (the build as reviewed; the same frames and counts in `20261008-001401-OIpSef-trace` before the review), owner's account, never-seen identities |
| The run before it | failed the oracle 6 of 6 on its own wording: it counted three parked items (frames at the screen's bottom left, not on the bar) as left of the divider. The count was corrected to on-bar items (what the membership rule can select) and re-reviewed by Codex; the failed run was not reused | MEASURED, run `20261008-001005-7X98U1-trace` |
| A run between the two | failed 6 of 6 with the layout unchanged: its one baseline pass, the trace process's first, was incomplete. The baseline is now read up to twice until complete (it took two attempts in all six runs of the final run); an incomplete baseline still fails | MEASURED, run `20261008-004012-dze20T-trace` |
| An identity that already stored the old seeds | keeps the old layout (divider and icon right of everything, every other item a hidden-section member): the stored divider value stays. The repair is a Command-drag of the divider | INFERRED (code), not run |
| An app installed later | its new item lands leftmost too, so left of the divider: a hidden-section member until the owner moves it | INFERRED (from the unseeded dividers' landing), not run |
| A crowded bar | the leftmost slot may be overflowed or under the notch; Ice would then read its divider as unusable. Here the bar had room | not measured |
| Other accounts, displays, item sets | not measured; `icetest`'s different layout (P2) is still unexplained | TBD |
