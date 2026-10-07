# IceBar T7 retry: the application menu frame on macOS 27, and a clearer run

Status: final (Codex, four rounds; Appendix). Not implemented. Fixes
what stopped T7 run `20261007-012252-t7` (plan 2026-10-03-icebar-build, section 10)
so T7 can be run again. Implemented on `wip/icebar-build` (the same build line;
T7's staging and scripts live there), from `95d1179`.

## 1. What happened

| # | Fact | Grade |
|---|---|---|
| E1 | Run `20261007-012252-t7` (`icetest`, rev `95d1179`), started 01:22:52, Ctrl-C after 3 min 48 s; preferences restore `verified`, helper domains empty. Evidence copied to `~/IceReverse-evidence/20261007-012252-t7/` (`ditto`, `diff -r` identical) | MEASURED |
| E2 | `ice.log`: `checking` at 01:22:53.37, `shown(menuUnreadable)` 1.04 s later, again `checking` -> `shown(menuUnreadable)` at 01:22:55.56; no further IceBar line, no `active`, no baseline, no trial for 3 min 45 s | MEASURED |
| E3 | `menuUnreadable` comes only from `MenuWidthRule.verdict` returning `.unreadable`: menu edge or notch is nil or not finite (`MenuWidthRule.swift:20-23`, `IceBarHidingMachine.swift:257-259`) | MEASURED (code) |
| E4 | The notch is readable on this Mac: built-in display only (`system_profiler`), `auxiliaryTopLeftArea` maxX 771.5 | MEASURED, owner's account, 2026-10-07, macOS 27.0.1 26A434; `postmortem/axorigin-output.txt` in the run's evidence |
| E5 | `NSScreen.getApplicationMenuFrame()` (`Ice/Utilities/Extensions.swift:553-570`) hit-tests the system-wide element at the display origin and needs role `AXMenuBar`. The hit test at (0, 0) returned an `AXWindow` of `com.apple.MenuBarAgent` in 3 of 3 reads; (1, 1) the menu bar owner's `AXMenuBar`; (20, 10) an `AXMenuBarItem`. So under these conditions the reader returns nil | MEASURED, same record as E4 (probe source `postmortem/axorigin.swift`, read-only) |
| E6 | E5 in `icetest` | INFERRED: same Mac, display and OS; E2 matches it exactly |
| E7 | The same origin hit test is upstream's (`upstream/macos-26` same line; `upstream/main` `MenuBarManager.getApplicationMenuFrame(for:)`). Five other call sites use the reader; their reach under T7's settings is in section 3, F1 | MEASURED (code) |
| E8 | The owner saw neither a helper icon nor any flashing for 5 min, and answered row 1 `y` without knowing what to expect | owner's report |
| E9 | With the machine `shown`, the hidden divider is at standard length (`ControlItem.swift:455-486`, `calibratedLength ?? Lengths.standard`), so the helper was probably on the bar; whether it was visible in that layout is not known | INFERRED; settled by F3 next run |
| E10 | `run-t7.sh` row 1 prints "wait for `active`" and asks at once (`run-t7.sh:312-316`); the script itself never waits, never looks for `shown(...)`, and its text "列上最左側" reads as the far left of the whole bar | MEASURED (code) |

The memory note "layer-20 full-screen system window tops the CG window list" is the
same window seen by the window server; E5 is its Accessibility side.

## 2. Goal and scope

- F1: on macOS 27 the application menu frame is read without the origin hit test.
- F2: `run-t7.sh` waits for Ice itself, ends the run when Ice is not hiding, and
  every row says where to look (bar or Terminal).
- F3: each phase records where each helper is on the bar, so "not seen" can be told
  apart from "not there".
- F4: a live preflight of F1 before anything starts, so this failure costs seconds,
  not a sitting.

Not in scope: the calibrator, the machine, the detector and `Packages/MenuBarCapture`
(frozen), the checklist's expectations (section 10.5 rows stay as they are), T8.

## 3. Design

### F1 menu frame reader (macOS 27 only)

- New `ApplicationMenuReader` in `MenuBarDetectorFeed`, behind an Accessibility seam
  (`ApplicationMenuAXReading`, as `ChevronReader` takes `MenuBarAXReading`). Input:
  the menu bar owner's pid. It reads that app element's `kAXMenuBarAttribute`, then
  each child's enabled flag and frame, with `AXUIElementSetMessagingTimeout` 0.25 s
  on every element (vzhelper's `selfRead` value, `vzhelper/main.swift:335-375`). A
  child whose frame is missing or not finite is skipped on its own; the result is
  the union of the rest, nil when there is no pid, no menu bar, an AX error on the
  bar, no usable child, or a width <= 0.
- Threading: callers read the frame from the main thread and from detached tasks
  (the coordinator, `IceBarHidingCoordinator.swift:79-96`; the overlay,
  `MenuBarOverlayPanel.swift:151-156`). So the pid is never read from `NSWorkspace`
  at the call: a small `MenuBarOwnerPID` holder, owned and strongly retained by
  `AppState`, created synchronously on the main actor in `AppState.init` (before the
  asynchronous setup, `AppState.swift:64`), which reads
  `NSWorkspace.shared.menuBarOwningApplication` at once and then observes it with
  KVO `[.initial, .new]`, each change applied on the main actor; it stores only the
  scalar pid behind a lock, and `getApplicationMenuFrame()` reads it from any
  thread. A cold launch with no owner change therefore still has a pid (round 3). The AX reads stay where each caller already does them; only
  their source changes.
- `getApplicationMenuFrame()` uses it under `#available(macOS 27, *)`; earlier
  systems keep upstream's code unchanged. The inactive-display notch workaround
  (`Extensions.swift:573-587`) runs after either path, unchanged. No second display
  is attached (E4), so the multi-display case is covered by the fake only, stated.
- Why the owning app and not a hit test at (1, 1): it does not depend on which
  window the system puts on top at a given point, which is what broke here.
- The other call sites on 27, read in the code (no live test):

| Call site | Reached in T7? | Change |
|---|---|---|
| `MenuBarManager.swift:179` auto-hide app menus | no: guarded by `!useIceBar` (`:165`) | none in T7 |
| `MenuBarItemManager.swift:1680` temporarily show | no: returns before the read when the item has no window (`:1667`), always on 27 | none |
| `HIDEventManager.swift:412, 525` show on click/hover in empty bar space | yes, a click in the bar | a click on the app menu no longer counts as empty space (it did while the reader was nil): the upstream behaviour restored |
| `MenuBarOverlayPanel.swift:156, 289` appearance overlay | only with a custom appearance; T7 deletes the domain, so default | none expected |

### F2 `run-t7.sh`

- New `wait_for_phase_status` (in `t7-lib.zsh`), called after all of a phase's
  helpers are up and before row 1: reads only the `ice.log` lines written after the
  phase's start offset. `active` -> go on. `shown(menuUnreadable)`,
  `shown(cannotAssess)` or `shown(noCleanLength)` that is still the latest status
  10 s later, or no `active` within 5 min (T0: a full sweep about 2.7 min) -> print
  `Ice 沒有在隱藏（原因：…），本輪無效`, write it to the report, `finish 3` (cleanup as
  every exit). Ice ending while waiting -> `finish 1`, as `ask` does. Phase 4 calls
  it only for the initial `active` (row 5 expects `longMenu` later).
- The limits are named constants; `test-t7.sh` shortens them with a test-only
  option, never from the environment (section 10.3: the run takes nothing from it).
- Prompts start with `【看選單列】` or `【看終端】`; row 1 names the place as
  "右邊那排圖示（Wi-Fi、電池、Ice）的最左端" and the icon as a black-and-white
  bracket-shaped line glyph without text, with F3's x.

### F3 helper placement record

- After all helpers are up and again after `active`, the script sends `selfread`
  to each helper and waits up to 2 s for its `selfread {...}` line in that helper's
  log (the reply is asynchronous, `vzhelper/main.swift:541-547`). `frames` is not
  used: it has no position (`:500-502`). From the JSON: the helper's own child (its
  identifier) and its full frame. "On the bar" = finite, width and height > 0, and
  the rectangle inside the main display's menu bar band (y from the display's top
  to the bar height, x inside the display). The full frame and the display ID are
  recorded. No reply, malformed JSON or no
  child -> recorded as `unknown`, not as off the bar.
