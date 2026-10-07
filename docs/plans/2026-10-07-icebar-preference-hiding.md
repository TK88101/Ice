# IceBar on macOS 27, re-aimed: preference hiding, proven in a harness before any owner sitting

2026-10-07 · final (Codex round 5: CONVERGED; T2 design added 2026-10-08, Codex round 3: CONVERGED; Appendix) · T1, T3a implemented · continues on `wip/icebar-build` from `6c61b96`.
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
| P4 | macOS 27: a preferred position of 0 reads as none; positive values order from the right, smallest rightmost; MenuBarAgent remembers dragged positions per `status:<bundle id>::<autosave name>` outside the app's defaults, and they override an app seed | MEASURED (owner's account probes; the store file) / INFERRED (the override) |
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
     under the notch), the discovery pass `complete`, the store guard passing.
  6. (added 2026-10-08, Codex's re-review of clause 2) none displaced: a discovery
     pass taken **before** any control item exists (a fourth trace step,
     `.readBaseline`) counts the other items on the bar; the judged pass must count
     the same number, so a leftmost divider that pushed an item off the bar fails.
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
  both in every other exit. No countdown or confirmation: the run is unattended by
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

**T2c The notice and the gate (macOS 27, IceBar mode).**

- One definition of "right of": `PreferenceHidingPreconditions.misplacement` becomes
  the public `iconPlacement(icon:divider:) -> PreferenceHidingIconPlacement?`
  (unchanged logic; T3a's tests keep passing).
- New pure rule `IcePlacementNotice.notice(placement:isIceBarMode:isDragging:)`:
  `.iconLeftOfDivider` in IceBar mode and not during a drag gives the notice; every
  other input gives none. An unreadable icon or unusable divider is **not** reported
  as inverted (Ice did not see an inversion; T3b's `blocked` state names those).
  The text lives beside the rule, as `IceBarHidingStatus.message` does: "Ice's icon
  is left of its hidden-section divider, so Ice hides nothing. Hold Command and drag
  Ice's icon to the right of the divider."
- Wiring: `MenuBarItemManager.cacheDiscoveredItems` (27 only) evaluates the rule on
  each discovery pass it publishes and publishes the notice; a pass is skipped for
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
  placed identity; (8) frontmost app and long menus changing while hidden; (9) Ice
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
