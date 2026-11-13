# Ice on macOS 27 -- what this fork does and does not do

**In one line: on macOS 27 this fork can *see* the menu bar, and hides the items
you choose behind the IceBar in the lab, not yet on your own bar.** It lists your
items and sorts them into sections. The lab (`icetest`, sacrificial helpers)
measured `IceBar hiding: verified` round after round since 2026-10-11; the owner's
own bar is S5's (plan 2026-10-07-icebar-preference-hiding). The rows below the lab
sections are older and say what each measured then.

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
| macOS 27 remembers where status items were dragged | MenuBarAgent's `TrailingItemPreferredPositions` (group container `com.apple.MenuBar`), keyed `status:<owner>::<autosave name>`, where the owner is the bundle id for the signed apps seen and the process name for our ad-hoc helpers ("Remembered positions" below; the rule that picks one is unknown); a remembered position overrides the app's own preferred position. A user whose record has Ice's icon left of its divider stays that way despite the seed: Ice does not detect or repair this yet | MEASURED (the store, owner's account; run `20261007-211145-t7` landing on the dragged coordinates), INFERRED (that the record is what overrode the seed), 26A434, 2026-10-07 |
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

## Remembered positions (T2b, 2026-10-08, plan 2026-10-07-icebar-preference-hiding S2 design)

One live run, stopped by its own store guard at the first run's 30 s read; no drag
was posted. T2b did not complete its three-run protocol.

| what | status | tag |
|---|---|---|
| Does MenuBarAgent record an item nobody dragged (Q1) | yes: no entry about 4 s after launch, an entry for each of the two helper items by the 30 s read (588.5 and 616.5, one 28 pt item apart). When exactly between the two reads: not measured | MEASURED, 1 run, 26A434, run `20261008-081444-y8GnWW-remembered`, owner's account |
| How the entries are keyed | the helpers' are `status:vzhelper::<autosave name>`: the process name, not the bundle id (`com.icespike4.target` / `.protected`, ad-hoc signed). In the store, 34 `status:` keys carry a plain name (all of them our ad-hoc helpers of this and earlier dates) and 25 a bundle id (Team-signed apps, the release Ice among them: `status:com.jordanbaird.Ice::...`) | MEASURED (the keys). What makes MenuBarAgent choose one or the other: unknown |
| What this means for lab copies of Ice | an ad-hoc built Ice staged under a fresh bundle id may be keyed `status:Ice::...` whatever its bundle id, so successive lab runs that live long enough to be recorded might not start from a clean record. No `status:Ice::` key exists; the trace runs (about 6 s each) recorded nothing. Open for the lab matrix (S4). "A fresh bundle id is a fresh identity for MenuBarAgent" is withdrawn | INFERRED, not run |
| **The owner's own entries changed while the helpers were up** | in the same interval (4 s to 30 s) 15 existing entries that are not ours changed value (system modules and third-party items, by -28 to +46 pt, many by -8.5); no key was added or removed besides the helpers' two; nothing changed again in the minutes after the helpers quit. Whether MenuBarAgent rewrote them because our items appeared, whether the new values are just those items' current places, and whether anything visible or lasting follows: unknown. The store as it was: `~/IceReverse-evidence/20261008-081444-y8GnWW-remembered/store-before.plist`. No further run without the owner's approval | MEASURED (the change), cause and effect unknown |
| The earlier trace runs' guard | allowed entries under the lab bundle id only; if an ad-hoc Ice is keyed by process name that allowed nothing, so it acted as "any change to the store fails". The six runs passed it: the store did not change. Their layout results stand | MEASURED (the runs), INFERRED (the keying) |
| After a Command-drag: the entry, the app's own default (Q2); back in the slot after a relaunch (Q3); against a contradicting seed (Q4) | not measured: the guard stops the run when MenuBarAgent records, before the drag. Whether a dragged position persists is still the 2026-10-07 row's INFERRED | not measured |
| The drag itself | `probes/dragown.swift` has never posted an event; its rules pass their self-test and its read mode found the two helper items adjacent, T left of P, the press and drop points on them (3 of 3 reads without injection) | MEASURED (reads only) |

## Ice's icon left of its divider (T2c, 2026-10-08, plan 2026-10-07-icebar-preference-hiding S2 design)

| what | status | tag |
|---|---|---|
| The rule | on macOS 27 in IceBar mode, with no drag under way, an icon read on the bar with its middle not right of the hidden divider's left edge gives the notice: "Ice's icon is left of its hidden-section divider, so Ice hides nothing. Hold Command and drag Ice's icon to the right of the divider." An icon or divider Ice could not read gives none. The text promises nothing about the drag lasting (not measured: "Remembered positions") | MEASURED (unit tests, `IcePlacementNoticeTests`) |
| The gate | the hiding machine puts the section back (standard length) and reports that line from every phase, resting included, before any other reason; when the icon is right of the divider again it waits out the quiet period and hides again. Since T3b: precondition a of `blocked`, below | MEASURED (unit tests, every phase, `IceBarHidingMachineTests`) |
| Which reading counts | only a discovery pass whose hidden boundary is trusted (the divider at standard length, settled) updates where Ice holds its icon to be: a divider at a hiding length does not draw the boundary at its left edge, so such a pass neither clears nor invents an inversion | MEASURED (unit tests of the rule); that a hiding divider reads that way: INFERRED (layout direction), not measured |
| In the app | the layout pane shows the line above the bars (once: not repeated beside the same hiding status line); the item manager publishes the placement, the hiding coordinator feeds it to the machine | builds (Debug); **not run live**: no full Ice was started. INFERRED (code and unit tests) until the lab matrix's scenario 14 (S4) |
| An inversion on real frames | not seen: the trace's `inv` variant wrote the icon's stored position as 5000 before launch, 3 of 3 runs complete with the store guard passing, and the icon landed at x 1013, directly right of the hidden divider (x 997), the eleven other items all right of the icon. A stored position alone did not put the icon left of the divider here | MEASURED, 26A434, runs `20261008-092213-WTCPNh-trace` and `20261008-092507-liCEDD-trace`, owner's account |
| Fresh Ice's layout, again | hidden divider, the eleven other on-bar items, icon: 3 of 3 with the always-hidden section off and 3 of 3 on, in both runs | MEASURED, the same two runs |
| Not covered | an icon that gets left of the divider without a Command-drag while the section is hidden (it would be carried off the bar and read as unreadable, not inverted); an icon hidden by the "show Ice icon" setting (unreadable: no block) -- both for T3b's `blocked` state. Since T3b both block, below | built (T3b) |

## Preference hiding wired in (T3b, 2026-10-08, 26A434, plan 2026-10-07-icebar-preference-hiding S3 design)