- The report gets one line per helper per snapshot: `helper p<n>-<i> 啟動後 x=… 在列上`
  / `active 後 x=… 不在列上` / `unknown（原因）`.
- The first snapshot is a gate before `wait_for_phase_status`: a helper whose frame
  is not finite or not inside the main display -> `helper 不在選單列上，本輪無效`,
  record, `finish 3`. `unknown` is asked once more after 2 s; still `unknown` ->
  the same stop (rows 1-4 cannot be judged without knowing where to look).

### F2b one owner row for the changed click path

- Phase 1, after row 1: `【看選單列】點一下左上角 Terminal 的「Shell」選單，再按 Esc，然後看著 Ice 圖示下方數 3 秒`;
  expect the menu to open and no IceBar to appear during those 3 s (y/n). The
  wait covers the toggle's asynchronous panel (`HIDEventManager.swift:184`,
  `IceBar.swift:181`); the script prints the question only 3 s after the owner
  presses Enter to say the click is done.
- Deterministic check of the same path: the containment test of
  `isMouseInsideApplicationMenu` (`HIDEventManager.swift:482-486`, the frame widened
  to the screen's left edge) moves into a pure IceCore function the method calls;
  tested: nil frame -> not inside (the click counts as empty space, the old
  behaviour), a frame covering the Shell menu point -> inside, and a frame whose
  `minX` is right of the screen's `minX` with the click between the two -> inside
  only because of the widening (round 4). `isMouseInsideApplicationMenu` becomes a
  direct call to it, nothing else. The app has no unit
  test target, so the predicate is tested there. This is the one call site
  of section 3 F1's table that T7 reaches (`ShowOnClick` is on by default,
  `GeneralSettings.swift:40`; `HIDEventManager.swift:176-179`): before the fix a
  click on the app menu counted as empty bar space. Added to section 10.5 as
  row 1b; `n` is recorded, not a stop.

