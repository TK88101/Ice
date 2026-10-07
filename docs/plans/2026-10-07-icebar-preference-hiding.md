# IceBar on macOS 27, re-aimed: preference hiding, proven in a harness before any owner sitting

2026-10-07 · final (Codex round 5: CONVERGED; Appendix) · not implemented · continues on `wip/icebar-build` from `6c61b96`.
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

### S3 Re-aim the hiding rule (owner cost: none)

- D-a **Members, and nothing else moved without consent** (rounds 1-2: a spacer moves
  everything left of it; there is no way to leave one item behind).
  *IceBar members*: live items left of the divider that are uniquely addressable over
  Accessibility now (`declared` basis: a unique non-empty identifier within the process,
  `ItemKey.swift:45-57`); listed and pressable. An item left of the divider that is not
  addressable (unnamed or ambiguous, such as Apple's input menu in `icetest`) is
  *unmanaged*; what Ice does then is owner decision O2 -- default: Ice does not hide
  and the pane says which item to move to the right of the divider (round 2's cheapest
  safe rule: "not managed" then really means "not hidden"). No promise that membership
  survives a restart until a restart-identity experiment says so (FINDINGS "Identity
  across restarts is untested"); the experiment is in S4.
- D-b **`«` is recorded, never a trigger.** It neither vetoes a length nor shows the
  section at rest.
- D-c **Four states, said honestly** (rounds 1 and 3):
  `blocked, not attempted` -- Ice changed no length and offers no IceBar: an unmanaged
  item is left of the divider (O2's default), Ice's icon is left of its divider (S2),
  or verification is unavailable and O1 is "do not hide"; the pane names the reason
  and, where there is one, the item to move;
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
  What Ice does when it cannot verify (strict: do not hide; or best effort: the
  unverified state above) is owner decision O1.
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
  relaunched (membership and identity); (10) an unmanaged item left of the divider;
  (11) a member kept visible on purpose must yield `visible / failed`, never `verified`.
- Outcomes are of three kinds and never mixed: **verified** (per-member visual
  absence, the IceBar's roster equals the members, the menu-open signal);
  **unverified best effort** (Ice applied an attempt and said so); **blocked** (the
  oracle: no divider length changed, nothing moved, no IceBar offered, the reason
  reported). Scenario (10) must end blocked under O2's default; scenario (5) must end
  unverified or blocked according to O1. Only verified scenarios count toward the
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

## 5. Decisions the owner must make (asked once, with a default)

| # | Question | Default if not answered |
|---|---|---|
| O1 | When Ice cannot verify that the chosen items left the bar (no reference item, capture refused): hide anyway and say "not verified", or do not hide? | hide, labelled "not verified" |
| O2 | An item Ice cannot manage (e.g. Apple's input menu) sits left of the divider. Refuse to hide until it is moved to the right, or hide anyway and let it be carried off with the others (it would not be listed in the IceBar)? | refuse, and name the item to move |
| O3 | The lab needs the `icetest` session in front for each matrix run. Who starts it: you, each time (one command, unattended, results read by the assistant); or a second Mac if you have one to dedicate? | you start it; asked for only when S1-S3 are done and reviewed |

`«` is no longer a question: it is recorded, never a trigger (section 0, D-b).

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
| T2 | placement fix + inverted-layout notice (S2) | T1 | none |
| T3a | hiding rules as pure IceCore types + tests (S3) | this plan's review | none |
| T3b | the rules wired into the live machine and coordinator (S3) | T2, T3a | none |
| T4 | fixed-matrix lab runner (S4) | T3b, O1-O3 | per O3 |
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

Round 1: 4 P0 + 3 P1 + 1 P2. Round 2: 5 P1 (unrevised file). Round 3: 2 P1. Round 4:
the same 2 P1 (unrevised file) with three refinements. Round 5: 0, CONVERGED. Two of
the five rounds were spent on files the assistant had failed to revise; since then a
revision is checked in the file before it is sent.