| what | status | tag |
|---|---|---|
| Who is hidden | the roster: everything left of the hidden divider, as T3a's rule resolves it on every completed discovery pass, advancing only while the divider is at standard length; the IceBar lists it, for either section, a stale or unaddressable member's cell disabled before any press. A member whose process has exited (`kill` says no such process) is dropped; one that is unread, quarantined or failing stays, stale | MEASURED (unit tests: `PreferenceHidingMembershipTests`, `PressTargetRuleTests`, `MenuBarDiscovererTests`); in the app INFERRED |
| When Ice changes nothing | `blocked`: Ice's icon left of its divider, not on the bar (also with Show Ice icon off: on macOS 27 IceBar hiding needs the icon on the bar), or the divider unusable at standard length; a discovery pass that is not complete, permission denied included; a positional item left of the divider, named with its repair. From every phase the length is retired before the pane says so | MEASURED (unit tests, every phase) |
| Hiding without proof | a baseline that does not cover the members, or a walk that finds no length where every ready member is absent, still applies a length -- the last verified one, else the middle of what the walk saw absent, else 736 pt (T0's first probe, not a measured fit for this bar) -- and the pane says "hiding requested, not verified" with the first reason. Never a lab success | MEASURED (unit tests); that 736 pt hides anything on another bar: INFERRED |
| What no longer shows the section | a frontmost-app, menu-width or Space change: the length stays, the pane says not verified, one re-check after the quiet period. A `«`: read with every observation, logged, acted on by nothing. A baseline older than ten minutes: the re-check says not verified, "the last check is more than ten minutes old"; Ice does not put the items back to re-baseline (the owner confirmed, 2026-10-08) | MEASURED (unit tests) |
| What still does | an item or display change (the roster may be wrong), a Command-drag, a failed precondition, leaving IceBar mode; a member seen drawn at a re-check starts a new cycle, at most three times per roster and display, then the pane says the item is still drawn | MEASURED (unit tests) |
| Turning IceBar mode off | empties the roster and the failed presses at once; a press still under way then changes nothing when it returns, and a baseline that returns after a newer one cannot replace it | builds (Debug); not run live |
| The pane's lines and the log | one line per state; the log line `IceBar hiding: <summary>` carries case names and counts only, pinned by `IceBarHidingStatusTests` for S4's runner. T7's report (`t7-lib.zsh`) cannot read it: T7 is superseded | MEASURED (unit tests) |
| In the app | builds (Debug); **not run live**: no full Ice was started in this account (R1). Everything in this section beyond the unit tests is INFERRED until the lab matrix (S4) | not run |
| Ice's own start, again (regression) | trace mode with T3b's build: always-hidden off 3 of 3; **on 0 of 3**: both dividers read at the same frame (x 981, w 18), so T2a's clause "always-hidden divider left of the hidden one" fails; `inv` 2 of 3 (the third's two passes disagreed: indeterminate). Control with the build before T3b (`226d84e`), one run each: off pass, **on fails the same way, same frames**, inv pass. So the failure is not T3b's: this bar no longer gives the two unseeded dividers distinct places, which T2a's 6 of 6 at 09:22-09:25 had shown. An open defect of T2a's placement: T2d, not blocking T4; S4 scenario 7 runs both variants (plan, T2a exception) | MEASURED, 26A434, runs `20261008-100625-RDzm4C-trace` (T3b) and `20261008-100830-3EZ9B3-trace` (control), owner's account |
| Not measured | how often a pass is incomplete on a real bar, each time retiring the length for at least the quiet period; where Ice's own divider reads at a hiding length (a helper spacer at 634 pt read at x 1229, inside the bar, the item it pushed off kept its frame: T0, `20261004-105226-spike`) | not measured |

## The lab matrix, built, not run (T4, 2026-10-08, plan 2026-10-07-icebar-preference-hiding S4 design)

| what | status | tag |
|---|---|---|
| Ice's lab report mode | `-IceLabReport YES` under a `com.icespike4.lab.` identity: a normal launch that also writes its status, each length, each roster change and a snapshot (roster, cells, cache, control items, checks) as numbered JSON lines, and takes `bar open`, `bar close`, `press <namespace> <identifier>` (the calls a click makes, under the click's own guards); `-IceLabHoldLength YES` withholds every length (scenario 11's fault). Inert without the argument, refused under any other identity | MEASURED (unit tests: `LabReportRuleTests`, `LabReportTests`); builds (Debug); **not run**: no full Ice was started in this account (R1) |
| The runner and its judge | `run-lab.sh` runs the 19 scenarios (plus scenario 14's second half listed as not run, the owner's decision) up to three rounds, each with a fresh Ice copy, judged from Ice's own report by `lab-tool.py` | MEASURED (the judge's unit tests, 30; the runner against stubs, 21 checks; Codex code review converged); against a real Ice and bar: **not run** |
| A renamed Ice copy starts | 9 of 9 trace runs with the executable renamed | MEASURED, 26A434, run `20261008-141922-GTxPkE-trace`, owner's account |
| How MenuBarAgent keys an ad-hoc Ice | still unknown; the runner records the store before and after every scenario and says which key form appeared | TBD until the first sitting |
| What only the first sitting can tell | placement by launch order in `icetest`; whether Ice reaches a rest there; that a held length reads as drawn; that the pre-seed inverts the icon; that the crowding ladder reaches "members folded, divider on the bar"; that a stall makes a pass incomplete; how long a round takes (estimated one hour, not measured) | INFERRED |

## The lab matrix's first run (2026-10-08 23:47, `icetest`, run `20261008-234718`, build `1a33df4`)