### F4 preflight

- `icewatch` (probes package) gains a dependency on `MenuBarDetectorFeed` and a
  `menu-frame` command: reads the owner pid and the frame with F1's reader, the
  notch from `NSScreen`, and prints `{"menuMaxX":…,"notchMinX":…,"verdict":"fits|crossesNotch|unreadable"}`
  (verdict by `MenuWidthRule`).
- `t7-lib.zsh` validates that JSON strictly. `run-t7.sh` guard 1 runs it after
  `preflight`, with Terminal frontmost: anything but `fits` -> exit 2, nothing
  started. The dry run and `stage-t7.sh`'s dry check require it too.

## 4. Tests (written first, seen red)

- `ApplicationMenuReaderTests` (fake seam): no pid; no menu bar; bar AX error;
  disabled children; one child non-finite (skipped, rest kept); width 0; normal
  union; the messaging timeout set on every element read; the E5 case (a
  system-wide hit test that would give a non-menu-bar window is never consulted).
  Coverage of the new file >= 80 %.
- `icewatch menu-frame`: verdict and JSON shape on a fake reader (`IceWatchCore`).
- `test-t7.sh`: the stub Ice's status lines become a per-test sequence. Cases:
  `shown(menuUnreadable)` persisting -> status 3, the new line, cleanup verified,
  no row-1 prompt printed; `menuUnreadable` then `active` within 10 s -> phase goes
  on; no status within the limit -> status 3; Ice exits while waiting -> status 1;
  `longMenu` in phase 4 after `active` -> not a stop; every prompt carries one of
  the two tags; `selfread` reply delayed, malformed, absent, off-display -> the
  matching report line; a first snapshot off-display, or `unknown` twice -> status
  3 before any row prompt; row 1b asked once in phase 1 and recorded;
  `menu-frame` `unreadable` or malformed -> exit 2, nothing started (stubs leave no
  marker).
- `MenuBarOwnerPID`: the current owner is visible immediately after creation (no
  change needed); a change is visible from a background reader; nil only when there
  is no owner. A `selfread` frame finite and in the display but below the bar ->
  status 3 before any row prompt; the wrong child identifier -> `unknown`. (In `MenuBarDetectorFeed` with the reader if it needs no AppKit
  type; otherwise its lock logic in IceCore and the KVO glue in `Ice/`.)
- Existing: IceCore, MenuBarDiscovery, MenuBarCapture green; app builds;
  `check-a3a4.sh`, `test-check-a3a4.sh`, `check-a10.sh` pass.
- Live, owner's account, read-only (no Ice, no helper): `icewatch menu-frame` gives
  `fits` and a finite `menuMaxX` < 771.5, saved under the run's `postmortem/`.

## 5. DoD

Section 4 green; Codex plan review converged (cap two rounds) and Phase 3
(/simcodex, cap two rounds) done; `stage-t7.sh icetest` restaged from the new
checkpoint with the dry check (including `menu-frame`) passing and no Ice or
`vzhelper` process before or after; plan 2026-10-03-icebar-build note 9 and
`STATUS.md` record E1-E10 and the fix. Then T7 is run again at the owner's time,
same single command.

