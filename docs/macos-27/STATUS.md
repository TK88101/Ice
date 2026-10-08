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