| what | status | tag |
|---|---|---|
| Ice applies a length and rests in `icetest` | yes, in 15 of the 17 scenarios that reach a roster: 736 pt applied, the roster exactly our members, Ice's icon right of its divider, every pass complete. T7 never got this far | MEASURED |
| The member leaves the bar at 736 pt | yes, in the bar captures: `sparse`'s member is gone at the end, while in `drawn` (lengths held, nothing applied) it stays drawn | MEASURED (captures, 1 scenario each); not judged by machine |
| Ice can verify it | **no**: every member check at every rest was `unverifiable:captureUnstable` (`noref`: `foldUnreadable`), so no scenario reached `verified`, and `drawn` never saw `stillDrawn` -- also with nothing moved | MEASURED |
| Why it cannot (read 2026-10-09 from this run's evidence, plan 2026-10-09-lab-first-run-followup) | in `drawn`, where Ice applies no length, the member and the hidden divider move 48 pt left in Accessibility 3-8 s after the baseline and back 6-11 s after the last trial; 4 of the 37 bar captures, each beside one of Ice's capture sessions, show a coloured block about 40 pt wide right of our helpers with both reference glyphs 48 pt left of where the other 33 have them. A reference more than 1 pt from its template's origin is one of the things that make a capture unstable | MEASURED |
| | the block is the screen-capture indicator, summoned by Ice's own captures after the baseline is cut, and that moved reference is what refused the trials (3 of 36 read `hidden`, each the first after a baseline) | INFERRED: Ice records the outcome, not which condition refused, nor what the matcher read |
| | whether another condition refuses as well; whether `noref`'s `foldUnreadable` is the same block | TBD |
| The block, timed in the owner's account | a 20 pt `MenuBarAgent` item right of our helpers, moving them 48 pt; it arrives 10.3 s (10.2-10.5, 9 of 9) after a capture session of 4 s or more begins, also when the capturing has already stopped, and stays about 10 s; a 1.5 s session never summons it (3 of 3) | MEASURED, run `20261009-111216-indicator`, 2026-10-09 |
| `positional` | blocked, no length, no IceBar, nothing moved: **pass** | MEASURED |
| `incomplete` | the stall at a rest retired the length and Ice said `blocked(discoveryIncomplete)`, then recovered -- what the scenario expects; judged `notEstablished` by a judge defect: a step's `seq` is the report's last line when the runner marked it, and the judge looked for the rest strictly before that line. Repaired 2026-10-09 with two more misreadings of the same rule (`incomplete`'s "30 s after", `crowded`'s witness against the first length); this run's evidence judged again: `incomplete` **pass**, the 18 other judged scenarios unchanged | MEASURED (the report; the replay). One round of one run, not S4's three |
| `crowded` | the bracketed witness held at 20 menus, but the roster then flapped between `stacked:2` and `noMembers` and Ice never applied a length | MEASURED; why the folded members drop out of the roster: TBD |
| `inverted` | the pre-seed (icon 5000, divider 1) did not put the icon left of the divider: `notEstablished` | MEASURED |
| `«` when a scenario began | never (0 of 19) | MEASURED |
| Cleanup | every domain deleted and verified empty; MenuBarAgent held 0 lab keys before | MEASURED |

## Capturing out of the indicator's reach (S3 of plan 2026-10-09-lab-first-run-followup, 2026-10-09)

| what | status | tag |
|---|---|---|
| When Ice captures | a baseline starts only 22 s after the last capture and has its burst to itself; an observation starts within 8 s of its burst's first capture if 2.5 s still fit, else waits for a clear bar; one attempt a session; every live capturer reports to one clock; work the machine no longer waits for is cancelled | MEASURED (unit tests: `CaptureBurstRuleTests`, `CaptureBurstObserverTests`, `IceBarHidingMachineTests`); builds (Debug); **not run** against a bar |
| What it costs | after a baseline the first observation waits about 22 s with the trial length set; a first calibration of fifteen observations about three and a half minutes instead of one; the violet block still shows for about ten seconds after each burst | INFERRED from the rule's numbers; not timed |
| What an observation says | the lab report's `observation` event: per reference its match, mismatch and distance from its template's origin, `captureStable`, the fold, the seconds waited, the burst's age | MEASURED (unit tests); not yet read from a real run |
| Not handled | Ice's window captures (the IceBar's cell images, search, settings) do not report to the clock; the numbers are one Mac's, one build's, two runs' | stated limit |
| Whether the lab's checks now verify | unknown until the next `icetest` sitting (S4) | TBD || The first try in `icetest` (`sparse` alone, run `20261009-234913`, 2026-10-09 23:49) | **fail**, `notVerified(noReference)`: the runner's own strip capture, 6 s before Ice's baseline, brought the block in during the baseline's last second. Ice's side went as designed (waited 19.9 s, burst 4.46 s). The runner now captures no strip before Ice's cycle and starts Ice only 22 s after any capture of its own | MEASURED (the times) / INFERRED (that the system counts any process's capture) |
| Captures by other processes | Ice's clock knows only Ice's own: a screenshot or a screen share by anything else within about 22 s can move the bar under a baseline or an observation; the `observation` event will show it as a moved or refused reference | stated limit || The second try (`sparse` alone, run `20261010-225047`, build `fb50d98`, 2026-10-10 22:50) | **pass**, `verified` at 728 pt after 292 s: 19 observations (a walk of 18 from 736 down to 592, where the fold came up, and up to 864, then the settle), every one `captureStable`, both references `unique` at distance 0 from their templates; each pair of observations shared a burst (ages 1.5 s and 5.9-6.7 s), each burst after a wait of 18.3-18.7 s | MEASURED, one run of one scenario |
| What that run does not show | the other 18 scenarios; three rounds; a bar with more than one member; that the refusals of the first run were the block (the block was kept out and the refusals did not come: consistent, not a proof) | TBD until the matrix |

## The lab matrix, one round in `icetest` (run `20261011-004911`, build `fb50d98`, 2026-10-11)

| What | State | Level |
|---|---|---|
| The round | 2 h 12 min; 14 scenarios pass (`sparse k2 k4 k8 press addremove fresh-off fresh-on placed-off placed-on relaunch positional drawn incomplete`), 1 in the first run. Not clean: S4's DoD is not met | MEASURED |
| Capture stability | 386 of 387 `observation` events `captureStable` with every reference `unique` at distance 0; the one other is `front-long`'s with 24 menus in front, both references `absent` | MEASURED |
| `noref` excluded | with no reference helper up the matcher read two of Apple's own items as references (19 of 19 observations) and Ice verified: in this account there is always a reference. `noReference` is unit-tested, and was seen live once (run `20261009-234913`) | MEASURED; the judge says `notEstablished` with that reason |
| `crowded` excluded | at 21 menus the system folded the helpers behind its own `«`; the cache then listed the members as visible (a section from frames, not a claim they are drawn), the roster was empty and Ice stayed at standard length with `noMembers`, no IceBar offered. Whether Ice should keep items the system folded is S5's question: the owner's goal is not the system's overflow | MEASURED limit; `notEstablished` with that reason |
| `inverted` not run | the pre-seeded preferred positions did not invert in either run (icon x 1508, divider x 1280): `blocked(iconLeftOfDivider)` is unit-tested only, until the owner's Command-drag in S5, with `inverted-moved` | MEASURED; `notRun` |
| `front-short`, `front-long` | not established: the runner never had the Terminal's pid, so it was never asked back (corrected by the next round's evidence, below) | MEASURED |
| What "clean" means (the owner's ruling, 2026-10-11) | three clean rounds running, as before; a round is clean when every scenario passes but `noref` and `crowded` (`notEstablished` with exactly the reasons above) and `inverted`, `inverted-moved` (`notRun`). Any other `fail` or `notEstablished` is not clean; an exclusion is never a pass. One rule for the runner's stop and the report (`passed_or_excluded`) | unit tests |
| Next | done: run `20261011-122641`, below | MEASURED |

## The lab matrix, a second round in `icetest` (run `20261011-122641`, build `6aa441c`, 2026-10-11)

| What | State | Level |
|---|---|---|
| The round | not clean: 12 pass; `noref`, `crowded` excluded and `inverted`, `inverted-moved` not run, as ruled; `front-short`, `front-long` not established; `relaunch`, `drawn` fail | MEASURED |
| `front-short`, `front-long` | the runner's defect: it read the front app's pid from `lsappinfo` as `"pid"=N`, and macOS 27.0.1 prints `pid = N`; `timeline.txt` of both rounds has no pid, and `steps.jsonl` has `back` false with no `activate` before it. Bringing an app forward works: the menus helper came forward on the first asking, both times | MEASURED |
| `relaunch` | Ice's gap. The second start's baseline, 13 s after its start and about 20 s after the first process's last capture, was `skip(noReference)`; Ice hid best effort, said `notVerified(noReference,unchecked:2)` and took no baseline again in the 10 minutes watched. In the round before, the same baseline came 1.5 s later and covered the members | MEASURED |
| Why that baseline had no reference | the capture indicator the first process summoned was still in the bar: a new process's burst clock knows nothing of another's captures | INFERRED |
| `drawn` | Ice as designed; the runner's limit was short. At 464 discovery was `incomplete:1` for 13 s, Ice said `blocked(discoveryIncomplete)`, then started its walk again from 736, and the 600 s ran out at 432, one length before the end. Why discovery was incomplete: unknown | MEASURED; the cause TBD |
| Fixed since (not yet run live) | `icewatch front` asks the system for the app in front, and the runner refuses to start, a dry run too, without a live pid; `drawn` waits 900 s; a baseline that did not cover the members is taken again, at most 3 times, the best-effort length staying until the next cycle may start (`IceBarHidingMachine`, unit-tested) | MEASURED (tests) |
| Next | done: run `20261012-165816`, below | MEASURED |

## The lab matrix, a third round in `icetest` (run `20261012-165816`, build `f02937b`, 2026-10-12)

| What | State | Level |
|---|---|---|
| The round | 1 h 57 min; not clean, for `crowded` alone: 16 pass; `noref` excluded and `inverted`, `inverted-moved` not run, as ruled | MEASURED |
| `front-short`, `front-long` | pass. The dry run and the run named the app in front (pid 693); the menus helper and the Terminal each came forward on the first asking (`steps.jsonl`: `activate`, `front`, `back`). Back in front, `front-short` verified again; with 24 menus in front `front-long` said `notVerified(unchecked:1)`, both references `absent`, as before | MEASURED |
| `relaunch` | pass. The second start's baseline, 13 s after its start, covered the members, and it verified | MEASURED |
| A baseline taken again | not seen live: no baseline of this round but `crowded`'s failed to cover. Unit-tested only; the plan's "the live `relaunch` has to show it" is not met | MEASURED (tests) |
| `drawn` | pass in 5 min 16 s: the walk went from 736 down to 416, came back to 736 and said `failed(drawn:1)`; discovery stayed complete | MEASURED |
| `discoveryIncomplete`, elsewhere | once in `placed-off`: `blocked(discoveryIncomplete)` at 17:57:19, a baseline again 25 s later, the scenario verified and passed. The cause: unknown | MEASURED; the cause TBD |
| Capture stability | 371 of 373 `observation` events `captureStable` with every reference `unique`; the other two are `front-long`'s with 24 menus in front and `crowded`'s, which had no reference | MEASURED |
| `crowded` | not established, and not the ruled exclusion. 57 s in the system folded both members and the roster emptied, as before. At 62 s the system's input menu read `stacked` on Ice's divider, frame `[1288, 46]` on `[1316, 18]`, the same right edge, mid-x 5 pt left of the divider's `minX`, and was a member by D-a. At 67 s it was still there (`[1336, 46]` on `[1364, 18]`); Ice set 736 at 80 s, its baseline was `skip(noReference)`, it said `notVerified(noReference,stacked:1)`, offered the IceBar, and gave the length back at 106 s. The judge refused: a roster member not ours | MEASURED |
| The same item, the rounds before | in the roster at 62 s with the same overlap in runs `20261011-004911` and `20261011-122641`, and out of it 5 s later (the divider at 1300 and 1320): which round it stays in is the system's | MEASURED |
| Fixed since (not yet run live) | D-a amended, the owner's ruling 2026-10-12: an item that was not a member, reads `stacked` and reaches onto the hidden divider (`maxX` past its `minX`) is not admitted (`PreferenceHidingMembership`, unit-tested). The judge, the runner and "clean" are unchanged; this round stays not clean | MEASURED (tests) |
| Still open in `crowded` | in run `20261008-234718` the two members themselves went in and out of the roster every 25 s, wholly left of the divider; the amended rule does not reach that. Not seen in the three rounds since | MEASURED |
| Next | done: run `20261013-000729`, below | MEASURED |

## The lab matrix, a fourth round in `icetest` (run `20261013-000729`, build `aefa7eb`, 2026-10-13)

| What | State | Level |
|---|---|---|
| The round | not clean, for `crowded` alone: 17 pass; `noref` excluded and `inverted`, `inverted-moved` not run, as ruled. The first round with no defect in Ice | MEASURED |
| `crowded`, Ice | as the goal asks: both members `ready` until 52 s, the roster empty from 57 s, `noMembers`; no length, no IceBar. The system's input menu was not admitted | MEASURED |
| `crowded`, the judge | `notEstablished`: "no bracketed witness". In all four rounds the only roster item that ever read `stacked` was the system's input menu, the one D-a now keeps out; our members go from `ready` to gone. The witness was resting on that item, and the runner's last ladder step skipped the "ladder ended" mark | MEASURED |
| Fixed since (not yet run live) | the owner's ruling 2026-10-13: the witness is the fold itself, read from our members (both `ready`, then two empty snapshots in a row after the ladder began, no length anywhere), and the judge reads it again from the report; the exclusion's reason is unchanged. The runner marks the ladder's end after the loop. Replayed on the four rounds' evidence: excluded in `20261011-004911`, `20261011-122641`, `20261013-000729`; still not in `20261012-165816`, where Ice did hide the system's item | MEASURED (tests, replay) |
| Next | stage; one round, the other two only if it is clean | TBD |

## The lab matrix, a fifth round in `icetest` (run `20261014-003331`, build `935aac1`, 2026-10-14)

| What | State | Level |
|---|---|---|
| The round | 2 h 3 min; not clean, for `crowded` alone: 16 pass; `noref` excluded and `inverted`, `inverted-moved` not run, as ruled | MEASURED |
| `crowded`, Ice | never said more than it knew: `notVerified(lengthNotApplied,stacked:2)` from 57 s, `notVerified(lengthNotApplied)` from 67 s, a length of 736 at 81 s, `notVerified(noReference,unchecked:2)` at the rest, the length retired 4 s later | MEASURED |
| `crowded`, the bar | at 19 menus, 57 s in, the hidden divider stood 48 pt left of its place (1232 for 1280) and both members read `stacked` on one frame; 10 s later all three were back, with the 19 menus still up. `«` was listed at the witness and not 15 s into the rest | MEASURED |
| What pushed it | the capture indicator: 48 pt and 10 s are its measured figures (run `20261009-234913`, above) | INFERRED |
| The same in every round | the bar changes 57 s into `crowded` in all six runs since `20261008-234718`, and the witness was read then or 5 s later, at 19 to 22 menus, in the five that have one: the ladder reaches the bar's end as the indicator arrives | MEASURED (the six reports) |
| Why 57 s | Ice starts a calibration no sooner than 30 s after the last (`minInterval`); the one near 46 s captures for 4 s or more and the indicator follows 10.3 s later | INFERRED: the report has no line for a calibration start |
| The judge | `fail`, clauses 12 and 6: it took a witness read under the push for the scenario's premise | MEASURED |
| Fixed since (not yet run live) | a reading with the divider, at standard length, left of where it stood with both members `ready` is no witness: the runner waits the push out on the same ladder step (20 s at most), `bracket` and `fold` answer nothing under it, and the judge says `notEstablished` ("the witness was read with the divider pushed left of its place") when the witness's snapshot has it. `bracket` also answers only for a snapshot that is itself `stacked`. Replayed on the six runs' evidence: `20261011-004911` and `-122641` excluded as before, `20261012-165816` and `20261013-000729` not established as before, `20261008-234718` and `20261014-003331` now not established for the push | MEASURED (unit tests, `test-lab.sh` with a stub Ice, the replay) |
| Found while testing | a push that came between the runner's check and its bracketed reading still gave a witness (the stub run); the check is now part of the reading | MEASURED (`test-lab.sh`) |
| Not known | whether a length comes while the ladder waits out a push. The argument that it does not: the push is within 20.3 s of the calibration start that summoned it, and no start follows for 30 s | INFERRED |
| Not known | what `crowded` ends as once no witness is read under the push: the fold (the ruled exclusion), or both members `stacked` at a rest. Never seen without the push | TBD: the next round |
| The staging, 2026-10-13 | CleanMyMac removed 30 `.lproj` folders of Sparkle from the staged `Ice.app`; the dry run refused it ("the staged files do not match lab.env's sha256"). Restored from the build product, whose tree hash was the recorded one; the round ran on that | MEASURED |
| Next | stage; one round, the other two only if it is clean | TBD |

## The lab matrix, a sixth round in `icetest` (run `20261019-004100`, build `0fbae72`, 2026-10-19)

| What | State | Level |
|---|---|---|
| The rounds | three run; rounds 1 and 2 clean, round 3 not clean, for `press` alone ("ended unverified, expected verified"); S4 DoD not met | MEASURED |
| `crowded` | `notEstablished` in all three rounds: "the system folded the members out of the roster", the ruled exclusion. Answers the fifth round's TBD: with no witness read under the push, it ends as the fold | MEASURED (`*-crowded/verdict.json`, `steps.jsonl`) |
| `3-press`, Ice | length 728 at 293.8 s; the settle's observation at 297.3 s was its burst's second session (`waited` 0, `burstAge` 6.9); `verified` at 297.3 s; `notVerified(stacked:1)` at 300.7 s, 10.2 s after the burst began, member 1 `stacked` at an unchanged frame, to the scenario's end | MEASURED (`3-press/report-1.jsonl`) |
| Over the run | a `stacked` beginning 8-16 s after a burst's start: 0 of 137 one-session bursts, 305 of 402 two-session bursts. Every other verified scenario verified on a one-session burst or ended inside the indicator's 10 s: it passed by timing | MEASURED (the run's reports) |
| What `3-press` was stacked on | the capture indicator, a `MenuBarAgent` child and so an obstacle | INFERRED (timing, the tally, FINDINGS "The capture indicator, timed"): the report had no obstacle frames |
| Fixed since (not yet run live) | plan `2026-10-19-verify-in-a-clean-burst`: Ice verifies only on a burst's first session read within 2.5 s of its start, else confirms the length in a burst of its own (`notVerified(confirming)`); settles, confirmations and re-checks close their burst as they start. The report now dates each observation's burst (`burstID`, `ordinal`, `sinceCapture`) and names what each member overlaps; `hide` waits out the verifying burst's indicator before the scenario goes on (about 22 s a scenario) | MEASURED (unit tests: IceCore 700, MenuBarDiscovery 87 with a Feed/machine contract test, lab-tool 44; `test-lab.sh` with a stub Ice; app build; Codex review rounds 2-3 no findings) |
| Next | stage the branch head (code as of `6f0a5c1`); the seventh round | TBD |

## The lab matrix, a seventh round in `icetest` (run `20261031-015900`, build `b2f8744`, 2026-10-31)

| What | State | Level |
|---|---|---|
| The rounds | round 1 not clean, for `k8` alone ("never verified (last status: notVerified(lengthNotApplied))"); the run stopped there; S4 DoD not met. `noref`, `crowded` the ruled exclusions; `inverted`, `inverted-moved` not run | MEASURED |
| Verify in a clean burst, live | every verifying observation was a burst's first session (`ordinal` 1, `burstAge` about 1.56 s); no `notVerified(confirming)`; no verified rest fell back during the hold; `press` passed | MEASURED (`1-*/report-1.jsonl`) |
| `1-k8` | no observation joined a burst (`sinceCapture` about 2.23 s against `k4`'s 1.40 s), about 24 s a step, as in round six (verified at 467-471 s). At 217 s discovery was `incomplete:1` for about 5 s at length 608: `blocked(discoveryIncomplete)`, the length retired, a baseline again, the walk from 736 again; about 685 s needed against the 600 s limit | MEASURED (`1-k8/report-1.jsonl` seq 96-109) |
| `k4`'s join | its second session starts about 5.4 s into a burst, against the 5.5 s it may | MEASURED |
| Transient discovery incomplete (known limit) | outside the `incomplete` scenario, in 7 of about 76 scenario runs of rounds six and seven; always one process, never Ice itself; each one retires the length and starts the walk again. Which process: unknown until the next run | MEASURED (the two runs' reports); the cause TBD |
| Fixed since (not yet run live) | plan `2026-10-31-k8-hide-limit`: a hide waits `HIDE_LIMIT` (1100 s, two walks; `STATUS_LIMIT` 600 and `DRAWN_LIMIT` 900 stay); the snapshot names each failed read (`incomplete`: pid, bundle id, Ice or not); the judge folds them into episodes, fails a run on Ice's own, leaves it not established on a member's, and the report lists every episode, its length and duration, with the count on the DoD line ("met (functional; ...)") | MEASURED (unit tests: IceCore 701, lab-tool 53; `test-lab.sh` with a stub Ice; app build; simcodex 2 rounds, Codex round 2 no findings) |
| Next | done: run `20261111-233109`, below | MEASURED |

## The lab matrix, a ninth sitting in `icetest` (run `20261111-233109`, build `9a6d7a6`, 2026-11-11), and the end of the matrix as a gate

| What | State | Level |
|---|---|---|
| The round | 2 h 25 min; round 1 not clean, for `k8` alone ("never verified (last status: notVerified(unchecked:8))"); the run stopped there. Every other runnable scenario matched its kind. `noref`, `crowded` the ruled exclusions; `inverted`, `inverted-moved` not run | MEASURED |
| `1-k8` | the walk 736 to 672 clean, about 24 s a step. At 23:59:40-0:00:00 the clock went from 124 to 116 pt and every item left of it moved 8 pt. The trial at 656 and the settle at 704 then read unstable, both references `unique` at offset 8; Ice rested `notVerified(unchecked:8)` and observed nothing more for 924 s. `HIDE_LIMIT` was not the cause: the walk ended at 183 s | MEASURED (`1-k8/report-1.jsonl` seq 68-270, `report-1.log`) |
| Why it stayed | a rest observes again only when a baseline is owed or a layout change is pending, and the layout signature leaves frames and system items out. The same happens at a verified rest: the next app in front re-checks against the old baseline | INFERRED (code); both reproduced by unit tests |
| Discovery incomplete | 3 episodes in 3 scenario runs, all another process at standard length: `com.apple.Safari` 1.5 s (`noref`), `com.microsoft.autoupdate.fba` 10.0 s (`crowded`) and 12.5 s (`relaunch`, which passed). None Ice's own, none a member's. Answers the seventh round's "which process": not one process | MEASURED (run report) |
| The owner's decision, 2026-11-12 | no more full overnight matrix. "Three clean rounds running" was never met in nine sittings (best: two of three, 2026-10-19) and is given up. S4 closes on the gate of plan `2026-11-12-displaced-baseline`, section 3: **a lower acceptance confidence, chosen on purpose, not an equivalent** | the owner's ruling |
| Fixed since | a rest whose reading finds the bar displaced as one piece (at least two references, each found well, all the same distance off) retires the length and baselines again, at most 3 times until a length verifies; a reading that is unstable for another reason (references covered by the frontmost app's menus, `front-long`) keeps the length as before | MEASURED (unit tests: IceCore 712, MenuBarDiscovery 88, lab-tool 53; app build; `check-a3a4.sh`) |
| The rule over old runs | of 1893 observations in runs `20261019-004100`, `20261031-015900` and this one, 6 were unstable; the rule is true of `k8`'s two and of none of `front-long`'s four | MEASURED (the rule replayed over the reports) |
| The recovery, live | **unit-tested, not witnessed live.** G3's one run (`20261112-100028`, build `a5630ab`, `icetest`, 2026-11-12) started at 10:00:28, after the clock's change at 10:00:00: `k8` **pass**, verified at 473 s at length 728, 19 observations, every one stable with both references `unique` at offset 0, one "IceBar baseline: ok true", no discovery incomplete. A regression pass only: no reading was displaced, so the recovery path was not entered. Not run again (plan section 3, G3) | MEASURED (`1-k8/report-1.jsonl`, `report-1.log`, `verdict.json`) |

### The evidence S4 closes on

Each scenario's latest live pass. The hiding machine changed after every one of them
(this fix); the changed path is entered only by a displaced reading, which none of
these runs had outside `k8` (the row above), and is covered by `IceBarHidingMachineTests`
("A rest read on a bar that moved under its baseline") and `ObservationDiagnosticsTests`.

| Scenario | Expected | Latest live pass | Level |
|---|---|---|---|
| `sparse` `k2` `k4` `press` `addremove` `fresh-off` `fresh-on` `placed-off` `placed-on` `front-short` `relaunch` | verified | run `20261111-233109`, `9a6d7a6` | MEASURED |
| `k8` | verified | run `20261019-004100`, `0fbae72`, three rounds. Since: failed 2026-10-31 (the 600 s limit; `HIDE_LIMIT` since) and 2026-11-11 (the displaced bar; fixed above). Live pass on the current code: run `20261112-100028`, `a5630ab`, one round, no displaced reading in it | MEASURED; the recovery unit-tested only |
| `front-long` | best effort | run `20261111-233109`, `9a6d7a6` | MEASURED |
| `positional` `incomplete` | blocked, unverified | run `20261111-233109`, `9a6d7a6` | MEASURED |
| `drawn` | failed, as expected | run `20261111-233109`, `9a6d7a6` | MEASURED |
| `noref` `crowded` | excluded (the ruling of 2026-10-11) | never a pass | MEASURED limit |
| `inverted` `inverted-moved` | not run | the owner's Command-drag, S5 | TBD |

### Limits S4 closes with

| Limit | Level |
|---|---|
| Three clean rounds running were never achieved; no claim rests on them | MEASURED |
| A transient (another process's failed read, a capture the indicator answers, a system item changing width) can leave Ice `notVerified` for a while or until the layout next changes. No run has shown a false `verified` | MEASURED for the runs above; INFERRED beyond them |
| With one reference, or references that moved by different amounts, a displaced bar is not recovered: Ice stays `notVerified` until an item or display change | INFERRED (the rule) |
| A bar that keeps reading displaced after 3 baselines is left alone, unverified | unit tests |
| All of it on one Mac, one display, the `icetest` account and sacrificial helpers; the owner's own bar is S5's | MEASURED |

## S5, the owner's acceptance: built, not run (2026-11-12, plan 2026-11-12-s5-owner-acceptance)

| what | status | tag |
|---|---|---|
| The sitting's runner and judge | `run-s5.sh` starts a lab-identity copy of Ice and one sacrificial helper in the owner's account, asks the owner to look, click and drag, and `s5-tool.py` judges clauses C1-C8 from Ice's report and the answers: `pass`, `partial`, `fail` or `notEstablished`. The release Ice's settings are read twice, never written; no input event is posted | MEASURED against stubs only (`test_s5_tool.py` 49, `test-s5.sh` 24, `test-lab.sh` unchanged and green; two review rounds, Codex in both) |
| Staged | `52d841d` in `/Users/Shared/IceReverse-lab`; `run-s5.sh --dry-run` passes its guards in the owner's account from the assistant's session. From the owner's own Terminal (its Accessibility and Screen Recording): not yet run | MEASURED (the dry run) / TBD (Terminal) |
| On the owner's bar | nothing has run: whether a fresh identity starts with no item of the owner's left of its divider, whether the helper becomes the member, how long a walk takes there, whether the panel draws and a click opens the menu | TBD: the sitting |

## S5, the owner's sitting (run `20261112-120353`, build `52d841d`, owner's account, 2026-11-12): fail at C3

| what | status | tag |
|---|---|---|
| The verdict | `fail`: C1 pass, C2 pass, **C3 fail** ("the runner's wait for verified ran out (last status: notVerified(noReference,unchecked:1))"), C4-C6 not reached, C7 pass, C8 pass. The sitting took 19 minutes, all of it waiting | MEASURED (`verdict.json`) |
| The start on the owner's bar | a fresh identity put its hidden divider at x 1085 and its icon at x 1500 with nothing of the owner's left of the divider; the helper landed left of it (x 1065) and was the one member 6 s after Ice's start | MEASURED (`report.jsonl`) |
| Why it never verified | every one of 5 baselines ended "ok false coverage skip(noReference) targets=1": Ice applied 736, could check nothing ("hidden 0 drawn 0 of 1 ... stable unread"), rested `notVerified(noReference,unchecked:1)`, retired the length and tried again; from 186 s it stayed at that rest (once more after a `blocked(discoveryIncomplete)` at 399 s). Eight items of the owner's were listed right of the divider, none with an identifier. Whether the plan found no candidate among them or the baseline accepted no template of the two it tries is not in the report | MEASURED (the statuses, lengths and log) / TBD (which of the two) |
| What the lab's `verified` rested on | every verified lab run had the two reference helpers we started ourselves between the divider and the icon; the owner's bar has none. `noref`, the scenario without them, was excluded in `icetest` because that account's two system items served as references | MEASURED (run-lab.sh, the ruling of 2026-10-11) |
| The system's `«` | listed at every trial at 736 on the owner's bar (`chevron true`), not listed at standard length | MEASURED (log, snapshots) |
| The Mac afterwards | Ice and the helper stopped, the lab domains empty, the release Ice's settings byte-identical, the order of the owner's items unchanged; 12 stored values of other items changed in MenuBarAgent's store, no key added or removed | MEASURED (C7, C8, the store diff) |
| The panel and the click | not reached | TBD |
| **The cause, found the same day** | the owner's bar overflows at rest: with no Ice running and a short front menu (max x 574, notch at 771), the system's `«` is listed; 10 status items, 8 on the bar. A read-only probe (one discovery pass, then the detector's own baseline over every on-bar item): ink ok, `foldAtBaseline present`, 0 templates; the three leftmost items `readsDisagree`, the other five `foldNotAbsentAtBaseline`. `StripAssessor.baseline` gives no template at all unless the fold is absent (`StripAssessor.swift:124-130`, frozen), so on this bar no baseline can find a reference and no rest can be `verified`. The cap of two candidates in `CheckPlan` is not the cause: more candidates reach the same baseline (Codex, same day) | MEASURED (probe and `icewatch chevron`, 2026-11-12 about 12:50, owner's account; the code) |
| What that leaves | on the owner's bar the only state Ice can reach is the designed "hiding requested, not verified" (O1: the length is applied, the IceBar offered). Whether the spacer hides the member there, and whether the panel draws and a click opens the menu, are neither shown nor refuted: the runner stopped at C3 because the S5 plan made `verified` a condition of looking. The lab's `crowded` scenario, the same condition, was excluded on 2026-10-11 as "S5's question" | MEASURED (the stop) / TBD (the rest) |

## S5, the owner's second sitting (run `20261112-173803`, build `3d419c4`, owner's account, 2026-11-12): it works by the owner's eyes, not verified

| what | status | tag |
|---|---|---|
| The verdict | C1 to C7 `pass`, C8 `changed`, so the run's result line reads `fail`: the one reason is "the owner did not say the item is back in its place", and that is the runner's fault, not Ice's (step 4 asked the owner to drag back an item that was hidden inside Ice and so not on the bar; the owner skipped it as told) | MEASURED (`verdict.json`, `steps.jsonl`) |
| The helper, on the owner's bar | 268 s after Ice's start the owner answered: the helper is gone from the bar (y), it is listed in the IceBar (y), a click on it there opened its menu (y). The report showed the IceBar presented with its one cell enabled | MEASURED (the owner's answers; C3, C4) |
| An item of the owner's own | dragged left of the divider by the owner; Ice saw it 11 s later and rested with both members about 4 minutes after; listed in the IceBar (y), its menu opened from there (y) | MEASURED (C5) |
| Ice's icon left of its divider | Ice said `blocked(iconLeftOfDivider)`, retired the length, offered no IceBar; the layout pane showed its line (y); dragged back, Ice rested again about 6 minutes later and the line was gone (y) | MEASURED (C6). This is `inverted-moved`, never run in the lab |
| Not verified | every rest was `notVerified(noReference,unchecked:n)`: on this bar Ice cannot check its own hide (the section above). What is measured is the owner's eyes and Ice's own report of its state, not a pixel check | MEASURED (the notes) |
| The Mac afterwards | Ice and the helper stopped, the lab domains empty, the release Ice's settings byte-identical; 7 stored values of other items changed in MenuBarAgent's store, no key added or removed. The item the owner dragged in was left where Ice's exit drew it: for the owner to drag back | MEASURED (C7) / the order: the owner's |
| How long | 22 minutes, of which about 15 were Ice's three waits (4.4, 4.3 and 6.4 minutes): on this bar every change of members or placement costs three baseline retries before Ice rests | MEASURED (`steps.jsonl`) |

## Free use on the owner's bar (lab-identity copy, run `20261112-181149-free`, build `3d419c4`, 2026-11-12): unusable as built

| what | status | tag |
|---|---|---|
| What happened | 223 s of the owner using the bar normally (items dragged left of the divider, the mouse on the bar, part of it under a screen recording): Ice never reached a rest. The length was applied and retired within 2 to 5 s four times (67/69 s, 102/105, 135/138, 196/201); the members left the bar and came back; the IceBar was never offered. The owner: "useless" | MEASURED (`report.jsonl`; the owner's recording) |
| Why, one | the coordinator calls the pointer being over the menu bar "interacting" (`IceBarHidingCoordinator.swift:130`), and the machine retires the length on interaction in every phase before a rest (baselining, settling, confirming). Snapshots show `isInteracting` true around three of the four retires | MEASURED (snapshots) / the code |
| Why, two | on this bar every baseline ends `skip(noReference)`, yet the machine still runs its baseline, a 20 s settle and up to three baseline retries before it rests unverified: about 3 minutes with the pointer kept off the bar (the second sitting). The retries exist for a baseline cut by a capture; the event `baseline(ok:)` no longer says why it failed | MEASURED (both runs) / the code (Codex, same day) |
| The 135/138 retire | no interaction in the snapshots, no status or observation event; under the screen recording. A soft layout change (frontmost app, menu edge) while settling would do it; which one is not in the report | TBD |
| The owner's settings afterwards | Ice quit by the owner; the lab domain empty, the release Ice's settings unchanged | MEASURED |

## Hide at once (build `2499e5f`, plan 2026-11-12-hide-at-once), on the owner's bar, 2026-11-12

| what | status | tag |
|---|---|---|
| What changed | Ice runs the hiding machine with `verifies` off: a member left of a settled divider is hidden on the sample that brings it, at 736 (or the last verified length), and Ice rests "not verified" with the IceBar offered. No baseline, no observation, no wait, no regard for the pointer. A pass is run 1.15 s after a drop or a retire. `-IceLabVerify YES` (what `run-lab.sh` passes) keeps the machine as it was | MEASURED (IceCore 722 tests, app build, Codex review: no findings) |
| A helper appearing, three runs | from the helper's item being up to the length applied: 2.6 s (build `57d8862`), then 1.3 s and 1.3 s (build `2499e5f`); the IceBar offered within 0.4 s of that | MEASURED (runs `20261112-183019-selftest` and the two after it, owner's account) |
| The owner's free use, run `20261112-183251-free`, 171 s | three of the owner's items dragged in, one after another; each time Ice rested again 1.1 to 4.1 s after it had retired the length (a retire comes with the drag's start, so the time holds the drag itself); the IceBar was presented 20 times; every cell enabled, no press failed; an icon dragged left of the divider read `blocked(iconLeftOfDivider)` and recovered within 2 s of being put back. Every rest `notVerified(unchecked:n)` | MEASURED (`report.jsonl`). What the owner thought of it: TBD |
| Still so | the hidden items show on the bar for about a second at every change of members (the divider decides membership at standard length); nothing is verified in this mode | MEASURED (the retires) / by design |

## After hide at once: two defects found in the owner's free use and repaired, settings trimmed (2026-11-12, to build `8966aee`)

| what | status | tag |
|---|---|---|
| An item of the owner's gone from the bar and absent from the IceBar | run `20261112-184440-free` (build `45c48b4`): the owner dropped a second item left of the divider while Ice rested; no retire followed, the roster stayed at one member, and the item was pushed off with it and listed nowhere until Ice quit. The machine is sampled once a second and the drag began and ended between two samples. Repaired in `73ce7c8`: a drag's start is reported by the next sample whatever its end, and samples the machine at once | MEASURED (the report: one member, no `length null` after 444.8 s, the divider's frame 59 pt further right) / the cause INFERRED from the code; the repair not yet seen by the owner |
| Taking an item out | holding Command with the pointer on the bar gives the members back (`IceBarArrangingRule`, `45c48b4`); after Command is let go the bar is read once the divider has settled, not earlier (Codex's finding, `617b969`) | built, unit-tested; **not exercised**: it needs real keys and pointer, which the assistant has not sent |
| Settings | on macOS 27 no "Menu Bar Layout" pane (its two status lines are in General); the updater never starts and nothing offers a check; the upstream links are gone from About (plan `2026-11-12-settings-cleanup`) | built (`8966aee`), running on the owner's bar as `20261112-190842-free`; not yet looked at |
| The owner's own findings | changing the Ice icon works; "Use Ice Bar" works; a click anywhere on the bar shows the IceBar under the pointer (Show on click with the dynamic location) | the owner's report, 2026-11-12 |
| Every other setting | not tried: General (launch at login, location, show on click/hover/scroll, rehide, spacing), Appearance, the five hotkeys, Advanced (divider style, hide app menus, secondary context menu, hover delay). The owner's ruling: the assistant tries each itself with automation, the owner tests nothing; what does not work is not shown | TBD, next session |

## The settings pass (2026-11-12, plan 2026-11-12-settings-cleanup): every setting tried by automation; what failed is gone on macOS 27; version 1.0

All of it on macOS 27.0.1 (26A434), the owner's account and bar, a lab-identity copy of Ice
with two sacrificial helpers, input posted by `probes/settingsdrive.swift`. Runs
`20261112-192750-s6` (as found), `-200049-s6` (first repair), `-203533-s6` (the cut, 20 cases
of 20 passed), `-205315-s6` (after the code review, the 11 cases its fixes touch). Each case's
finding is in the plan's appendix B.

| what | status | tag |
|---|---|---|
| Kept, each seen to work | launch at login (the registration only); the Ice icon, a custom one, as template; IceBar location, all three; show on click, hover (and its delay), scroll; automatically rehide, all three strategies; the menu bar appearance: tint, gradient, shadow, border with colour and width, full shape with either caps, inset, dynamic, reset; the hotkeys for the hidden section and the application menus, and the recorder; the secondary context menu and its two entries; a click on an IceBar cell | MEASURED (run `-203533-s6`; the touched ones again in `-205315-s6`) |
| Not offered on macOS 27, and without effect when stored | Show Ice icon (off: Ice is blocked, hides nothing); Use Ice Bar and its hotkey (off: nothing is hidden); item spacing (never run: its "Apply" quits every app with an item); the always-hidden section and its hotkey; the search panel's hotkey and menu entry (a click on a result opens nothing); divider style and "show all sections while dragging" (no difference the owner can see); hide app menus (only outside IceBar mode); the temporarily-shown delay; the split shape (drawn as the full one) | MEASURED for each "off"/"dead" above except item spacing and the two known from T2d; the removal itself: `T6-panes`, `T6-menus`, `T6-removed` |
| A stored value of a removed setting | not read into effect, and left in the defaults as it was | MEASURED (`T6-removed`, run `-205315-s6`) |
| Repaired: a click or a rest on another app's item showed the IceBar | on 27 Ice asked a window list that is empty; it now asks the last pass's frames (`MenuBarPointRule`) | MEASURED before and after (G3, G4) |
| Repaired: the smart rehide | it took the system's full-screen windows (levels 20, 21) for the clicked one; they are passed over (`SmartRehideRule`). A click in the front app's window closes the IceBar, 3 of 3 | MEASURED. One display; a click that itself brings another app forward may come before that app is active (upstream's quarter second): not repaired |
| Repaired: an item taken out stayed listed as hidden | after a drag or Command let go, Ice hid on a roster read during the drag. Nothing is hidden now until a pass that began afterwards was read | MEASURED: before, 3 of 4 take-outs; after, 10 of 10, and 10 of 10 quick drags in (retire 0.12 s after the drag's start, in the IceBar about 1.3 s after its end) |
| Hold Command on the bar | the hidden items are back at once and answer at their places; let go, hidden again; dragged right of the divider, the item leaves the IceBar | MEASURED (D1). By who answers at the point, not by pixels: on this bar a notch app's overlay covers that stretch |
| Version | 1.0 (About pane read over Accessibility) | MEASURED |
| The Mac after the last run | no Ice, no helper, the lab domain empty, the release Ice's settings byte-identical, no spacing key, no lab login item (the toggle read off) | MEASURED (`finish.json`) |
| Tests | IceCore 745, MenuBarDiscovery 88, `test_settings_lab.py` 23, `test-settings.sh`, `test-lab.sh`, `test-s5.sh`, `check-settings.sh`, `check-a3a4.sh`, the app build | MEASURED, all passing |

### Limits

| Limit | Level |
|---|---|
| Synthetic input, one Mac, one display, the owner's bar as it was that evening, two helpers. Nothing was pressed or dragged that is the owner's | MEASURED |
| Launch at login: that a login starts Ice was not run. The custom icon's file chooser was not driven. macOS 14 to 26: not runnable here; everything removed is removed only on 27 | INFERRED / not run |
| The hiding machine still hides on the first sample after leaving `blocked` or turning the mode on, whatever the roster's age; only the way out of arranging waits for a fresh pass | INFERRED (code review) |
| `ScreenCapture.checkPermissions` reads a window list that is empty on 27 and falls back on a value macOS gives once: Screen Recording granted while Ice runs may not be seen until Ice is started again | INFERRED (code review), not this pass's |

### The staging folders, cleared (2026-11-12, at the owner's ask)

| what | status | tag |
|---|---|---|
| The lab matrix's evidence (13 runs, 2626 files) | copied with `ditto` from `/Users/Shared/IceReverse-lab/evidence` to `~/IceReverse-evidence/lab-matrix/`, every file's sha256 equal; the hashes are in `MANIFEST.sha256.json` there | MEASURED |
| The route C, spike and t7 runs | each already in `~/IceReverse-evidence/<run id>` with the same bytes, but for t7's `20261007-181858-t7`, copied now | MEASURED |
| `/Users/Shared/IceReverse-c2`, `-icebar`, `-spike` | deleted | MEASURED |
| `/Users/Shared/IceReverse-lab`, `-t7` | everything of the owner's deleted (the staged Ice, the helpers, `icewatch`, the scripts); what `icetest` wrote under `evidence/` the owner then deleted with `sudo`, and the `icetest` account with its home folder: nothing of either is left. `run-lab.sh`, `run-s5.sh`, `run-t7.sh` and the settings pass need `stage-lab.sh` (or `stage-t7.sh`) run again before their next use | MEASURED |
| 1721 empty `com.icespike4.lab.*` preference files, then the 94 other `com.icespike4.*` ones (trace, t7, the helpers) | each read as an empty dictionary, then deleted; none is left. The release Ice's settings were not touched | MEASURED |


## The limits of the settings pass, tested (2026-11-13, plan 2026-11-13-untested-limits)

macOS 27.0.1 (26A434), the owner's account and bar, build `1ade8e9` plus the harness
changes of this plan, a lab-identity copy, sacrificial helpers, synthetic input. Run
`20261113-123139-s6` (cases L1, L2, L3; `finish.json`: nothing left running, the lab domain
empty, the release Ice's settings byte-identical).

| what | status | tag |
|---|---|---|
| The custom icon through the file chooser (L1) | "Choose image…" opens the chooser in Ice; its Go to field takes a path; Open closes it; the stored icon is "Custom" and its data equal byte for byte to the chosen PNG; the bar shows the red square in its own colour (`icon-after.png`). The case's pixel-mean check failed: the mean over the icon's frame takes in today's blue bar around the 16 pt square (a weak check, Codex's plan point 7); the picture is the evidence. Third attempt; the first two failed in the harness (the driver's new `axset` not rebuilt; the Go to field not told from the list's file names) | MEASURED |
| Smart rehide, a click that brings another app forward (L2) | 10 of 10 closed within 2 s; the clicked app was front 0.10 to 0.13 s after the button went down, so the 250 ms decision point was never reached first. The race exists only for an app slower to activate than that: not seen, not repaired | MEASURED (this Mac) / INFERRED (a slower app) |
| Leaving `blocked` with an old roster (L3) | the stale condition produced in 3 tries (the roster at the drop of Ice's icon without the new item, started 0.05 to 0.5 s before it): each time the length came with the roster that held the item (0.34/0.34, 1.05/1.06, 0.78/0.78 s after the drop). The limit stated on 2026-11-12 does not occur: leaving `blocked` by a drag is held as leaving arranging is, and blocked's preconditions come from the same pass as the roster. One try ended blocked again (the harness dropped the icon left of the divider): not counted | MEASURED (3 tries) |
| A new app's item at rest | neither on the bar nor in the IceBar for about 2 s (one sample of the harness, 1.95 s), until the next pass lists it: it lands left of the divider and is pushed off at once. Seen the same in L3 after a drop (1.8, 2.0 s) | MEASURED; resolution about 2 s |
| Launch at login, an actual login (L4) | not run: it needs a logout of the owner's session. The registration was measured (G1, 2026-11-12) | not run |
| Screen Recording granted while Ice runs (L5) | not run: a grant needs the owner's password in System Settings | INFERRED (code), not run |

These replace the three rows "Launch at login…", "The hiding machine still hides…" and
"`ScreenCapture.checkPermissions`…" of the settings pass's limits, which stay as they were
written for that date.

Codex: the plan reviewed once (REVISE, answered in the plan); the harness changes reviewed three rounds (2, 1, 0 findings, all P2, fixed; L2 and L3 re-read against them: no try of this run is affected).

## The daily Ice (2026-11-13, plan 2026-11-13-untested-limits section 5)

| what | status | tag |
|---|---|---|
| `/Applications/Ice.app` | this fork, 1.0, `io.github.tk88101.Ice`, signed by the owner's team `Q6WP7U2GDM`; the upstream release archived in `~/Ice-release-archive/` | MEASURED |
| Ice's menu bar item service (XPC) | starts and the session activates with the team-signed build (it never started ad-hoc, row at the top of this file) | MEASURED, 1 launch |
| Permissions, launch at login | granted; registered and enabled | MEASURED; an actual login not yet seen |
| Members | none yet: the new identity starts with nothing left of its divider | MEASURED |

## No flash when an icon comes or goes right of the divider (2026-11-13, plan 2026-11-13-flash-on-item-change, build `4de4081`, installed as the daily Ice)

| what | status | tag |
|---|---|---|
| The owner's report | any third-party icon added or removed showed the hidden items for about 1.2 s; the hiding machine retired the length on every change of the item set | MEASURED (owner's recording; log 14:40:11 and 14:40:16) |
| An icon removed | the length stays: 3 of 3 helper quits (E2), and a member's helper quitting (E4: members 5 to 4, no retire) | MEASURED, helpers only, owner's bar |
| An icon added right of the divider | the length stays when no icon went since the last standard-length pass (E1 run 1); it still retires once when one did (E1 runs 2, 3; E3 A) | MEASURED |
| An icon gone and one added in the same pass | retires once, then hides again; the new helper drawn right of the divider (E3 B) | MEASURED |
| An icon added left of the divider | retires once, the item becomes a member (members 4 to 5) and is hidden at 1.5 s (E4) | MEASURED (status log); the IceBar not opened (Ice's icon is not pressed by automation) |
| A changing title | an item whose title changes reads as one gone and one added: still retires once | INFERRED (code), not run |
| An anchor rule to cover remove-then-add | rejected after Codex review (AX frames are not drawn-ness) | plan D2b |

Evidence: `~/IceReverse-evidence/20261113-flash/`. Rollback: `~/Ice-release-archive/Ice-1.0-before-flash-fix-20261113.zip`. Codex: the plan three rounds (REVISE, REVISE, AGREE), the code two (one P2 fixed, then clean), D2b one round and a debate (dropped).

## Traditional Chinese and the language option (2026-11-13, plan 2026-11-13-zh-hant, version 1.1.0, installed as the daily Ice)

| what | status | tag |
|---|---|---|
| Completeness | 199 keys (compiler-extracted, hand-listed, IceCore templates), every one with a zh-Hant value (`check-zh-hant.sh`) | MEASURED |
| L1 System on the owner's list (ja, en, zh-Hant) | Settings in English | MEASURED |
| L2 繁體中文 chosen in the pane by automation, Ice relaunched by its own button | every pane and both right-click menus read in Chinese (`zh_check.py`); run 1 found three English texts (Launch at login, the hotkey button's accessibility labels, a space between Chinese sentences), fixed; run 2: nothing English left. The About pane's copyright line stays English on purpose | MEASURED, runs 16:07 and 16:10 |
| L3 back to System | English again after relaunch; the app's `AppleLanguages` removed | MEASURED |
| Layout | no clipping seen in the Chinese panes' captures | MEASURED (by eye) |
| The owner's setting | System (English), the owner's choice | as left |

Evidence: `~/IceReverse-evidence/20261113-zh/`. Codex: the plan three rounds (REVISE, REVISE, AGREE), the code four (two P2 fixed, then clean twice).