## 6. Risks

- R1 the owner pid may be nil for a tick during app switches: the machine shows the
  section for that tick; F2 stops only when `menuUnreadable` is still the latest
  status 10 s later. Tested.
- R2 Upstream features change on 27 (F1 table). Accepted; noted in `STATUS.md`.
- R3 F3 shows a helper not on the bar: rows 1-4 cannot be judged; T7 stops for the
  owner with the record.
- R4 `icetest`'s Terminal: `menu-frame` runs with Terminal frontmost, so it checks
  the reader, not every app's menus; long menus are row 5's subject.
- Rollback: revert the checkpoint; restage from `95d1179`.

## 7. 我的步驟（修好之後，時間由我定）

和上次完全一樣：切到 `icetest`，在 Terminal 執行 `/Users/Shared/IceReverse-t7/run-t7.sh`。
這次每一題前面會標【看選單列】或【看終端】；如果 Ice 沒在隱藏，腳本會自己停下並說明，
不需要猜。錄影用手機對著螢幕拍，不用 Mac 錄螢幕（錄影按鈕會佔用選單列）。

## 8. As built (Phase 2, 2026-10-07)

MEASURED in the owner's account; nothing ran on a bar. Each suite seen red before green.

- Deviations, each for a reason found while building:
  - The pid holder lives in a static (`MenuBarOwner.pid`, `Ice/MenuBar/IceBar27/MenuBarOwner.swift`);
    `AppState.init` starts and owns the observation: `NSScreen.getApplicationMenuFrame()`
    has no `AppState` to reach. The immediate read and KVO `.initial` are as planned.
  - The live AX read is its own file (`LiveApplicationMenuAXReader.swift`), as
    `LiveExtrasReader` is; the seam takes the timeout, the live read sets it on
    every element. Covered by a test that reads Finder's menu bar, enabled only
    when the test process is trusted for Accessibility.
  - `icewatch menu-frame` also prints `displayWidth` and `barHeight` (the main
    display's), which F3's bar band needs; one source for both.
  - F3's first snapshot is taken right after each helper reports `up`, not after
    all are up: Ice waits a 3 s quiet period after a layout change before a trial
    moves anything (`IceBarHidingMachine` `quietPeriod: 3`), so the read comes
    before any trial. One retry after 2 s on `unknown`.
  - `wait_for_phase_status` goes on at any `active` since the phase began, not
    only when `active` is the latest status: the stub test showed that a
    `shown(longMenu)` right after `active` would otherwise wait out the limit.
  - Phase 4's question "already active?" is replaced by the wait.
  - `docs/plans/checks/a10-AppState.expected` gains the `init` and its property
    (A10 pins `AppState.swift`'s diff; T4-T6 did the same for `ControlItem`).
- Live: `icewatch menu-frame` in the owner's account gave
  `{"barHeight":33,"displayWidth":1728,"menuMaxX":574,"notchMinX":771.5,"verdict":"fits"}`
  three times (`postmortem/menu-frame-live.txt`), where upstream's reader gave nil (E5).
- Tests: IceCore 471 / 53 suites; MenuBarDiscovery 85 + 70; MenuBarCapture 30;
  probes `IceWatchCoreTests` incl. `MenuFrameReport` 3; `test-t7.sh` 124 checks
  (about 75 s). Line coverage: `ApplicationMenuReader` 100 %,
  `LiveApplicationMenuAXReader` 91.3 %, `ApplicationMenuHitRule` 100 %. App builds;
  `check-a3a4.sh`, `test-check-a3a4.sh`, `check-a8.sh`, `check-a10.sh` pass.
- Residual risk R5: a helper that a trial has already pushed off within its
  first 2 s would stop the phase as "not on the bar"; the quiet period makes it
  unlikely, and the stop names it rather than hiding it.

## 9. Phase 3 review (/simcodex, cap two rounds)

| Round | Source | Found | Taken |
|---|---|---|---|
| 1 | simplify (4 angles) | no P0; P1-grade: test-only CLI flag, a redundant first read in `MenuBarOwner`, a dead `phase_to` write, an array lookup for three reasons, a string round trip for the exit code, three hand-written rect conversions, `pgrep` in a test, a derivable `member_logs` | all: limits as `t7.env` keys `STATUS_LIMIT`/`BLOCKING_GRACE` (the `NEW_ITEM_DELAY` precedent), `.initial` alone, a pattern match, `verdict == .fits`, `BarRect(_:)`/`cgRect`, `BarRect.maxY`, `NSRunningApplication`; plus a bug the fixes introduced (`local` read `i` before setting it), caught by `test-t7.sh` |
| 1 | Codex (`review --commit b77d424`) | 0 | - |
| 1 | security review | 0 CRITICAL/HIGH/MEDIUM, 7 LOW | L1 quoting under `set -u`, L2 Ice's status lines matched by their log prefix only (best effort: text with a newline could still start a line), L4 fixed `PATH`, L6 an infinite union refused; L3 gone with the flag; L5 (no overall AX deadline) and L7 (the pid one hop stale) deferred |
| 2 | simplify (4 angles) | no P0/P1 | P2 taken as one-liners: the long-menu match anchored too, `MenuWidthVerdict: String` (`rawValue` in the JSON), one `usable()` for every edge incl. `maxX`/`maxY`, the rect bridge moved to `MenuBarDiscovery` (now also `LiveExtrasReader`), `#!/bin/zsh -f`, `STATUS_LIMIT` >= 1 |
| 2 | Codex (`review --uncommitted`) | 0 | - |

Trend: round 1 9 P1-grade + 4 LOW, round 2 0 P0/P1. Round 2's last edits (the
P2 one-liners above) landed while Codex round 2 ran and were not sent back
(cap); each is covered by a test. Deferred P2: a short cache for the menu
frame (only matters with a hung app); an overall AX deadline (L5); the pid
read on the main actor before a detached read (L7); placement judged in Swift
(`icewatch placement`) instead of zsh; a tag parameter for `ask` instead of the
literal tags; one awk helper for the shown reason; a `write_env` helper in the
tests. Tests after round 2: IceCore 471 / 53; MenuBarDiscovery 86 + 70;
MenuBarCapture 30; `IceWatchCoreTests` 46; `test-t7.sh` 127; coverage
`ApplicationMenuReader` 100 %, `LiveApplicationMenuAXReader` 91.3 %,
`ApplicationMenuHitRule` 100 %, `BarRect+CoreGraphics` 100 %; app builds; A3/A4,
A8, A10 pass; `icewatch menu-frame` live `fits`.

## 10. Second attempt and a baseline diagnostic (2026-10-07)

- E11 (MEASURED, run `20261007-160812-t7`, `icetest`, `d992dfa`, evidence copied
  to `~/IceReverse-evidence/20261007-160812-t7/`, `diff -r` identical): the F1 fix
  held (no `menuUnreadable`; `menu-frame` passed in the guard); the helper was on
  the bar (`x=1316`); Ice: `checking` 16:08:13.67 -> `shown(noMembers)` ->
  `checking` 16:08:15.85 -> `IceBar baseline: ok false` 16:08:19.68 ->
  `shown(cannotAssess)`; `run-t7.sh` stopped the phase as F2 says; restore
  `verified`, helper domains empty.
- E12 (INFERRED, Codex): the baseline ran its whole 3.8 s (1 s warm-up plus the
  four-sample baseline), so the early skips (geometry, divider plan, room,
  preflight) are out; left: a baseline rejection of the member, a late
  `skip(noReference)`, a plan skip / no checkable target, or a capture failure.
  `Failed item image cache` is in older owner-account runs where capture
  worked, so it says nothing here. Which one: TBD.
- Change, diagnostic only (the owner agreed, after a Codex debate that agreed):
  `HiddenLengthObserver.takeBaseline` returns a `BaselineCoverage` (covered, or
  why not: the skip reason, no targets, cancelled, or the counts of plan skips
  and rejections by reason with the target and checkable counts); only
  `covered` keeps the baseline, exactly as `covers` did. The coordinator logs
  `IceBar baseline: ok <bool> coverage <description>` (reasons and counts only,
  no item names); `t7_summary` prints the reasons. Tests first.
- Then: rebuild, restage, the owner runs `run-t7.sh --phase 1` only.

## 11. Third attempt: no reference, and one sitting that tells more (2026-10-07)

- E13 (MEASURED, run `20261007-182404-t7`, `icetest`, `ef5b37b`, evidence copied,
  `diff -r` identical): `IceBar baseline: ok false coverage skip(noReference)
  targets=3`. Section 10's diagnostic named the cause in one run.
- E14 (MEASURED, code): a reference is a non-positional on-bar item between the
  hidden divider and Ice's icon (`CheckPlan.swift:47-80`). `run-t7.sh` launched
  only hidden members and `icetest`'s bar has system items only; T0's roster had
  three visible helpers (`IceBarRunCore/Roster.swift:50`). A gap in T7's design
  (section 10 of the build plan), not in Ice. Why three targets with one
  helper: TBD (the references report below lists the layout).
- Product limit, to `STATUS.md`: IceBar hiding needs at least one identifiable
  third-party item in the visible section; a bar with system items only is not
  supported.
- Decision (Codex debate: do not rehearse on the owner's bar -- another layout
  predicts nothing here and the isolation is the point; no harness can reach
  `active` outside the logged-in session): stay in `icetest`, make each sitting
  cost one command and no typing until Ice hides, and collect more per sitting.
- G1 references: two reference helpers (`vz-t7-ref1`, `-ref2`, `Target.app`,
  `--autosave`, lifetime = the run's) are launched before Ice, with a preferred
  position between Ice's icon (0) and its hidden divider (1)
  (`ControlItem.swift:712-717`); whether macOS 27 honours that is not known, so
  it is checked, not assumed: `icewatch references` runs one read-only
  discovery pass and applies Ice's own rule (extracted as
  `CheckPlan.geometricReferenceCandidates`, used by `CheckPlan.make` too). No
  reference -> the owner is asked, in the same sitting, to Command-drag one
  bracket icon to just left of Ice's icon (up to three tries); still none ->
  the run stops with the layout recorded. `vzhelper`'s lifetime cap goes from
  1800 s to 10800 s for these.
- G2 smoke first: a run without `--phase` first does phases 1-3 with no
  question (members, placement gate, wait for `active`, placement after, a
  capture of the bar strip only before and after), goes on to the next k when
  one fails, and only if all three reach `active` starts the checklist;
  otherwise it reports and ends with status 3. `--phase n` skips the smoke.
- G3 `shown(noMembers)` and `shown(unstableLayout)` join the statuses that stop
  a phase after the grace (both end hiding; `noMembers` is also a normal first
  status, hence the grace, not at once).
- The owner no longer pastes anything: the run directory is read from
  `/Users/Shared/IceReverse-t7/evidence/`.

## 12. Section 11 as built (2026-10-07)

MEASURED in the owner's account; nothing ran on a bar. Tests first, except
`ReferencesReport`, written with its tests in one step.

- Built: `CheckPlan.geometricReferenceCandidates` (the inline filter, moved);
  `ExternalReferenceCheck` (IceCore: Ice's rule asked from outside Ice, all
  three of Ice's control items left out); `icewatch references`
  (`ReferencesReport`: counts on the Terminal and in the report, the full
  line with other apps' item namespaces in the run directory only);
  `run-t7.sh`: two reference helpers before Ice, `reference_gate` (six reads,
  then up to three owner drags, six reads after each), the smoke pass
  (`s1`-`s3`, a stopped phase recorded and the next k still run), a bar-strip
  capture before / at `active` / at a stop (`CAPTURE`, 0 in the tests), the
  layout recorded again before each wait and at each stop, `noMembers` and
  `unstableLayout` as stops after the grace; `vzhelper` lifetime cap 10800 s.
- Codex review, one round: 1 P0 (Ice's always-hidden divider passed for a
  reference: the gate could pass and Ice still fail), taken with a test; 4 P1
  taken (reads after a drag, an incomplete pass is not a pass, the layout
  before the wait and at a stop, the capture's size noted; the display
  identity not taken: one display). Not sent back (cap).
- Open, to be read from the next run's `references.txt`: the last run had
  three hidden members with one helper launched, so two other identifiable
  third-party items sit in `icetest`'s hidden section; they are members too
  and may fail coverage or change the cell count.
- Not known until run: whether macOS 27 honours the preferred positions (the
  owner's drag is the fallback); everything from the baseline to `active`.
- Tests: IceCore 479 / 55; MenuBarDiscovery 86 + 70; MenuBarCapture 30;
  `IceWatchCoreTests` 49; `test-t7.sh` 153 (about 5.5 min); coverage
  `CheckPlan` 100 %, `ExternalReferenceCheck` 100 %; app and probes build; A3/A4,
  A8, A10 pass. Not repeated: the full probes run (56 min): its other bundles
  do not touch `icewatch`'s commands, `vzhelper`'s lifetime guard or the two
  reports; stated, not hidden.

## 13. Fourth and fifth attempts: Ice's icon left of its divider (2026-10-07)

- E15 (MEASURED, runs `20261007-201416-t7` and `20261007-201704-t7`, `icetest`,
  `cfef1d0`, evidence copied): `references.txt` shows Ice's hidden divider at
  x 1469 and its icon's middle at 1297.5 -- the icon LEFT of the divider. So
  the interval `CheckPlan` looks in (right of the divider, left of the icon)
  is empty: no reference can exist, wherever a helper is dragged. The two
  reference helpers sat right of both (1493, 1521). The runner's instruction
  ("drag right, to the left of Ice's icon") assumed the opposite order and
  could not be followed; the owner said so. The owner's three drags could not
  have worked.
- E16 (MEASURED, owner's account, macOS 27.0.1 26A434, sacrificial helpers
  only; `postmortem/preferred-position-results.txt` in run `20261007-201416-t7`):
  an `NSStatusItem Preferred Position` of 0 is read as none (the item lands
  leftmost); positive values order items from the right, smallest rightmost
  (0.001, 0.1, 0.5, 1, 2). One of seven trials kept that order but off the bar
  to the left: TBD. Upstream seeds Ice's icon with 0 and its hidden divider
  with 1 (`ControlItem.preflightSetup`), which on 27 gives E15.
- E17 (MEASURED, same record): a rehearsal with stand-ins carrying Ice's AX
  identifiers, the run's two reference helpers and a member, then
  `icewatch references`: icon seed 0 reproduces E15 (divider 1465, icon 995,
  references 0); icon seed 0.1 gives divider 1437 | references 1465, 1493 |
  icon 1528, references 2, the member left of the divider.
- Fix: `ControlItemPositionSeed` (IceCore, tested): on macOS 27 the icon's seed
  is 0.1, and a stored 0 is seeded again; the divider's 1 and earlier systems
  are unchanged. `ControlItem.preflightSetup` calls it;
  `a10-ControlItem.expected` follows. A real defect of a fresh Ice on 27, not
  of the test.
- Runner: an icon left of the divider is said as such and ends the run without
  asking for a drag; the drag instruction names no direction and says how to
  recognise Ice's icon.
- Also read from E15: the two other hidden members are Apple's input menu
  agent and `com.apple.campo` (basis `unnamed`, so targets and possible
  references). With the fix they are expected left of the divider, i.e.
  members of the hidden section beside the helpers: the cell counts of rows
  3, 8 and 9 will be k + 2 unless they are moved, and a baseline rejection of
  either would stop coverage (the coverage line would name it).
- Codex (`review --uncommitted`): 0. Tests: IceCore 483 / 56; MenuBarDiscovery
  86 + 70; MenuBarCapture 30; `test-t7.sh` 155; `ControlItemPositionSeed` 100 %;
  app builds; A3/A4, A8, A10 pass.

## 14. Sixth attempt: the system remembers where items were dragged (2026-10-07)

- E18 (MEASURED, run `20261007-211145-t7`, `icetest`, `53696d1`, evidence
  copied): the run ended at the gate in 8 s: divider 1525, icon 1353.5,
  reference helpers at 1288 and 1316 -- to the half point where the owner's
  drags had left everything in run `20261007-201704-t7`, although the runner
  deletes Ice's and the helpers' defaults domains before it launches
  anything. Section 13's seed (0.1) had no effect there. The assistant had
  told the owner no drag would be needed, on a rehearsal with names the
  system had never seen: an unfounded claim, and a sixth wasted sitting.
- E19 (MEASURED, owner's account, read-only): MenuBarAgent keeps
  `TrailingItemPreferredPositions` in `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist`,
  keyed `status:<bundle id>::<autosave name>` (`::Item-<n>` without a name),
  e.g. the release Ice's two control items. Today's sacrificial helpers,
  never dragged, have no entry there, and their app-side seeds were honoured.
- E20 (INFERRED from E18 + E19): once the user Command-drags, the agent
  records positions there and they override the app's own
  `NSStatusItem Preferred Position`; `icetest`'s record pins Ice's icon left
  of its divider. Not read in `icetest` (a read of another app's group
  container from Terminal may raise a consent prompt and block an unattended
  run), so the record itself is unseen.
- E21 (MEASURED, owner's account, sacrificial helpers, fresh names): divider
  stand-in (1) 1437 | reference (0.6) 1465 | reference (0.4) 1493 | icon
  stand-in (0.1) 1521. Two items with an autosave name and no seed landed on
  the same x (972): stacked, which `CheckPlan` skips -- so members keep no
  autosave name.
- E22 (MEASURED, `icetest`, every run's helper logs): a helper with its own
  bundle id, started by path from Terminal, reports `trusted: true`; consent
  follows Terminal. For a re-identified Ice: INFERRED.
- Change (Codex debate: a new identity, not an edit of the agent's store,
  which `cfprefsd` or the running agent may overwrite): `stage-t7.sh` gives
  the staged copy of Ice the bundle id `com.icespike4.ice` (Info.plist,
  `codesign --force --deep -s -`, verified) and stages that as `DOMAIN`; the
  XPC service keeps its id (its connection already fails on 27 in every T7
  log and `Shared/` is not to change). Reference helpers get the run's time
  in their name. Before each wait the runner checks, with Ice's own rule,
  that a reference is still there and every member is on the hidden side.
  The staged copy no longer shares the release's preferences domain.
- Product gap, to `STATUS.md`, not built: a user whose record pins the
  inverted order (a fresh Ice on 27, then any drag) stays broken despite the
  seed; Ice should detect its icon left of its divider and say how to repair
  it (Command-drag the icon to the right of the divider).
- Unverified until a run in `icetest`: that a fresh bundle id is really
  placed by its seeds there; that the re-identified Ice passes its permission
  checks; everything from the baseline to `active`.
- Tests: `test-t7.sh` 160; IceCore 483 / 56 unchanged.

## Appendix: plan review

| Round | Finding | Ruling |
|---|---|---|
| 1 | P1 E9 (now E10) wrong: row 1 does not wait | taken: E10 corrected, F2 `wait_for_phase_status` |
| 1 | P1 F2 underspecified; the stub always logs `active` | taken: per-test status sequences, cases in section 4 |
| 1 | P1 F3: `frames` has no position; `selfread` is asynchronous | taken: `selfread` only, bounded wait, `unknown` |
| 1 | P1 F4: `icewatch` lacks `MenuBarDetectorFeed` | taken: dependency, strict JSON check |
| 1 | P1 F1 threading, timeout, non-finite children, multi-display | taken: pid snapshot on the main actor, 0.25 s timeout, per-child skip; multi-display by fake only (one display) |
| 1 | P1 five other call sites untested; add a manual smoke checklist | taken in part: each call site's reach under T7 read from the code (F1 table); no extra owner checklist, since none but the hover path is reached in T7 and that path's change restores upstream behaviour |
| 1 | P2 E4/E5 not reproducible | taken: probe re-run 3x, source and output saved under the run's `postmortem/` |
| 1 | P2 E8 overstated | taken: split into E8 (report) and E9 (INFERRED) |
| 2 | P1 the overlay also reads from a detached task; a pid snapshot only in the coordinator does not cover it | taken: `MenuBarOwnerPID` holder, main-actor KVO, read from any thread |
| 2 | P1 an off-bar helper is recorded but the phase goes on | taken: the first snapshot gates the phase (F3) |
| 2 | P1 the reached click path has no check | taken: owner row 1b (F2b), one click |

| 3 | P1 the KVO holder has no initial read: a cold launch without an owner change keeps nil | taken: created in `AppState.init`, immediate read, KVO `.initial`, test of the immediate value |
| 3 | P1 F3 "on the bar" = finite and in the display, not in the bar band | taken: own child by identifier, full frame inside the bar band |
| 3 | P1 row 1b answered before the async IceBar could appear; the script test does not cover the regression | taken: 3 s watch before the question. Modified: the HID-level test becomes a test of the extracted containment predicate in IceCore (the app has no test target) |

| 4 | F1, F3, F2b's 3 s wait resolved. P1 the predicate test does not prove the left-edge widening, nor that the HID method uses the helper | taken as Codex prescribed: a widening case and a thin direct call; row 1b stays the end-to-end check |

Trend: round 1 6 P1 + 2 P2, round 2 3 P1, round 3 3 P1, round 4 1 P1 (with its own
fix, taken verbatim), 0 P0. Rounds 3-4 were run at the owner's request
(`/fatboyslim 那去審核啊`). Round 4's fix was not sent back: it is Codex's own
prescription, and the code goes through /simcodex. Plan final.
