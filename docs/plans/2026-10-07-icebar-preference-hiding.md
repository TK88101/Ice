# IceBar on macOS 27, re-aimed: preference hiding, proven in a harness before any owner sitting

2026-10-07 · final (Codex round 5: CONVERGED; T2 design added 2026-10-08, Codex round 3: CONVERGED; Appendix) · T1, T3a implemented, T2 done 2026-10-08 (T2b: Q1 only, see its Result); T3b design added 2026-10-08, Codex round 4: CONVERGED · continues on `wip/icebar-build` from `6c61b96`.
Follows the owner's corrected goal and Codex's consult of 2026-10-07
(`~/IceReverse-evidence/20261007-213730-t7/codex-consult.md`, handover beside it).
Supersedes, where they conflict: `2026-10-03-icebar-build.md` sections 1, 3 (the
"clean = no `«`" rule, the long-menu and all-or-nothing rules) and its T7/T8, and
`2026-10-07-icebar-menu-frame-fix.md` as a way of working. Labels: MEASURED (file:line
or run id), INFERRED, TBD.

## 0. Goal (the owner's words, 2026-10-07)

Not "items that do not fit are pushed off the bar without `«`". The owner picks, by
taste, some status items to keep hidden inside Ice, **also when the bar is not crowded**;
Ice's icon opens the IceBar listing them; clicking one opens that app's menu; the owner
chooses the members. `«` is not the problem to solve: when hidden items are put back,
many items overflowing with `«` is natural, few items show none.

Success = the chosen items are kept in Ice and reachable there. Not = "no `«`".

Non-goals: certification; macOS 26 and earlier (unchanged); a second display; live item
images (accepted: app icon, monochrome).

## 1. What today established (evidence, not to be re-derived)

| # | Fact | Grade |
|---|---|---|
| P1 | Seven owner sittings in `icetest` on 2026-10-07; none reached `active` | MEASURED (runs `20261007-012252` ... `-213730`); "one defect per sitting" is a reading of them, INFERRED |
| P2 | With a never-seen bundle id (`com.icespike4.ice`): divider x 1469, Ice's icon middle 1297.5 (left of it), both reference helpers right of both, two unnamed Apple items left of the divider | MEASURED (`20261007-213730-t7/references.txt`). That the divider and helpers "landed by their seeds" and the icon's 0.1 was lost or ignored: INFERRED until the values are read at creation (S1); cause TBD |
| P3 | The helper rehearsal that predicted otherwise used separate processes and ordinary-length items; Ice creates three items in one process with `statusItem(withLength: 0)` then `autosaveName` (`ControlItem.swift:68-71`, `MenuBarManager.swift:54-58`) | MEASURED (code); that this difference is the cause: INFERRED |
| P4 | macOS 27: a preferred position of 0 reads as none; positive values order from the right, smallest rightmost; MenuBarAgent remembers dragged positions per `status:<bundle id>::<autosave name>` (for our ad-hoc helpers the process name stands there instead, and undragged items are recorded too: T2b, 2026-10-08) outside the app's defaults, and they override an app seed | MEASURED (owner's account probes; the store file) / INFERRED (the override) |
| P5 | The detector's baseline refuses without a "reference" (an identifiable item between Ice's divider and icon, `CheckPlan.swift:47-80`) and unless every hidden-section member is covered (`HiddenLengthObserver.coverage`) | MEASURED (code; run `-182404`) |
| P6 | A length counts as hiding only if no `«` is listed and every member is checked gone (`HiddenLengthOutcomeRule.swift:11-18`); a `«` at rest shows the section again (`IceBarHidingCoordinator.swift:141-153`); a long frontmost menu shows it (`IceBarHidingMachine.swift:255-262`) | MEASURED (code) |
| P7 | Membership = everything left of the hidden divider (`DiscoveredCachePlan.make`); in `icetest` Apple's input menu and `com.apple.campo` (basis `unnamed`) became members beside the helper | MEASURED (code; `references.txt`) |
| P8 | T0: a spacer of 632-840 pt pushes k = 1, 2, 4, 8 helper items off the bar with no `«`; an AX press on a pushed-off helper opens its menu 5/5 at 736 | MEASURED (`20261004-105226-spike`), for sacrificial helpers, short and mid menus, this display and arrangement only; FINDINGS "Where this leaves the plan" rejects a fixed constant without transfer proof |
| P9 | AX frames alone do not tell "drawn" from "overflowed": an overflowed item keeps `y < 40`, stacked on its neighbours (FINDINGS "Two different kinds of not visible", "AX frames cannot carry this") | MEASURED (FINDINGS) |

Codex's verdict on these (consult, sections 2-4): the physical mechanism of route C
(P8) is worth keeping; the runtime built on it (calibration tied to a capture /
reference / no-chevron certificate, P5-P6) is too complex and aimed at the wrong
target; `icetest` sittings are for final acceptance only, not for development.

## 2. Way of working (binding for every later step)

- R1 No owner sitting until the acceptance gate of step S5. Nothing is called working on
  the strength of a stand-in whose lifecycle differs from Ice's (P3).
- R2 Every deliverable passes Codex before it is reported: this plan (plan review,
  debate recorded in the Appendix), code (`/simcodex`, full loop), decisions (`thecure`).
- R3 A claim to the owner states what was measured and what was not; never "should work".
- R4 Independent work is dispatched in parallel.
- R5 Each session ends by itself at a sensible boundary: commit, push the `wip/` branch,
  the next start command.

## 3. Steps

### S1 A trace mode in Ice itself (owner cost: none)

- Not a copy of the lifecycle (round 1, P0: `ControlItem`'s storage is lazy and
  `performSetup` installs publishers that create the item and drive state and
  visibility, `ControlItem.swift:144, 189-352`; a copy would again be a stand-in that
  differs from Ice). The mode lives in Ice's own sources, off unless the launch
  argument `-IceLabTrace YES` is given, and is only ever staged under a disposable lab
  bundle id.
- What is traced, said exactly (round 2): **the IceBar-mode creation lifecycle with
  uncalibrated dividers** -- `UseIceBar` on, the hiding coordinator not started, so the
  hidden divider is at standard length by the real code path
  (`ControlItem.iceBarLength`, `calibratedLength ?? Lengths.standard`,
  `ControlItem.swift:459-486`), not by an override. That is the state T7 starts Ice in.
  It is not a trace of an ordinary (non-IceBar) launch, where `.hideSection` means
  10,000 pt (`ControlItem.swift:35-56`), and proves nothing about one.
- The bootstrap, exactly (rounds 3-4): `AppState` is constructed as always; trace mode
  then sets, in memory only, `general.useIceBar = true`, `general.showIceIcon = true`
  and `advanced.enableAlwaysHiddenSection`, and calls **only**
  `MenuBarSection.performSetup(with:)` on the three existing sections, which assigns
  the app state and calls `ControlItem.performSetup` (`MenuBarSection.swift:146-150`,
  `ControlItem.swift:189-347`; the settings and sections exist once `AppState` is
  constructed, `AppState.swift:19-29`). A clean domain would otherwise load
  `useIceBar` false and take the 10,000 pt path (`GeneralSettings.swift:32, 85-90`,
  `ControlItem.swift:459-470`).
- Two variants, both run: `enableAlwaysHiddenSection` **off** (what T7 runs, and the
  state P2 was seen in: setup then removes the always-hidden control item,
  `ControlItem.swift:308-324`, and that removal is part of the lifecycle under test;
  two items end on the bar) and **on** (three items on the bar).
- Not called: `AppState.performSetup`; `AppSettings.performSetup` (it starts hotkeys,
  which register global listeners, `AppSettings.swift:24-28`, `Hotkey.swift:43-52`) --
  if the three values cannot be set without it, that is settled in the code review
  with Codex, not assumed; `MenuBarManager.performSetup` (three panels and manager
  observers, `MenuBarManager.swift:67-76`); the item manager, the hiding coordinator
  (`MenuBarItemManager.swift:121`), HID taps, image cache, appearance, updater,
  notifications, `AppDelegate`'s menu and cursor changes (`AppDelegate.swift:16-40`).
  Two things `AppState`'s construction itself starts are dealt with by name: the
  permission polling (`Permission.swift:65-79`) is stopped at once
  (`permissions.stopAllChecks()`, as the normal setup does), and the macOS 27
  menu-bar-owner observer (`AppState.swift:65-68`) is left, as it only reads.
- Ice logs the bundle id and, for each control item, the **three** status-item keys it
  writes (`Preferred Position`, `Visible`, `VisibleCC`, `ControlItem.swift:721-767`) at
  five points (before seed, after seed, after `statusItem(withLength:)`, after
  `autosaveName`, after the first main-queue turn), names the two stores a position
  lives in (the app's defaults; MenuBarAgent's `TrailingItemPreferredPositions`) with
  the lab identity's entry in each, then the AX frame of every control item that is on
  the bar; then it quits (10 s cap).
- What it does touch, stated: it adds three status items of the lab identity for a few
  seconds, which reflows the bar while they are there (as a helper does), and it writes
  the lab identity's own defaults and, possibly, MenuBarAgent's record for that
  identity. Guard: the owner's entries in MenuBarAgent's store
  (`TrailingItemPreferredPositions`) are read before and after; any change outside the
  lab identity fails the run and is reported.
- Proves: where the icon's 0.1 is lost or ignored (P2). Does not prove: anything about
  expanding a spacer.
- DoD: a pure, tested rule for what trace mode starts (IceCore); the trace from a clean
  domain, 3 of 3, with the five-point values recorded and the store guard passing. If
  it does not reproduce P2's layout in the owner's account, that is recorded and the
  same trace becomes the lab's first scenario (S4).

### S2 Fix placement, and a repair for remembered positions (owner cost: none)

- Fix only what S1's trace shows. Re-run `trace` from a clean domain: divider | (visible
  section) | icon, 3 of 3.
- Remembered positions (P4): the harness measures, with its own items, that a dragged
  layout persists across relaunch and that a seed does not override it (the drag by the
  event-injection probe on a harness item only, after reading `probes/README.md`'s side
  effects; else recorded as not measured).
- Product: Ice detects its icon left of its hidden divider at start and on layout
  change and says so in the layout pane with the repair ("Command-drag Ice's icon to the
  right of the divider"); it does not hide anything in that state. Pure rule in IceCore,
  tested.
- DoD: unit tests; `trace` 3 of 3; the inverted state shown, not silently broken.

#### S2 design (T2, added 2026-10-07 after T1; review in the Appendix, "T2 design")

What T1 measured, and what it changes (run `20261007-231100-cM6U06-trace`, owner's
account, 26A434; STATUS "Ice's trace mode"):

| # | Fact | Grade |
|---|---|---|
| E1 | From a never-seen identity the seeds held at all five points (icon 0.1, hidden 1) and both items landed right of every other status item Ice could have listed: hidden divider x 1492, icon x 1508, 6 of 6 (+12) | MEASURED |
| E2 | The always-hidden divider, which gets no seed (`ControlItemPositionSeed.swift:31-32`), landed at x 1009, left of everything, 3 of 3 | MEASURED |
| E3 | So here the defect is not P2 (icon left of divider) but the opposite of section 5's aim: with the divider at the far right, every other item is left of it, a hidden-section member by default | MEASURED (E1) + code (`DiscoveredCachePlan.make`) |
| E4 | MenuBarAgent's `TrailingItemPreferredPositions` holds what look like distances from the bar's right end in points (`module:Clock` 0.0; this account's release Ice: icon 361.5, divider 465); 69 entries, among them never-dragged probe helpers of earlier dates, so the agent records positions without a drag at some point; in T1's 3 s lifetimes it recorded nothing | MEASURED (the store, T1's guard) / INFERRED (the unit; "without a drag") |
| E5 | The release Ice's own defaults hold real coordinates (`Preferred Position` hidden 465, visible 432), not seeds: AppKit rewrites the app's value at some point | MEASURED (`defaults read com.jordanbaird.Ice`, read only) |

T2 is three steps, each with its own `/simcodex` before it is reported: T2a the seed
and the trace's oracle; T2b the remembered-position measurement; T2c the notice and
the gate. Serial (each needs the one before); nothing is dispatched.

**T2a The seed (macOS 27 only; 26 and earlier byte-for-byte as now).**

- The change: the hidden divider gets **no seed** when nothing is
  stored, as the always-hidden divider already does (E2: an unseeded control item of
  Ice's own lifecycle lands leftmost). The icon keeps 0.1 (E1: rightmost of the
  status items). Expected: `[always-hidden divider] hidden divider | others | icon`.
- A stored value is never touched, a stored 1 included: its provenance cannot be
  told from the number (review round 1). The rule keeps its shape,
  `ControlItemPositionSeed.seed(for:stored:isMacOS27:) -> Double?`; the only change
  is that `.hidden` on 27 returns `nil`. `ControlItem.preflightSetup` is not edited.
  An identity that already stored the old seeds keeps E3's layout (the icon's 0 is
  re-seeded to 0.1 as today, the divider's 1 stays): T2 does not change it, and
  STATUS says so; the owner's repair there is a Command-drag of the divider.
- With the always-hidden section on, two unseeded dividers are created in the order
  hidden, always-hidden (`MenuBarManager.swift:53-57`, set up in that order by trace
  mode and by `MenuBarManager.performSetup`). That each new unseeded item lands left
  of the one before is INFERRED; the oracle below measures it.
- The oracle (`trace-tool.py summary`, per run; the layout verdict replaces T1's
  icon-versus-divider one):
  1. `icon.midX > hiddenDivider.minX` (IceCore's boundary, `PreferenceHidingPreconditions`);
  2. `othersLeftOfHiddenDivider == 0`, counting what D-a could make a member: an
     item on the bar (`.onBar` or `.stacked`) whose mid-x is left of the divider's
     minX. A `.parked` or frameless item is counted apart (`othersUnplaced`) and
     never judged: it is not on the bar, the divider cannot carry it, and D-a never
     selects it. (Corrected 2026-10-08 after the first run, `20261008-001005-7X98U1-trace`:
     the first wording counted three parked items, frames at x -1 to 7, y 1104, at
     the screen's bottom left, as "left"; the ten on-bar items were all between.
     Re-reviewed by Codex, Appendix.)
  3. `othersBetween >= 1` (the bar here has other status items; 0 would mean the
     read saw nothing and proves nothing);
  4. variant `on` only: `alwaysHiddenDivider.minX < hiddenDivider.minX`;
  5. every control item `isAddedToMenuBar` with a usable frame (not overflowed, not
     under the notch; for the icon, its discovered position on the bar, not only its
     frame -- Codex code review, T2a), the discovery pass `complete`, the store guard passing.
  6. (added 2026-10-08, Codex's re-review of clause 2) none displaced: a discovery
     pass taken **before** any control item exists (a fourth trace step,
     `.readBaseline`) counts the other items on the bar; the judged pass must count
     the same number, so a leftmost divider that pushed an item off the bar fails.
     The baseline must be a complete pass; it is read up to two times, a gap apart,
     because a process's first pass is often incomplete (STATUS "Discovery keeps
     up"; run `20261008-004012-dze20T-trace` failed 6 of 6 on a single incomplete
     baseline with the layout unchanged). The cap is 20 s for it.
  `othersRightOfIcon` is recorded, never judged (Apple's modules sit there).
- One snapshot, not two reads stitched together (round 1): after the settle, trace
  mode runs Ice's own discovery entry point (`MenuBarItem.discoverItems(previous:)`,
  `MenuBarItem.swift:375`; read only, as every Ice does once a second) **twice, 1 s
  apart**, and emits per pass, from that pass's `DiscoveredItemSet` alone: the three
  control-item frames, the count of other items per region, `completeness`,
  `ownRead`: numbers, no names. The oracle is judged on the second pass and holds
  only if both passes agree on every frame and count; otherwise the run is
  `indeterminate` and counts as failed. This is `LabTracePlan.readings`
  (`.ownExtras`, `.discoverTwice`; as built, a list of its own beside `steps`,
  which stays "what a trace launch starts"), unit-tested in `LabTraceRule`; the
  item manager itself is still not started. T1's own-extras read and five-point values stay as they are.
- Decision rule, fixed before the run: the change is kept iff the oracle holds 3 of
  3 in both variants (`run-trace.sh <app> <scratch> 3`). If **any** clause fails in
  any run, the seed rule returns to T1's, the failing clause and frames go into
  STATUS, and the fresh-install layout is reported to the owner as an open defect:
  T2c does **not** cover it (a divider right of the other items is a layout Ice
  cannot tell from one the owner chose). No second candidate (explicit large seeds
  were considered and dropped: whether a value beyond the bar is honoured is
  unknown, and it would be a second production path, round 1) without a new plan
  review.
- Exception, recorded 2026-10-08 after T3b (thecure with Codex, converged; the owner
  confirmed): the rule above was T2a's acceptance gate, and T2a passed it (6 of 6, both
  variants, runs `20261008-092213-WTCPNh-trace`, `-092507-liCEDD-trace`). A later
  failure of clause 4 alone -- both dividers read at one frame, x 981, 3 of 3, also
  with the build before T3b (runs `20261008-100625-RDzm4C-trace`, control
  `20261008-100830-3EZ9B3-trace`) -- is not answered by the revert, which would bring
  back E1/E3 for both variants to address one. It is an open defect, **T2d**, to be
  investigated under its own plan review; it does not block T4. S4 scenario 7 measures it.
- Limits stated in STATUS: measured in this account only (P2's `icetest` layout is
  still unexplained, S4 scenario 1); a later-installed app's new item lands leftmost
  too (INFERRED from E2), so left of the divider, a member by default until the
  owner moves it; on a crowded bar the leftmost slot may be overflowed, and Ice then
  reports the divider unusable (D-c a) instead of hiding.

**T2b Remembered positions, measured with the harness's own items only.**

- Items: `vzhelper --items 1 --autosave <fresh name per run>` staged under
  `com.icespike4.target` (the dragged one, T) and `com.icespike4.protected` (the
  anchor, P), both ad-hoc signed copies as `build.sh` makes them, lifetime-capped,
  controlled over stdin. Nothing else is dragged, clicked or resized.
- Questions, each answered or recorded "not measured" with the reason:
  Q1 does MenuBarAgent record an undragged item, and when (read at 3 s, 30 s, after quit);
  Q2 after a Command-drag of T across P: the agent's entry for T, and T's own
  `NSStatusItem Preferred Position <name>` default, before and after;
  Q3 T quit and relaunched: is it back in the dragged slot;
  Q4 T relaunched with a contradicting seed written to its own defaults (0.1): the
  answer is the tuple (MenuBarAgent's entry, T's own default, T's side of P), each
  read three times 1 s apart after the store has settled as `run-trace.sh` settles
  it; "the remembered slot wins" or "the seed wins" only if all three reads agree,
  else inconclusive. Q3 is read the same way.
- The drag: a new one-shot probe `probes/dragown.swift`, derived from `inject3.swift`
  (FINDINGS "The move primitive": 3 of 4, the miss a drop-point error with foreign
  items in between). Side effects (README's column for `inject3`, read 2026-10-07):
  synthetic mouse and Command events in the owner's session and a moved cursor for
  about 2 s. That the drag is run at all, in this account, on harness items, is the
  owner's instruction for T2; what guards it (round 1):
  it refuses unless T and P are both found by identifier under `com.icespike4.`,
  are adjacent (gap <= 2 pt, so the path crosses only P), both on the bar, and no
  hardware input arrived for 5 s (`CGEventSource.secondsSinceLastEventType` on
  `.hidSystemState`, which the probe's own session-tap events do not reset);
  before **every** posted event it re-reads that counter and re-resolves T and P
  from scratch (bundle id, the pid first seen, identifier, on the bar, adjacent,
  frames as first read), and on any hardware input, any mismatch or an unreadable
  element it releases the button and Command at
  once, restores the cursor and ends as `aborted`; a watchdog and a `defer` release
  both in every other exit. (Corrected while building, 2026-10-08: "frames as first
  read" and "adjacent" hold only until the button is down. A drag is the frames
  changing: T follows the cursor and P gives way, so the literal rule would abort
  every drag. After the button is down each event still re-checks the hardware
  counter, the pid's bundle id and the one item of that identifier in it. And
  "gap <= 2 pt" is not what adjacent AX frames show: the helpers' frames (14 pt)
  are inset 7 pt in their 28 pt windows, so touching windows read as a 14 pt gap
  (MEASURED, the helpers' own `frames` beside `dragown read`, 26A434); adjacent is
  a gap of 14 +- 2 pt. The runner also waits, up to 90 s before each of the three
  attempts, for the 5 s without hardware input. Put to Codex in T2b's code
  review, Appendix: all three accepted. From that review, also: P is launched
  first, so T, a new item, lands left of it (MEASURED, 2 of 2 smoke reads) and is
  dragged to P's **right** -- a relaunched T on the left would be a fresh
  placement, not a kept slot, so a slot on the left proves nothing; the seed's
  place (0.1, rightmost) is right of P too, so Q3's and Q4's reads carry a fourth
  value, whether T is beside P, and T's x. The slot is "beside P on its right":
  Q3 says kept only for that (right but not beside: elsewhere; left: lost). Q4
  needs Q3's kept slot as its control and says "the remembered slot wins" for
  beside P, "not the slot, and where the seed would put it" for right but not
  beside -- never "the seed wins": a placement that is not the slot does not show
  what put it there (Codex, round 2) -- and "neither" for left. Before the press the element at the press point must be T's
  process's and the one at the drop point T's or P's (an AX hit test: nothing
  covers the bar there); the button and Command are let go under one lock that
  every post takes, by the watchdog and the signals too; `dragown release` is the
  runner's fail-safe for a `dragown` that died.) No countdown or confirmation: the run is unattended by
  the owner's choice. A refusal or abort is "not measured"; at most 3 attempts.
- Runner `run-remembered.sh <apps dir> <scratch>`: preflight (no helper already
  running, both defaults domains empty), the four questions, the store read as
  `run-trace.sh` reads it, T1's store guard on every read (only the two helper
  identities' entries may change; anything else stops the run), 3 runs. Evidence in
  `~/IceReverse-evidence/<run id>-remembered/`. Left behind, and said: MenuBarAgent's
  entries for the two helper identities (the store is not ours to write; it already
  holds such entries, E4). The helpers' own domains are deleted and verified empty.
- The result changes no code path: it decides the wording of STATUS's "remembered
  positions" row (MEASURED instead of INFERRED) and whether the notice's repair text
  can promise that a drag sticks.

- Result (2026-10-08, run `20261008-081444-y8GnWW-remembered`; STATUS "Remembered
  positions"): Q1 measured once -- no entry at about 4 s, one for each undragged
  helper item by 30 s, keyed by process name (`status:vzhelper::...`), not bundle
  id; Q2-Q4 **not measured**: at that moment MenuBarAgent also changed 15 of the
  owner's existing entries, and the guard stopped the run before any drag. T2b did
  not complete its three runs; the persistence question stays INFERRED. Decided
  with Codex (thecure, 2 rounds, "no objection" on the whole): the guard is not
  relaxed and nothing is rerun without the owner's yes; the guard and the lookup
  use the run's two exact keys; T2c goes on, its notice promising nothing about
  persistence (the converged wording does not). Codex's rulings against the first
  proposal, both taken: no "ad-hoc means process name" rule (an observation, the
  rule unknown); no `status:vzhelper::` prefix (it would allow other helpers'
  entries). Conceded by Codex on the store's evidence: the installed Ice is keyed
  by bundle id, so a `status:Ice::` collision would be among lab copies only.

**T2c The notice and the gate (macOS 27, IceBar mode).**

- One definition of "right of": `PreferenceHidingPreconditions.misplacement` becomes
  the public `iconPlacement(icon: DiscoveredItem?, divider:) -> PreferenceHidingIconPlacement?`
  (done in T2a; as reviewed there, it and `evaluate(iceIcon:)` take the discovered
  item, not a frame: an icon that is not on the bar, parked or frameless, is
  `.iconUnreadable` whatever its frame says, so the notice below never asks the
  owner to drag an icon that is not on the bar).
- New pure rule `IcePlacementNotice.notice(placement:isIceBarMode:isDragging:)`:
  `.iconLeftOfDivider` in IceBar mode and not during a drag gives the notice; every
  other input gives none. An unreadable icon or unusable divider is **not** reported
  as inverted (Ice did not see an inversion; T3b's `blocked` state names those).
  The text lives beside the rule, as `IceBarHidingStatus.message` does: "Ice's icon
  is left of its hidden-section divider, so Ice hides nothing. Hold Command and drag
  Ice's icon to the right of the divider."
- Wiring: `MenuBarItemManager.cacheDiscoveredItems` (27 only) evaluates the rule on
  each discovery pass it publishes and publishes the notice (as built, after the
  code review: it publishes the icon's placement, held from the last pass whose
  hidden boundary was trusted -- a divider at a hiding length does not draw the
  boundary at its left edge -- and the pane applies the rule to it); a pass is skipped for
  1 s after a move (`MenuBarItemManager.swift:542-545`), so the notice follows a
  change by up to that plus one pass. The layout pane shows it as a line above the
  bars, beside `hidingCheckStatusLine`.
- Gate, in the machine (round 1: `boundaryUsable` is read only when a baseline
  starts, `IceBarHidingMachine.swift:294`, and `.resting` ignores samples, `:269`):
  `IceBarHidingSample` gains `iconLeftOfDivider: Bool`, and `blocker(in:)` returns a
  new `IceBarShownReason.iconLeftOfDivider` for it **first**, so from every phase,
  `.resting` included, `enterShown` emits `.setLength(nil)` then the report
  (`:382-386`); when it clears, the machine re-enters quiet as for the other
  blockers. Its status line is the notice's text. Unit-tested per phase. This is
  the one edit to the machine T3b will retire; T3b's `blocked` state replaces it.
- Seen live, and what is not: a third trace variant `inv`: the runner writes the
  lab identity's icon default to a large value before launch (the one deliberate
  exception to the clean-domain check), trace mode emits the rule's verdict from
  the discovery pass's frames, and the oracle expects `iconLeftOfDivider` with the
  notice. Its gate, said exactly (round 2): the three `inv` runs must complete
  (trace complete, two agreeing passes, store guard); whether the stored value
  produces an inversion is a diagnostic, not a gate -- if none of the three is
  inverted, that is recorded and the rule stays unit-tested only; but a run that
  **is** inverted (`icon.midX <= divider.minX` in the pass's frames) and does not
  carry the notice fails T2c. `inv` proves the rule on real
  frames, **not** the wiring: trace mode starts neither the item manager nor the
  coordinator. Publication after start and after a placement change, and the
  retired length, are proved live only in the lab, as a new S4 scenario (14: the
  icon left of the divider at start, and moved there while hidden: blocked, the
  notice, no length applied); a full Ice under a lab identity is not started in
  the owner's account for it (S1's not-called list, R1). Until then: INFERRED
  (code and unit tests), and reported so.

Tests: IceCore unit tests first (the seed on 27 and 26's unchanged values; notice;
the machine's new blocker from every phase; `LabTraceRule`'s new step), coverage >= 80 % of changed IceCore files;
`test-trace.sh` for the new oracle and the remembered-store classification on
synthetic input; `xcodebuild` Debug build; `check-a3a4.sh` (frozen files untouched);
E2E = `run-trace.sh`: the placement oracle 3 of 3 x (off, on), `inv` 3 runs under
its own gate above; and `run-remembered.sh` in this account. No probes Swift package source changes, so no full probes test run.

Touched: `Packages/IceCore` (seed, preconditions, notice, machine blocker, trace rule +
tests); `Ice/` (`LabTrace.swift`, `MenuBarItemManager.swift`,
`IceBarHidingCoordinator.swift`, `MenuBarLayoutSettingsPane.swift`); probes
(`run-trace.sh`, `trace-tool.py`, `test-trace.sh`, new `run-remembered.sh`,
`dragown.swift`, README rows); `STATUS.md`. Rollback: revert the T2 commits; the
seed rule's 26 path is untouched.

### S3 Re-aim the hiding rule (owner cost: none)

- D-a **Members** (thecure 2026-10-07, section 5). Items left of the divider:
  `.declared` and `.unnamed` ones are members -- listed in the IceBar, and pressable
  while they are uniquely addressable in the current Accessibility read
  (`PressTargetRule.swift:12-20`; the pixel check can target both, `CheckPlan.swift:36-45`);
  a member that becomes ambiguous or unreadable stays listed, marked stale, its cell
  disabled, and caps the state at `not verified`. A member whose position is `.stacked`
  stays a member, listed and pressable, and also caps the state at `not verified` (the
  pixel check skips it). A `.positional` item (an identifier shared within its process)
  left of the divider **blocks hiding**: Ice names it and asks the owner to move it to
  the right of the divider -- its press is resolved by child index with only an
  identifier-at-index recheck, so a reorder between discovery and click can open a
  sibling's menu. Parked, frameless or non-AX records never become newly selected
  members; the explicit stale-state rule for a previously known member is written in
  T3a. What Ice cannot see at all it cannot protect: a limit stated in `STATUS.md`,
  mitigated by the complete-pass precondition of D-c. No promise that membership
  survives a restart until the restart-identity experiment of S4.
- D-b **`«` is recorded, never a trigger.** It neither vetoes a length nor shows the
  section at rest.
- D-c **Four states, said honestly** (rounds 1 and 3):
  `blocked, not attempted` -- Ice changed no length and offers no IceBar, because a
  precondition of any hiding failed: (a) Ice's icon is not right of its hidden divider
  (S2); (b) the discovery pass behind the roster is not complete (an unseen item could
  be carried off and be unreachable; "complete" is `Completeness.complete`, defined
  concretely in T3a); (c) a `.positional` item is left of the divider. The pane names
  the reason and, where there is one, the item to move;
  `verified hidden` -- every member was observed absent from the bar by the pixel check;
  `hiding requested, not verified` -- Ice applied a length and could not check (no
  reference, capture refused); the pane says exactly that, the IceBar is offered, and
  this state never counts as success in S4/S5;
  `visible / failed` -- a member was observed drawn; Ice says so and does not claim to
  hide.
- D-d **No shipped constant.** 736 pt is the first length the lab probes (P8), not a
  default. In `verified` mode a length is kept only after every member is observed
  absent; below the band a member may be folded behind `«` (not a failure, but not proof
  of absence either), above it the member is drawn again (FINDINGS "The safe width").
  When Ice cannot verify, it hides best effort in the unverified state above; there is
  no strict-mode setting (section 5).
- D-e **Layout changes** (frontmost app, menus crossing the notch, items added): the
  requested set is kept, the state drops to `not verified` and is re-checked; nothing is
  shown merely because a menu is long.
- D-f **Pressing.** An item is supported in the IceBar only while it is uniquely
  AX-addressable; a successful AX call is not proof a menu opened
  (`PressTargetRule.swift:22`), so unsupported items are marked before, not after, a
  press fails, and the lab verifies the helper's own menu-open signal.
- Frozen files stay frozen (`check-a3a4.sh`); the pixel check is used as a verifier of
  absence, not as a no-chevron certificate.
- Two tasks (round 2): T3a, the rules as pure IceCore types with unit tests, may start
  beside S1; T3b, wiring them into the live machine and coordinator, waits for S2 (the
  inverted-layout gate must exist before any live hiding).
- T3b must retire, not sit beside, the machine's old triggers (T3a review, 2026-10-07,
  altitude F3): `HiddenLengthOutcomeRule` reading `chevronListed` as `.folded`, the
  machine's `chevronSeenAtRest` re-calibration and its `.crossesNotch` -> `.shown(.longMenu)`
  path all contradict D-b and D-e. The machine stays the single owner of "a length is
  applied" (`lengthApplied` is derived from its phase, never set separately) and records
  the chevron reading itself (the state rule has no chevron input). Layout changes are
  derived from `LayoutSignature` differences, not classified by hand. Membership is read
  only through `PreferenceHidingMembership.resolve(set:hiddenDividerState:previousMembers:childIdentifiersByPID:)`,
  never from `CachePublication.hidden`, which drops always-hidden and parked items and is
  empty until a divider has settled. The roster advances only from a pass whose divider
  boundary `DiscoveredCachePlan` would trust (collapsed, settled, unchanged during the
  pass, own read ok): a released member is dropped for good, so one read taken while
  the divider moves must not release it (T3a review round 2, altitude F2; enforced in
  `resolve(set:...)` itself after Codex round 3, which freezes the roster otherwise). A precondition
  that fails while a length is applied (a positional item appears, a pass is incomplete,
  the icon moves): the machine retires the length first, then the pane shows `blocked`
  -- `blocked` promises that no length is changed (T3a review round 3).
- DoD: unit tests per rule (TDD, coverage >= 80 % of changed files); `/simcodex`.

#### S3 design (T3b, added 2026-10-08 after T2; review in the Appendix, "T3b design")

Goal: the live machine and coordinator decide by T3a's rules and nothing else. Non-goals:
any new rule of membership beyond G1 below; a live run (R1: S4); macOS 26 and earlier;
the non-IceBar hiding check (`HidingVerifier`), untouched. Serial; nothing dispatched.

What the code does now, and what contradicts S3 (all MEASURED, code):

| # | Now | Against |
|---|---|---|
| N1 | any signature change, a frontmost-app switch included, puts the section back and re-baselines (`IceBarHidingMachine.swift:257-261`) | D-e |
| N2 | `.crossesNotch` and `.unreadable` menus show the section (`:272-276`) | D-e |
| N3 | a listed `«` is `.folded` (`HiddenLengthOutcomeRule.swift:14`) and, at rest, re-calibrates (`:227-230`, `IceBarHidingCoordinator.swift:142-155`) | D-b |
| N4 | a baseline that does not cover every member, or a walk without a band, ends `shown(...)`: Ice hides nothing | O1 |
| N5 | members are `itemCache[.hidden]` (`IceBar.swift:284`, the coordinator's signature and section map) | D-a, S3's "never from `CachePublication.hidden`" |
| N6 | no caller of `PreferenceHidingMembership`, `PreferenceHidingPreconditions`, `PreferenceHidingStateRule` outside tests | S3 |

**The machine (`IceBarHidingMachine`, rewritten in place; the calibrator is not changed).**

- Sample: `signature`, `preconditions: PreferenceHidingPreconditionResult`,
  `membership: PreferenceHidingMembership`, `isInteracting`, `isDragging`,
  `boundaryUsable`. Gone: `menuVerdict`, `iconLeftOfDivider`.
- Events: `mode`, `sample`, `baseline(token:ok:)`,
  `observed(token:checks:chevronListed:)`. Gone: `chevronSeenAtRest`.
- Phases: `off`; `blocked`; `quiet(since:)`; `baselining` -- all three at standard
  length: entering `blocked` or `quiet` from a phase with a length set emits
  `.setLength(nil)` first, as `enterQuiet` and `enterShown` do now (`:391-401`);
  `calibrating` (as now); `settling(trial, kind)` -- the one observation at a length Ice
  means to rest at, `kind` = `.lastGood` (not clean: the walk starts from that
  observation, as `confirming` does now) or `.final` (rest whatever was seen);
  `resting(Rest)` with `Rest` = length, the checks of its last observation, the chevron
  reading, the pending layout change and when it came, the re-check under way.
- Two computed properties, neither stored. `lengthSet`: the phase holds a non-nil
  length (a trial, a settle, a rest) -- what `blocked` must retire first.
  `lengthApplied`: the phase is `.resting` -- the rule's input and what offers the
  IceBar. Every unverified rest is a rest, so D-c's "the IceBar is offered" holds for
  it. Not offered during a trial or a settle (review round 2, P1, taken in part): a
  presented IceBar is `isInteracting`, which ends the observation
  (`IceBarHidingMachine.swift:294-297`), and such a length lasts one settle (about
  1 s) before it is a rest or is retired. Not offered at standard length either,
  though the rule's `isIceBarOffered` is true for every state but `blocked`: the
  members are on the bar there and the IceBar would list them twice
  (`IceBarHidingCoordinator.swift:73-76`). The status is
  `PreferenceHidingStateRule.evaluate` on the last sample's preconditions and
  membership, that flag, the rest's checks and pending change -- a computed property;
  after every event the machine appends `.report(status)` iff it differs from the last
  one reported, so a report can never precede the `.setLength(nil)` of the same step.
- Order within a sample: (1) a drag -> quiet (as now); (2) preconditions blocked ->
  `blocked`, `.setLength(nil)` first if any length is set (trial, settle or rest);
  (3) signature difference, classified by the one new pure function
  `PreferenceHidingLayoutChange.between(_:_:)`: **structural** (an item list or the
  display differs: the roster may be wrong, and it advances only at standard length)
  -> quiet from any phase; **soft** (frontmost pid, menu edge, Space) -> while resting
  the length stays, the change is held as `pendingLayoutChange` (state: not verified)
  and after `quietPeriod` without interaction one re-check `.observe` is sent, whose
  checks replace the rest's and clear the pending change; in any earlier phase a soft
  change restarts the quiet period as now. The enum's cases become
  `displayChanged`, `itemsChanged` (structural), `frontmostAppChanged`,
  `menuWidthChanged`, `spaceChanged` (soft): the signature has no notch and cannot
  tell added from removed. A Space is soft because the signature's item lists are
  the roster's and the cache's: a Space that shows other items differs in those
  lists and is structural by them; the Space id alone says nothing about the roster,
  and treating it as structural would show the section on every Space switch (N1).
- From `blocked`, a sample whose preconditions are ok enters `quiet(since: now)`
  and waits out the quiet period, as a cleared blocker does now (`:286-288`).
- Start (from quiet, after `quietPeriod`): as now -- `boundaryUsable` included, which
  is false from the moment the divider's collapsed-ness changes until a pass has
  placed the sections by it (`MenuBarItemManager.swift:160-166, 595`), so no baseline
  is taken before a standard-length pass has resolved the roster -- and only with a
  non-empty roster.
  An empty roster stays quiet; the rule says `requestedNotVerified([.lengthNotApplied, .noMembers])`.
- After the baseline. `ok` (every ready member checkable): settle at the last verified
  length if there is one (`.lastGood`), else walk. Not `ok`: settle `.final` at the
  best-effort length. The walk's end: `.rest(L)` within the margins -> settle `.final`
  at L; give-up -> settle `.final` at the best-effort length. (Corrected while
  building: "or margins not met" went, with `restMargin`: the best-effort midpoint
  of a walk is the same L, so the check changed nothing; the settle's own
  observation decides the state.)
  **Best-effort length** = the last verified length, else the midpoint of the clean
  lengths this walk saw, else `calibration.defaultStart` (the injected parameter, no
  new literal). That value is 736 pt, the lab's first probe (P8): under O1 Ice must
  apply some length when it cannot verify, and this is the only one with any
  measurement behind it; a rest there without clean checks is
  `requestedNotVerified`, never a success (D-d). INFERRED that it hides anything on
  another bar.
- The walk's outcome per trial is `HiddenLengthOutcomeRule.outcome(checks:memberCount:)`
  over the **ready** members only (stale and stacked ones cap the state through the
  rule, they do not stop the walk); no chevron parameter. A check that saw the fold
  (`hidden(folded: true)`) is still `.folded` for the walk's direction: a per-member
  pixel reading (D-d), not the `«` listing. The chevron reading rides on every
  `observed` event, is stored in the rest, logged, and read by nothing.
- At rest nothing retries by a timer. Only: a re-check that sees a member drawn
  starts one new cycle (quiet -> baseline -> ...) if fewer than `maxFailures` cycles
  failed for this roster and display and `minInterval` has passed; otherwise the rest
  stays and says `visible / failed`.
- A stale baseline. `verify` answers `skipped(.baselineStale)` once the baseline is
  older than `BaselineReuse.maxAge` (600 s, `HidingVerification.swift:264-267`), and a
  baseline can only be taken with the section **shown** (`HiddenLengthObserver.swift:65-68`:
  the members' templates are what is later looked for). So a re-check then cannot
  verify without putting the members back on the bar for a cycle. The design: it does
  not; the length stays, the state stays `requestedNotVerified` until a structural
  change, a drag or a mode change runs a cycle anyway. Reason: D-e ("nothing is shown
  merely because a menu is long") and the goal (kept in Ice; not "certified"). Cost,
  said: in daily use, ten minutes after the last cycle a frontmost-app change leaves
  the pane at "not verified". The lab's scenarios are shorter than that.
- The stale reason (added 2026-10-08, thecure with Codex, the owner confirmed): a
  member's check `skipped(.baselineStale)` adds the not-verified reason `baselineStale`
  (placed after `captureRefused`; the member is still counted in `membersUnchecked`),
  so the pane says "the last check is more than ten minutes old" and the log
  `baselineStale`, instead of a generic "could not be checked".
- The per-signature length cache and `maxCachedLengths` go: a rest now survives the
  changes the cache was keyed by; `lastGood` remains.
- Retired with the above: `IceBarShownReason` whole; `IceBarHidingStatus`'s
  `checking / active / shown`. `IceBarHidingStatus` = `.off` or
  `.state(PreferenceHidingState)`, with `message` (the pane's line, item names
  allowed) and `logSummary` (case names and counts only).

**Lines the pane shows** (one per state; the first failing reason speaks):
blocked a `iconLeftOfDivider` -> T2c's text; a `iconUnreadable` -> "Ice's icon is not
on the menu bar, so Ice hides nothing. Turn on Show Ice icon, or make room for it.";
a `dividerUnusable` -> "Ice's hidden-section divider is not on the menu bar, so Ice
hides nothing."; b -> "Ice could not read every menu bar item, so it hides nothing
until it can."; c -> "Ice cannot tell <names> from another item of the same app, so
it hides nothing. Hold Command and drag it to the right of Ice's divider.";
verified -> "Ice Bar: the chosen items are hidden (checked)."; not verified with no
length -> "Ice Bar: getting ready to hide the chosen items." or, roster empty,
"Ice Bar: nothing is left of Ice's divider, so nothing is hidden."; not verified at a
length -> "Ice Bar: hiding requested, not verified (<why>)."; failed -> "Ice Bar: an
item meant to be hidden is still drawn on the menu bar." The notch clause of the
limits sentence goes.

**The roster and the preconditions (`MenuBarItemManager`, macOS 27, IceBar mode;
cleared outside it).** Each **completed** pass, before the cache plan's branch:
`PreferenceHidingMembership.resolve(set:hiddenDividerState:previousMembers:
childIdentifiersByPID:)`, then `PreferenceHidingPreconditions.evaluate`. A pass the
cache does not publish (`.keepPrevious(.permissionDenied)`,
`MenuBarItemManager.swift:623-629`) still updates the preconditions --
`discoveryIncomplete(.permissionDenied)` blocks and the machine retires the length --
and keeps the roster as it was (review round 2, P0). Calling `resolve` on a pass
taken while a length is set does not advance the roster: the divider is not
collapsed then, `DiscoveredCachePlan.evaluate` gives no boundary, and `resolve`
freezes -- no member added, none released (`PreferenceHidingMembership.swift:112-116,
130-142`). What such a pass may still change is a member's condition (ready to
stale: D-a, it caps the state) and, by G1, drop a member whose process has exited;
a dropped tag is an item-list difference, structural, so the length is retired.
Checks are matched to members by key and one for a non-member is ignored
(`PreferenceHidingStateRule.swift:24-26`), so an older rest's checks cannot speak
for a changed roster. Three things the rules need that do not exist:

- G1 **A member whose process has exited.** `missingFromRead` keeps it listed, stale,
  for ever, and caps the state for ever: after any member's app quits nothing is
  verified again and a dead cell stays in the IceBar. The wiring drops, before
  `resolve`, a previous member only on positive evidence that the process of its
  last read key no longer exists (`kill(pid, 0)` failing with `ESRCH`; pure
  `PreferenceHidingMembership.carried(previous:lastKeys:hasExited:)`, tested): a
  process that does not exist owns no status item, so nothing is carried off the bar
  unlisted. Not the pass's `enumeratedPIDs` (round 1: that list leaves out
  `.prohibited` apps, so absence there is not removal). A live process that is
  unread, quarantined or failing stays stale, as T3a wrote it; a reused pid reads as
  alive and keeps the member stale (the safe side).
- G2 **`childIdentifiersByPID`.** No pass exposes it. `DiscoveryResult` gains it as a
  required `init` parameter (round 1: no default; that init's own note), built in
  `MenuBarDiscoverer` from the admitted reads by pure
  `PressTargetRule.identifiers(of: RawRead)` (`nil` for a failed read, so the pid is
  absent = unreadable = not pressable). The eight sites that build a result say what
  they carry; five are probes Swift, so the full probes test run is owed (section 4).
- G3 **Precondition a at a hiding length.** There the divider's frame is not where
  the section boundary was (corrected while building, 2026-10-08: the design first said
  "starts off the bar"; T0's samples show a helper spacer at 634 pt read at minX 1229,
  inside the bar, its width running past the right edge, while the item it pushed off
  kept its frame at x 1201 -- MEASURED, run `20261004-105226-spike`, `samples.jsonl`;
  Ice's own divider is not measured). Read naively, the icon's side and the divider's
  usability would then say whatever that frame says, and a `dividerUnusable` would
  block, retire the length, hide again, for ever. `evaluate` gains an overload taking the held placement, and
  T2c's hold rule becomes `placement(held:read:dividerAtStandardLength:)`: at
  standard length (Ice's own divider state collapsed, settled, unchanged in the
  pass -- no longer "the reading was usable", so an unusable divider at standard
  length is now read and blocks) the read stands; otherwise the held value stands,
  except that an icon read as not on the bar is `iconUnreadable` at once (STATUS's
  first "not covered" row: an icon carried off with the section). The second row
  (Show Ice icon off) blocks by the same reading: on macOS 27 IceBar hiding needs
  Ice's icon on the bar. A limit, said in STATUS and by the pane.

The signature's `hidden` list is the roster's tags; `visible` and `alwaysHidden` stay
the cache's. The IceBar on macOS 27 lists the roster for either section it is asked
for (always-hidden items are left of the hidden divider too, and are members): a
member's item from the current set, else the last one read for its tag; its cell is
disabled when the member is not `isPressable` or its press failed.

**Coordinator.** Builds the sample from the manager's roster and preconditions;
`takeBaseline` passes a section map made of the roster's tags; `observe` returns the
checks and the chevron reading. `HiddenLengthObserver` keeps what `prepare` returned
also when it does not cover the section, so a best-effort settle reports each
member's real skip or refusal (`noReference`, `refusedAtBaseline`) instead of
nothing. `watchChevron` goes. `isIceBarOffered` stays "the machine is resting".

**T7's files.** `t7-lib.zsh` and `run-t7.sh` parse the retired statuses; T7 is
superseded (this plan's header). `test-t7.sh`'s block "what t7_summary reads is what
Ice's sources write" is removed with a note, the runner's README row says it reads a
grammar Ice no longer writes; the scripts themselves stay (S4 replaces them). The
new contract, `logSummary`'s exact strings per state, is pinned by IceCore unit
tests, for T4's runner to parse.

**Tests.** IceCore first, RED before GREEN: the machine per phase and per row N1-N4
(a soft change keeps the length; a long menu shows nothing; a listed `«` changes
nothing; an uncovered baseline and a failed walk rest best effort and say not
verified; every precondition from every phase retires the length before `blocked`;
a drawn re-check re-cycles at most `maxFailures` times; a stale baseline never
shows the section); `between`; the outcome rule; `message` / `logSummary`; the hold
rule; `carried`; `identifiers(of:)`. `MenuBarDetectorFeedTests` for the observer,
`MenuBarDiscoveryTests` for the new field. Coverage >= 80 % of changed IceCore
files. `xcodebuild` Debug; `check-a3a4.sh`; `test-t7.sh`, `test-trace.sh`; the full
probes test run (G2; in the background, logged, capped at 90 min). E2E:
`run-trace.sh` 9 of 9 as the regression of Ice's own start (trace mode starts
neither the item manager nor the coordinator, so it proves nothing of T3b's wiring).
The wiring itself is **not run live** before S4 (R1): INFERRED, and reported so.

Touched: `Packages/IceCore` (machine, outcome rule, state enum, preconditions,
notice, membership, press rule + tests); `Packages/MenuBarDiscovery` (result,
discoverer, observer + tests); `Ice/` (`IceBarHidingCoordinator.swift`,
`MenuBarItemManager.swift`, `MenuBarItemManager+IceBar27.swift`, `IceBar.swift`,
`LabTrace.swift` if the hold rule's label reaches it); probes (the five sites of
G2, `test-t7.sh`, README); `STATUS.md`. Frozen files untouched. Rollback: revert
T3b's commits; T2c's gate comes back with them.

Risks: a pass is often incomplete for a moment (STATUS "Discovery keeps up"), and
each such pass at rest retires the length for at least `quietPeriod` -- how often
on a real bar is not measured (S4 scenario 13 measures the block, not the rate);
the best-effort length on a bar unlike T0's.

### S4 A fixed lab matrix, foreground (owner cost: see O3)

- Default (round 1, P1): no agent and no cross-account control plane. The lab is the
  `icetest` GUI session **in front**, running one account-local, owner-staged runner
  with a baked-in list of scenarios: no arguments beyond a scenario id, no paths, no
  sourced files; staged bundle hashed as `run-t7.sh` does; evidence paths made by the
  runner. Whether a background (fast-user-switched) session can capture the bar and
  answer Accessibility is not known and nothing is built on it.
- Who starts it: O3. A second Mac logged into the lab account at its console would make
  it unattended; a VM serves logic and lifecycle tests only (no notch compositing).
- Matrix, each scenario with a machine oracle (round 1, P0), sacrificial helpers, the
  real Ice under the staged id: (1) sparse bar, one member; (2) k = 2, 4, 8; (3) press
  from the IceBar with the helper's menu-open signal; (4) add and remove a member;
  (5) no reference on the bar; (6) a `«` already present; (7) fresh and previously
  placed identity, with the always-hidden section off and on (2026-10-08, T2d): the
  always-hidden divider left of the hidden one, the pane's roster holding every member,
  and the cache's hidden and always-hidden sections together matching the roster --
  the hidden section non-empty only when a member lies between the two dividers;
  (8) frontmost app and long menus changing while hidden; (9) Ice
  relaunched (membership and identity); (10) a positional item left of the divider: blocked, nothing moved;
  (14) Ice's icon left of its divider, at start and moved there while hidden: blocked,
  the notice, no length applied (T2c);
  (11) a member kept visible on purpose must yield `visible / failed`, never `verified`;
  (12) a stacked member: `not verified`, the roster includes it; (13) an incomplete
  discovery pass: blocked.
- Outcomes are of three kinds and never mixed: **verified** (per-member visual
  absence, the IceBar's roster equals the members, the menu-open signal);
  **unverified best effort** (Ice applied an attempt and said so); **blocked** (the
  oracle: no divider length changed, nothing moved, no IceBar offered, the reason
  reported). Scenarios (10), (13) and (14) must end blocked; (5) and (12) must end
  unverified. Only verified scenarios count toward the
  DoD's "verified"; each of the others must match its expected kind in the same three
  runs, and is listed apart.
- DoD: every verifiable scenario verified three runs in a row; the report is generated,
  with the unverified ones listed apart.

### S5 Owner acceptance (owner cost: one short sitting)

Only after S4's DoD: one unattended command; then the owner looks at Ice on the bar
once (does the IceBar hold what was chosen; does a click open the menu).

## 4. Tests and review

TDD throughout; unit + integration (stub-driven runner tests as `test-t7.sh`) + the lab
matrix as E2E. Each step: `/simcodex` before it is reported. Full probes test run when
probes Swift changes (about 56 min, in the background).

## 5. The three decisions, converged (thecure with Codex, 2026-10-07)

Debated in two rounds; the owner confirms the conclusion, not a choice.

- **O1** When Ice cannot verify that the members left the bar, it hides anyway and
  says `hiding requested, not verified`; the IceBar is offered; never a lab success.
  No strict-mode setting. Any hiding, verified or not, first needs D-c's
  preconditions a, b, c.
- **O2** No longer a decision: the membership rule of D-a.
- **O3** The owner starts the lab matrix: one command in the `icetest` foreground
  session, unattended, fixed scenarios, no agent; asked for only after S1-S3 are built
  and reviewed. One fact to ask the owner then, not a decision: is there a second Mac
  that could be dedicated to the lab.
- **S2, added:** the placement fix aims, for a fresh Ice, at
  `hidden divider | other status items, system agents included | Ice's icon`, so that
  items such as the input menu are not swept into the hidden section by default (on the
  owner's bar they sit right of Ice's icon already: MenuBarAgent's store has them at
  141.5 and 221.5, Ice's icon at 361.5, divider at 465).

| Claim | Won by | On what evidence |
|---|---|---|
| hide best effort when unverifiable, one behaviour | the assistant, with Codex's preconditions | `CheckPlan.swift:72-74` (no reference is a verification failure, not a reason not to act) |
| the risk of that is only "an item stays drawn" | Codex | an unseen item can be carried off and be unreachable: non-`AXMenuBarItem` records are dropped before membership (`ItemCatalog.swift:123-131`) |
| `.unnamed` items are manageable (the plan had called them unmanaged) | the assistant | `PressTargetRule.swift:12-20`, `CheckPlan.swift:36-45`, FINDINGS "`.unnamed` items are eligible" |
| `.positional` items can be members too | Codex | identifier-at-index is the only recheck and the identifier is shared (`PressTargetRule.swift:13-18`); the detector drops positional keys (`DiscoveredTargets.swift:7-17`) |
| "listed and pressable" for members | Codex | only while uniquely addressable in the current read; otherwise stale and disabled |
| the owner starts the lab; a second Mac is a fact to ask | agreed | the plan's S4 |

Codex's greatest worry: positional identity taken as good enough because `AXPress`
finds some child at that index -- the feature would look successful while opening
another app's menu. Its most likely point of failure in the plan: S2 (a seed may not
be able to establish `divider | others | icon`; remembered positions).

## 6. Risks

- Trace mode may not reproduce P2 in the owner's account (another bar, another store);
  then it is the lab's first scenario. The cause may be in AppKit/MenuBarAgent and not
  fixable by a seed (then S2's repair path is the product answer).
- Trace mode starts something it should not (S1's list and the store guard).
- D-b/D-c hide without proof: an item may stay drawn unnoticed when no pixel check is
  possible. Accepted by the goal (best effort); the pane says "not verified".
- Rollback: this plan adds; the certificate path stays in the tree until S3 is green.

## 7. Task list

| # | Task | Depends on | Owner cost |
|---|---|---|---|
| T1 | Ice's trace mode + the trace in the owner's account (S1) | -- | none |
| T2 | placement fix + inverted-layout notice (S2): T2a seed and trace oracle, T2b remembered-position measurement, T2c notice and machine blocker (S2 design) | T1 | none |
| T3a | hiding rules as pure IceCore types + tests (S3) | this plan's review | none |
| T3b | the rules wired into the live machine and coordinator (S3) | T2, T3a | none |
| T2d | always-hidden divider read at the hidden divider's frame on a fresh identity (S2 design, exception) | its own plan review | none |
| T4 | fixed-matrix lab runner (S4) | T3b; the owner starts it (section 5, O3) | one sitting per matrix run |
| T5 | owner acceptance (S5) | T4 green x3 | one short sitting |

T1 and T3a are independent and may run in parallel; T2 needs T1; T3b needs T2.

## Appendix: plan review

| Round | Finding | Ruling |
|---|---|---|
| 1 | P0 a copied lifecycle repeats the stand-in mistake; trace the staged Ice itself | taken: trace mode in Ice's own sources, inert elsewhere, under a lab bundle id |
| 1 | P0 736 pt is a lab candidate, not a product length | taken: no shipped constant; verified / requested-unverified / failed |
| 1 | P0 D-a incoherent: a spacer moves everything; `declared` is not restart-stable | taken: members only; no persistence promise before a restart experiment |
| 1 | P0 "three green runs" without a per-member oracle is a false green | taken: verified and unverified outcomes never mixed; scenarios 8-11 added |
| 1 | P1 background-session runner unproven; an owner-owned job file is still a control plane | taken: foreground, fixed scenarios, no agent by default |
| 1 | P1 the three owner decisions are the wrong ones | taken: O1 strict vs best effort, O2 unmanaged items, O3 who starts the lab; `«` dropped as a question |
| 1 | P1 the click half is not guaranteed | taken: D-f, the menu-open signal as the oracle |
| 1 | P2 evidence labels in section 1 | taken: P1, P2, P8 relabelled and scoped |
| 2 | (reviewed the unrevised draft: the assistant's edit script had failed, so round 1's rulings were not in the file) P1 no Appendix; P1 S1 still a copy | process error, the assistant's; the revision is now in the file |
| 2 | P1 a real launch does far more than create three items; no store check | taken: S1's started / not-started list from `AppDelegate` and `AppState`; the before/after guard on MenuBarAgent's store; the reflow stated, not denied |
| 2 | P1 "held at standard length" is not the unmodified lifecycle | taken: the experiment is defined as IceBar mode with uncalibrated dividers, standard length by the real path; no claim about an ordinary launch |
| 2 | P1 D-a: an unmanaged item left of the divider must block hiding | taken as the default of O2 (round 1 had proposed carrying it as collateral; the two differ, so the owner decides, default = block) |
| 2 | P1 T3 needs a boundary | taken: T3a (pure rules, parallel with S1) and T3b (live wiring, after T2) |

| 3 | P1 S1's started / not-started set is not executable as written: settings setup starts hotkeys, `AppState`'s construction starts permission polling, `MenuBarManager.performSetup` starts panels; a clean domain removes the always-hidden item; three keys, not two | taken: the exact bootstrap (only each section's setup, three settings set in memory, polling stopped), three keys and two stores logged |
| 3 | P1 D-a/O2 and strict O1 need a "blocked, not attempted" result that D-c and S4 lacked | taken: a fourth state with its oracle; scenarios 5 and 10 tied to O1 and O2 |
| 4 | (again shown a file without the round-3 revision: the assistant's edit script had failed a second time) the same two P1s, plus: a clean domain loads `useIceBar` false; call `settings.performSetup` and say it starts hotkeys; force `enableAlwaysHiddenSection` on for three frames | process error, the assistant's; from now the file is checked before it is sent. Taken: `useIceBar` set explicitly. Modified: the always-hidden setting is run both off (T7's state, where P2 was seen) and on; `AppSettings.performSetup` is not called, to keep hotkeys out of the owner's session, unless the code review shows the values cannot be set without it |

Round 1: 4 P0 + 3 P1 + 1 P2. Round 2: 5 P1, two of them caused by a failed edit.
| 5 | both round-3 P1s resolved; both modified rulings accepted (the three settings can be set in memory and are observed by `ControlItem`'s subscriptions, `ControlItem.swift:281, 308, 330`; the settings' persistence subscribers are installed only by their `performSetup`, so nothing of the settings is written; the trace still writes the lab domain's three control-item defaults) | **CONVERGED** |

| thecure | the three decisions O1-O3 (2026-10-07, after the plan converged): round 1, 10 claims -- 6 right, 4 conceded to Codex; whole-package confirmation, one objection (pressable only while uniquely addressable), taken | converged: section 5, D-a, D-c, scenarios 10, 12, 13 |

Round 1: 4 P0 + 3 P1 + 1 P2. Round 2: 5 P1 (unrevised file). Round 3: 2 P1. Round 4:
the same 2 P1 (unrevised file) with three refinements. Round 5: 0, CONVERGED. Two of
the five rounds were spent on files the assistant had failed to revise; since then a
revision is checked in the file before it is sent.

### T2 design (S2 design subsection; Codex gpt-5.6-terra, 2026-10-08; cap 5 calls, 3 used)

| Round | Finding | Ruling |
|---|---|---|
| 1 | P0 the gate through `boundaryUsable` is read only when a baseline starts; `.resting` ignores samples (`IceBarHidingMachine.swift:269, 294`) | taken (Codex's): a machine blocker, first in `blocker(in:)`, `setLength(nil)` from every phase |
| 1 | P0 no disposition when the oracle's clauses 2-3 fail; add a "divider right of the others" notice | modified, accepted in round 2: any failing clause reverts the seed and is reported as an open defect T2c does not cover; no new notice (a far-right divider is also an owner's choice; D-c's preconditions are owner-confirmed) |
| 1 | P1 clearing a stored 1 infers provenance from a number | taken, simpler: no migration, stored values never touched, the rule keeps its shape |
| 1 | P1 the oracle stitched two reads | taken: one `DiscoveredItemSet` per verdict, two agreeing passes or `indeterminate` |
| 1 | P1 drag safety: idle time alone is not enough; ask for a countdown, confirmation, foreground | modified, accepted in round 2: hardware-input and target re-checks before every event, abort with release; no countdown or confirmation (the owner's ruling: unattended, in their account, harness items) |
| 1 | P1 Q4 cannot say "which wins" from one read | taken: the tuple, three agreeing settled reads, else inconclusive |
| 1 | P1 "at start and on every layout change" overstated; wants a live integration test | modified, accepted in round 2: timing corrected; the live wiring proof is S4 scenario 14, not a full Ice in the owner's account (S1's not-called list, R1); INFERRED until then |
| 1 | P2 candidate B (seeds of 20 000 / 30 000) unsupported | taken: dropped |
| 2 | P1 the drag re-checked frames only, not the targets' identity | taken: T and P re-resolved from scratch before every event |
| 2 | P1 `inv` both optional and in the 3-of-3 E2E line | taken: its gate said exactly (completion gates; inversion is diagnostic; an inverted run without the notice fails) |
| 3 | none | **CONVERGED** |

Round 1: 2 P0 + 5 P1 + 1 P2. Round 2: 2 P1. Round 3: 0. Of round 1's eight, five
taken as given, three modified with evidence and accepted.

### T3b design (S3 design subsection; Codex gpt-5.6-terra, 2026-10-08; cap 5 calls, 4 used)

| Round | Finding | Ruling |
|---|---|---|
| 1 | (sent before the subsection was in the file: the edit had been stopped by a hook and the call went out beside it -- the assistant's process error, the third of its kind in this plan; Codex ruled on the seven choices named in the prompt only) P1 G1 drops by `enumeratedPIDs`, which leaves out `.prohibited` apps | modified, accepted in round 2: dropped only when `kill(pid, 0)` says the process does not exist |
| 1 | P1 `childIdentifiersByPID` defaulting to `[:]` loses a pass fact silently | taken: a required parameter; the probes' five sites change, the full probes run is owed |
| 1 | P1 a stale baseline must be re-taken before a re-check | rejected, conceded in round 2: a baseline needs the section shown (`HiddenLengthObserver.swift:65-68`); Codex: "whether to show on expiry is an owner value judgement; retaining the length and reporting unverified is consistent with confirmed D-e" |
| 1 | P1 a Space change is structural | rejected, conceded in round 2: the signature's item lists already carry any roster difference |
| 1 | accepted as proposed: the best-effort length (no new literal), structural versus soft, Show Ice icon off blocks, `test-t7.sh`'s block removed (the new contract pinned by unit tests) | -- |
| 2 | P0 a permission-denied pass is not published, so the preconditions would not block | taken: the preconditions are evaluated on every completed pass, before the cache plan's branch |
| 2 | P1 `lengthApplied` is false during a settle; offer the IceBar from `isIceBarOffered` | taken in part (`lengthSet` named beside `lengthApplied`); the rest rejected, conceded in round 3: a presented IceBar aborts the observation, and at standard length it would list on-bar items twice |
| 3 | P1 a structural change does not retire the length | a wording gap, not the design: `quiet` and `blocked` are standard-length phases; said so |
| 3 | P1 `blocked` has no exit | taken: preconditions ok -> `quiet` |
| 3 | P1 `resolve` on every pass contradicts "advances only at standard length" | rejected, conceded in round 4: `resolve` freezes without a trusted boundary (`PreferenceHidingMembership.swift:130-142`) |
| 4 | all three RESOLVED, no new P0/P1 | **CONVERGED** |

P0/P1 per round: 4 (on the prompt alone), 2, 3, 0. Of twelve findings: five taken, two
modified, four rejected with evidence and conceded, one a wording gap. For the owner,
one value judgement Codex named and did not rule: when a re-check meets a baseline older
than ten minutes, Ice keeps the items hidden and says "not verified" rather than put
them back on the bar to re-baseline.

### T2a code review (/simcodex, 2026-10-08; 3 rounds, the stated cap)

| Round | simplify (4 views) | Codex | Ruling |
|---|---|---|---|
| oracle | -- | re-review of clause 2 after the first run counted three parked items as left: ACCEPT, with "tell pre-existing parked items from displaced ones" | clause 2 counts on-bar items only; Codex's point taken as clause 6 (a baseline pass before Ice's items exist; equal on-bar counts) |
| 1 | 4 P1: the divider boundary written a third time; the tool's T1 `layout()` on another boundary; the pass count in a case name; dead and copy-pasted test lines | 1 P2: a parked icon could pass | all taken: `DividerReading.boundaryMinX`, the reading `discover`, the count pinned in the tool, `iconOnBar` |
| 2 | 3 P1: the parked-icon fix sat only in the trace; two texts stating what the code no longer does | 1 P1: reject `othersRightOfIcon > 0`; 1 P2: pass numbers unchecked | the parked icon moved into `iconPlacement`; texts fixed; P2 taken. Codex's P1 **rejected** (the plan's "recorded, never judged": such an item is in the visible section, `DiscoveredCachePlan.swift:128-141`, and Ice cannot pass items pinned further right) -- accepted by Codex in round 3 |
| 3 | 2 P1: `evaluate(iceIcon:)` still took a frame, blind to parking; one docstring word | 0 P0/P1 | taken: `evaluate` takes the discovered icon, the frame overload is not public. Codex confirmed the late change: 0 P0/P1 |
| after | -- | the final build's run failed 6 of 6 on one incomplete baseline pass (the process's first); retry-until-complete, at most two: 0 P0/P1 ("completeness gating, not cherry-picking") | taken; the clause itself not relaxed |

Trend, P0/P1 per round: simplify 4, 3, 2; Codex 0, 1 (rejected), 0. Left as P2, for
T2c, which reopens the oracle for `inv`: the oracle's clauses as one IceCore verdict
instead of Python; raw string values for `PreferenceHidingIconPlacement`;
`othersUnplaced` (derivable, and two meanings); `iconOnBar` now implied by
`iconPlacement`; three frame encoders in `LabTrace.swift`; `left.jsonl` beside
`trace()` in `test-trace.sh`; `boundaryMinX` not yet used by `DiscoveredCachePlan`
and `CheckPlan`; a separate "off the bar" case beside `.iconUnreadable` for T3b's pane.


### T2b code review (/simcodex, 2026-10-08; 3 rounds, the stated cap, then one Codex confirmation)

| Round | simplify (4 views) | Codex | security-reviewer | Ruling |
|---|---|---|---|---|
| 1 | 6 P1: two dead things in `dragown`; Q1's last row mislabelled; the dragged side read twice; seed side and read count stated twice; **the experiment confounded** (T dragged to the left, where a relaunched T lands anyway) | 2 P0 (a `try()` lock could skip the release; held state recorded after the post) + 5 P1; the three corrections made while building (frames compared only until the press; adjacent = AX gap 14 +- 2; the wait for quiet) **ACCEPT** | 2 HIGH (nothing checked what is under the press point; exit paths that leave the button or Command held), 3 MEDIUM, 3 LOW | all taken, except: "seed side / read count stated twice" kept as P2 (a mismatch fails loudly as `readCount`), "no retry after `sameSide`" rejected (after the hit test the drop can only be on a harness item). The confound: P first, T dragged right, `adjacent` added to each read |
| 2 | 6 P1: three stale headers, one unused file; `seedWins` stronger than its reads; P's last entry not marked as displaced | 0 P0 + 5 P1: `defaultBefore` read too early; `slotKept` without adjacency; `seedWins` unproven and without Q3 as control; `:A` resolves a link before the no-link check; the lab defaults' delete unverified. Round 1's rejected half (T's default need not still read 0.1: E5) **ACCEPT** | -- | all taken as given: Q4 says `seedCompatibleNotSlot`, never that the seed won, and needs Q3's `slotKept` |
| 3 | 3 P1: a stale README row; Q1's ages mislabelled; one in T2a's test code (outside this diff, left as P2) | 2 P0 (a release without the lock lets a stuck post land after it; held flags cleared when an up event could not be made) + 2 P1 (the hit test compared only the process; `link//`); 4 of round 2's 5 VERIFIED | re-check: no CRITICAL/HIGH, the first eight FIXED; 2 MEDIUM + 4 LOW new (an untimed lock in the watchdog; `release` posting unconditionally) | all taken; ACLs, the directories above the apps directory and the milliseconds between the last hit test and the press are stated as not closed |
| after | -- | confirmation of round 3's four: all **RESOLVED**, no new P0/P1, **CONVERGED** | -- | -- |

Trend, P0/P1 per round: simplify 6, 6, 3; Codex 7, 5, 4, then 0. Left as P2: the
per-event Accessibility reads (about ten a step; the watchdog bounds them); `stopping`
(redundant with exiting under the lock); `runDrag` and `runRead` sharing their
discovery; the helper launch code beside frozen `run-t7.sh`'s; `stop` and the
store-before save in both runners; an explicit "something is right of P" reading (T's
x is recorded instead); a retry after a `notMoved` attempt may drag T back;
`placement()`'s unused seventh argument in `test-trace.sh`; `vzhelper`'s own comment
on `--autosave`.

### T2c code review (/simcodex, 2026-10-08; 3 rounds, the stated cap, then two Codex confirmations)

| Round | simplify (4 views) | Codex | Ruling |
|---|---|---|---|
| 1 | 0 P0/P1 (8 + 3 P2) | 1 P0 (the gate read any usable divider, also one at a hiding length, so a held inversion could clear with the length applied) + 2 P1 (stale flag and notice; `inv`'s cleanup not guaranteed) | all taken: the placement is held from the last pass with a trusted hidden boundary (a pure rule, tested); one published placement, the pane applies the rule live; an EXIT cleanup. Kept on purpose: a pass that publishes nothing leaves a held inversion, which changes no length |
| 2 | 2 P1 (a signal left the launched trace running past the cleanup; one doc comment) | P0 and the stale-state P1 RESOLVED; 1 P1 (a failed cleanup still cleared its record and exited 0) | all taken |
| 3 | 0 P0/P1 | 1 P1 (a signal between staging and its record) | taken |
| after | -- | that one RESOLVED, 1 new P1 (an unremovable domain overwritten by the next run's record); then RESOLVED, **CONVERGED** | taken: the runner ends there |

Trend, P0/P1 per round: simplify 0, 2, 0; Codex 3, 1, 1, then 1, 0. No security-sensitive
change, no security review. E2E: `run-trace.sh` 9 of 9 twice (the second with the
runner as reviewed but for its last line, an exit no normal run reaches). Left as P2:
the string-keyed phase fixture in the machine's tests; `PASSING` doubling as the
variant list in `trace-tool.py`; the pane telling "same line" by comparing texts; the
placement computed on passes that may not update it; `placement()`'s seventh argument
now used only by `inv`'s tests. Open for T3b: the two "not covered" rows of STATUS.

### T3b code review (/simcodex, 2026-10-08; 3 rounds, the stated cap, then one Codex confirmation)

Reviewed: `git diff 226d84e` (the pre-review checkpoint `707ffe3` plus the fixes, uncommitted). Codex
by `codex review --base` in round 1, then `codex exec` on the working tree.

| Round | simplify | Codex | Ruling |
|---|---|---|---|
| 1 | 4 views: 9 P1 -- roster bookkeeping untested in the app layer; the ready set built twice from two samples; `LayoutSignature`'s field names repurposed; the press-failure retry watching the cache, not the IceBar's cells; `isAtStandardLength` restating `DiscoveredCachePlan.evaluate`; the roster published in a later turn than the cache, and frame-sensitive; two near-identical phase transitions; the `«` threaded through the machine and read by nothing; stored fields derivable from others | 1 (labelled P2, a behaviour defect): a drag or structural change while already quiet did not restart the quiet period | taken: the quiet fix; `PreferenceHidingRoster` (IceCore, tested); `DividerState.boundaryIssue`; `readyKeys`, the baseline command carrying the roster; `LayoutSignature(items:members:)`; the retry following the roster; the roster updated in the cache's turn; `move(to:)`. **Rejected**: taking the `«` out of the machine -- S3's T3b bullet requires the machine to record it. Frame-sensitive equality left (P2) |
| 2 | 1 P1: the old cache-based retry left beside the new one | 1 P1: IceBar mode off did not empty the roster until the next pass, so a mode turned on again could hide with the old roster; 1 P2: no wiring-level test | all taken; the P2 is a limit: `Ice/` has no test target |
| 3 | 0 P1 | 2 P1: `HiddenLengthObserver` is a reentrant actor, so a cancelled baseline could resume after a newer one and clear it; a press in flight across a reset re-disabled a cell of the new roster | both taken: a baseline generation; a press generation bumped by the reset |
| after | -- | both RESOLVED, no new P0/P1: **CONVERGED** | -- |

P0/P1 per round: simplify 9, 1, 0; Codex 1, 1, 2, then 0. No security-sensitive change (no
auth, payment, personal data, crypto, file or network I/O beyond what the reads already did): no
security review. Left as P2: `MenuBarItem` equality includes frames, so the roster republishes when a
member's frame moves; `childIdentifiersByPID` classifies each read a second time and is built
outside IceBar mode too; the `«` read in `observe` runs after the verify, not beside it; the
"AXMenuBarItem" literal in `ItemCatalog` and `DiscoveredFrameReader`; the item-by-key index built in
three places with three collision policies; `PreparedVerification.Ready` without an
`observedTargets`; `BaselineCoverage` now feeds only the log; `IceBarHidingStatus` could be methods
on an optional `PreferenceHidingState`; `setMode(false)`'s save-and-restore of two fields; three
test files each wrapping `fixtureSignature`; `itemTags` public for tests only; the IceBar view's own
`#available` and mode branch; three derivations of "the boundary was trusted"
(`hiddenBoundaryUsable`, `resolve`'s, `boundaryIssue`).

