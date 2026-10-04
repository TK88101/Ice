# IceBar on macOS 27: build it (best effort, no certification)

2026-10-03 · final (Codex round 2: CONVERGED) · to be implemented on `wip/icebar-build` cut from
`main` after route C's records are merged.

Labels: MEASURED (file:line, run id) or INFERRED (reasoning). TBD = unknown.

## 0. Decision this plan follows

Route C tried to *prove*, before building, that Ice never wrongly claims items are
hidden; that proof cannot be built on macOS 27 (`2026-10-03-icebar-c-deviation6.md`,
converged with Codex). The owner then chose (2026-10-03) to stop proving and build
IceBar as a best-effort feature with known limits, judged by using it. This plan does
not reopen route C; it reuses its measurements as engineering input only.

## 1. Goal and non-goals

Goal (the owner's): on macOS 27, items that do not fit (and would cross the notch and
summon `«`) live in the IceBar below Ice's icon; the owner can add and replace which
items live there; clicking an item in the IceBar opens that app's menu.

Behaviour on macOS 26 and earlier: unchanged (every change is behind
`#available(macOS 27, *)` or a `.accessibility` item source).

Non-goals: any certification or "never wrong" guarantee; S2-S5 of route C; moving
items by synthetic events (refused on 27, `MenuBarItemManager.swift:1490-1493`);
live item images (no per-item windows on 27, MEASURED); a second display.

Known limits, stated to the owner up front (INFERRED from measurements):
- a frontmost app whose menus cross the notch: hidden items come back to the bar and
  the IceBar is not offered (C2: the fold is unreadable there, MEASURED
  `20260929-234942-c2A`);
- IceBar cells show the owning app's icon in monochrome (route C F2, owner accepted
  2026-09-30), not the item's own image;
- now and then an item may peek or a `«` may appear without Ice noticing; frequency TBD,
  judged by use.

## 2. What exists and what is missing (MEASURED unless marked)

| piece | today on 27 | needed |
|---|---|---|
| item discovery and sections | AX discovery, sections follow Ice's dividers (`STATUS.md`) | -- |
| IceBar panel, its item list and click handlers | present (`IceBar.swift`), positions by AX on 27 (`IceBar.swift:159-167`) | -- |
| hiding the hidden section | control item expands to `Lengths.expanded = 10_000` (`ControlItem.swift:34-44`), which on 27 gives room back and hides nothing (FINDINGS "Hiding by spacing") | a length in the no-fold band |
| IceBar cell images | `imageCache.images[item.tag]` (`IceBar.swift:452-456`), always empty on 27 | app icon fallback |
| clicking a hidden item | `click` / `temporarilyShow` refuse a non-window item (`MenuBarItemManager.swift:1490-1493`, `:1625-1629`) | AX press |
| add / replace members | the owner Command-drags items across Ice's divider on the bar (native, route C F4, owner accepted) | -- (sections already follow) |

Hiding band, MEASURED: one helper, owner's bar, 616-840 pt hid without `«`, 5/5 at
728 (C1, `20260928-202509-vzc1`); safe-width probes: target hidden with no fold from
656 to 836 pt, the same for frontmost menus ending at 72, 440 or 758 pt (FINDINGS
"The safe width"). Below the band the hidden item folds (`«`); above it, it is drawn
again. How the band moves with k > 1 hidden items and with the owner's real item set:
TBD (spike A).

## 3. Design

**Product rule (r1).** On 27 IceBar mode supports **one** section, Ice's hidden
section; the always-hidden section stays shown (standard length) on 27 because two
expanded spacers are unmeasured (FINDINGS). Hiding is **all-or-nothing**: either every
hidden-section item is hidden cleanly and the IceBar lists them, or the section is
shown on the bar and the layout pane says why (long menu, no clean length found, an
item that cannot be assessed). Ice never hides part of the owner's selection silently.
Capacity is what the band allows (spike A); beyond it the section is shown, with the
reason.

All new logic is pure and tested in `Packages/IceCore` (new files only; the ten frozen
detector files and `Packages/MenuBarCapture` stay untouched); Ice wires it.

### D1 Hidden length on 27: a calibrated band, not 10 000
- `HiddenLengthCalibrator` (IceCore, pure): given a sequence of observations
  `(length, outcome)` where outcome is `folded` (a `«` is on the bar), `hiddenClean`
  (no `«`, and no hidden-section item drawn), `drawn` (some hidden item drawn) or
  `unknown`, it proposes the next length to try and, once the band edges are bracketed,
  the length to rest at (midpoint, as C1/C2 did). Start from the last good length;
  coarse 16 pt steps; give up after a bounded number of steps (constant, tested) ->
  "cannot hide here" (items shown).
- Observation source (Ice, live), through an adapter (r1): `«` from AX (`MenuBarAgent`
  on-bar frame 17.5 +- 0.5 pt, the frozen width rule, `FoldWitness`); "drawn" from the
  existing `HidingVerifier` path, which needs a shown baseline and may refuse items
  (`AppState+HidingCheck.swift`). The adapter takes a **fresh shown baseline of every
  hidden-section item** before a calibration, exposes per-item refusals, and reports
  `hiddenClean` only when the fold read is readable, no `«` is listed, and **every**
  member is positively assessed absent; any refusal, unreadable read or missing item ->
  `unknown` -> fail open (section shown).
- When (r1): any change of the layout signature (the discovered item set and order,
  the frontmost app and its menu width, the display, a Space change, the capture
  indicator appearing) **immediately restores the standard length and invalidates the
  calibration**; Ice recalibrates only after a quiet period (constant) with an unchanged
  signature, and never while the user is interacting with the bar. A good length is
  reused only for the identical signature.
- Long menus: if the frontmost app's menu frame crosses the notch's left edge
  (`screen.getApplicationMenuFrame()`, already used by Ice), the hidden section is shown
  (control item at standard length) and the IceBar is not offered until the menus are
  short again.
- On 26 and earlier `Lengths.expanded` stays.

### D2 IceBar cell image on 27
- For an item with `.accessibility` source and no cached image: the owning app's icon
  (`NSRunningApplication(processIdentifier:).icon`), drawn as a template (monochrome,
  tinted by the IceBar's text colour, as `IceBarColorManager` gives it); if none, the
  item's AX title or a generic glyph. A small pure helper chooses which (tested).

### D3 Click on 27
- `IceBarItemView` on 27: `AXUIElementPerformAction(element, kAXPressAction)` on the
  item's AX element (FINDINGS: third-party items expose `AXPress`) while it is pushed off.
  Spike B fixes, before any code (r1): whether the press opens the item's menu on screen
  while in the band, how the menu is detected (window owner pid and level), the timeout
  (1 s), and what happens on failure. If spike B validates a fallback (show the section,
  press the item on the bar, re-hide when the menu closes), it is shipped only with a
  hard timeout, cancellation on any layout-signature change, and a restore that always
  returns the section to its pre-click state; otherwise a failed press leaves the bar as
  it is and the cell shows "cannot open on macOS 27" (disabled), never a half-done
  fallback.

### D4 Settings and messages
- The layout pane shows one persistent line on 27 (r1): IceBar active / shown because
  of a long menu / shown because no clean length / shown because an item cannot be
  assessed, plus the limits (app icons, long menus). No new controls.

## 4. Tasks (TDD; each test seen failing first)

| # | task | DoD |
|---|---|---|
| T0 | spikes, **in the isolated account `icetest`** (r1: a spacer sweep relayouts whatever bar it runs on, so never the owner's bar first), helpers only (`com.icespike4.*`), started by the owner at a time the owner names, with the release-Ice preference export/restore if Ice runs: **A** with 1, 2, 4, 8 hidden helpers and short/mid menus, step a spacer from rest in 16 pt and record `«` (AX) and drawn (pixels) per step -> the band per k; **B** `AXPress` on a pushed-off helper (vzhelper given a one-item menu) -> does its menu open on screen within 1 s; if not, the show-press-rehide fallback. Evidence under `~/IceReverse-evidence/<run id>/` | a short report: band per k (or none), click path that works (or none); **stop for the owner** if A finds no band for k = 1 or B finds no click path |
| T1 | `HiddenLengthCalibrator` tests (bracketing, midpoint, give-up bound, `unknown` handling, restart from last good) red -> green | `swift test` in IceCore; coverage >= 80 % of the new file |
| T2 | long-menu rule tests (menu frame vs notch) red -> green | as T1 |
| T3 | icon-choice helper tests red -> green | as T1 |
| T4 | Ice wiring: `ControlItem` length on 27 from the calibrator; observation source; triggers and rate limit; long-menu show | builds; existing tests green |
| T5 | IceBar image fallback (D2) | builds; view shows icons in a manual check |
| T6 | click on 27 (D3), the path(s) spike B validated | builds; manual check on helpers |
| T7 | E2E on helpers in `icetest` (the local Ice build launched there by the owner): IceBar shows the hidden helpers, a click opens each helper's menu, long-menu app -> items shown, back to short -> hidden again; release Ice's preferences exported before and restored after (project memory) | checklist results recorded |
| T8 | owner trial on the owner's real bar, started by the owner; preflight: release-Ice preferences exported; abort = quit the local Ice (its control items return to standard length on quit, `ControlItem.swift`), then restore the preferences; bound: Ice changes only its own control items' lengths | owner's verdict |
| T9 | Phase 3 review (/simcodex), full tests, SwiftLint-compatible style (`.swiftlint.yml`) | green |

Order (r1): T0 first; T1-T3 only for what T0 validated. Parallel candidates: T1-T3 are independent pure units (exclusive files
`Packages/IceCore/Sources/IceCore/{HiddenLengthCalibrator,MenuWidthRule,IceBarIconChoice}.swift`
and their tests; setup none; test `swift test --filter <Suite>`); everything else is a
chain.

## 5. Acceptance

| # | check |
|---|---|
| AC1 | on 27, with helpers in `icetest`: entering IceBar mode hides the hidden-section helpers with no `«` (pixels and AX), at least 9 of 10 toggles, for k = 1, 2, 4; with more members than the band allows, the section is shown and the pane gives the reason (all-or-nothing, no partial hiding) |
| AC2 | IceBar lists every hidden-section item with an icon; clicking each opens its menu within 1 s, 9 of 10 |
| AC3 | a long-menu frontmost app shows every item on the bar; returning to a short-menu app hides them again after the quiet period; a new item appearing restores the standard length at once |
| AC4 | macOS 26 code paths unchanged (diff review: every change behind `#available(macOS 27, *)` or the `.accessibility` source) |
| AC5 | frozen files untouched (`docs/plans/checks/check-a3a4.sh`); unit coverage >= 80 % on new IceCore files; app builds (`xcodebuild … CODE_SIGNING_ALLOWED=NO`) |
| AC6 | the owner tries it on the real bar and says whether it is good enough |

## 6. Risks and rollback

- R1 (TBD, spike A): the band shrinks or vanishes as k grows or with the owner's real
  items -> IceBar holds only as many items as fit the band; reported, not hidden.
- R2 (TBD, spike B): no click path works on 27 -> IceBar shows items but cannot open
  them; stop and tell the owner before T4.
- R3: the calibration steps are visible (items flicker for a moment) -> rate limit,
  run only on the triggers in D1.
- R4: the release Ice in `/Applications` shares the bundle id and preferences ->
  export before every local run, restore after.
- Rollback: the branch; every change is additive behind the 27 check.

## 7. Implementation notes

| # | date | note |
|---|---|---|
| 1 | 2026-10-03 | **T0 design, as built** (branch `wip/icebar-build` from `b155aab`; the owner asked for T0 only, the plan not re-reviewed). Two commands in `vizprobe` (`spike-run`, `spike-dry`), a pure `SpikeCore` target (tested) and a `SpikeStage` target driven through route C's `IceBarEnvironment` seams (tested on a fake bar); new files only, the frozen detector files and `Packages/MenuBarCapture` untouched. **Spike A**: profiles k = 1, 2, 4, 8 x menus short, mid (C2's width classes); roster as route C S1 (3 visible helpers, the spacer, k members, Menus; placement `placed` MEASURED `20261003-134859-icebar`); lengths 408-1000 pt by 16, on C1's grid (vzhelper's cap is 1000; C1's 616-840 lies inside; k = 8 needs more push), each a **jump from rest** as C1 did (AX reads differ by path, FINDINGS), with a rest control between lengths. A length is `hiddenClean` iff, in two brackets 0.5 s apart after a 1 s settle: AX lists no on-bar 17.5 pt `MenuBarAgent` frame (`ChevronRule.fromAX`), the oracle sees no `«` (K1 template) and no member glyph, every visible helper is drawn, no ambiguity, and the restore control shows every member again; any refusal is `unknown`, never clean (fail closed). Band = the widest contiguous clean run; midpoint = its rounded middle. Not used: route C's claim, `HiddenBaseline`, `OverlapGuard` (C3 cannot hold on 27: no per-item windows, sitting record row 4) and `BControl`. **Spike B**: the k = 1 short profile's midpoint (mid if short has none); the member launched with vzhelper's new `--menu` (one-item `NSMenu`, `menuWillOpen`/`menuDidClose` reported on stdout, `closemenu` cancels tracking); the controller performs `kAXPressAction` on the member's `AXExtrasMenuBar` child from a background thread (the call may not return until the menu closes) and watches, for 1 s, the helper's `menu open` line and the window server for a window of the helper's pid at the pop-up menu layer (101); 5 trials, a path works at 4/5; if the pushed-off press fails, the fallback (rest, press, re-hide) is tried the same way. **Stop rules** (T0 DoD): no band at k = 1 in either menu -> B is not run and the owner is asked; no click path -> the owner is asked. Staging: `stage-spike.sh icetest` -> `/Users/Shared/IceReverse-spike` (its own directory; route C's staging is left as it is), `run-spike.sh` is the one command; evidence `<ts>-spike` under the shared evidence directory, copied by the owner to `~/IceReverse-evidence/`. Side effect noted: `Package.swift` and `vzhelper/main.swift` change, so route C's `icebarfreeze verify` (pre-S0 manifest v2) no longer passes; route C is closed, nothing re-runs under it |
| 2 | 2026-10-03 | **T0 built and reviewed** (MEASURED in the owner's account, nothing launched). Tests: `SpikeCoreTests` 29, `SpikeStageTests` 8 (the real stage on a fake bar, about 4 min: the oracle's search dominates), red before green. Phase 3 (/simcodex, cap two rounds, early exit after round 2): round 1 simplify 4 P1 + 7 P2 fixed (band by `C2Band.band`, the oracle's `ChevronSighting`, `Roster.maxMembers` and `C2Band`'s bounds instead of literals, one two-bracket read, the reply seam checked once and fail-closed, spike B's missing-result reasons in one `SpikeVerdict`, cadence from `CadenceParameters.preRegistered`, concurrent oracle labels), Codex (`review --base main`) 0 findings, security review 0 CRITICAL/HIGH/MEDIUM + 1 LOW fixed (the run directory is created strictly, as `icebar-run`); round 2 simplify 0 P1 (6 P2: a `SpikeBStatus` enum instead of `b`/`bProblem`/`runB`, `SpikeVerdict` as a struct, `PressSubject` unpacked, `[CaptureLabels?]` compactMap, the fake bar redrawn per capture, settle shim placement -- three one-liners taken, the rest deferred), Codex (`review --uncommitted`) 0. Checkpoints `edf1eba`, `e31cec8` on `wip/icebar-build`. Staged with `stage-spike.sh icetest`: `/Users/Shared/IceReverse-spike` (`apps/vizprobe` sha256 `79d23b381c82c446…`, `run-spike.sh` `ecd9654c2ddaeb78…`, geometry `1728x32:771.5-956.5`, `evidence` 0777 and empty); `spike-dry` exit 0 (vzhelper knows `--menu`/`closemenu`, 19 glyph templates + K1 chevron 29x27, scale 2, 8 profiles, 38 lengths 408-1000); no `vzhelper` process before or after. **Stopped for the owner's time.** Expected run: about 25 min (8 profiles x about 2.7 min + spike B); watchdog 90 min; helpers die with the controller |
| 3 | 2026-10-03 | **The owner's steps** (in `icetest`, at the time the owner names; the same settings as route C's sitting): Terminal has Accessibility and Screen Recording; the bar shows only system items; screen lock off; the Mac on power. Run exactly `/Users/Shared/IceReverse-spike/run-spike.sh`; leave the Mac untouched and do not switch accounts until the last line `結果：…` appears (the two answer lines come right before it). Then, in the same Terminal, `defaults read com.icespike4.target; defaults read com.icespike4.protected` (expected empty or "does not exist"), switch back, and tell Claude the last three lines and the two `defaults` results. Ctrl-C ends the run on its normal path (helpers quit, the spacer rested); never `kill -9`. Afterwards Claude copies `/Users/Shared/IceReverse-spike/evidence/<run id>` to `~/IceReverse-evidence/<run id>/` (`ditto`), verifies `run/manifest.final.json`, and records the band per k and the click path here and in `STATUS.md` |

| 4 | 2026-10-04 | **T0 result** (MEASURED, `icetest`, macOS 27.0.1 26A434, run `20261004-105226-spike`, started by the owner 10:52, 20 min 50 s; evidence copied to `~/IceReverse-evidence/20261004-105226-spike`, `ditto` + `diff -r` identical, `run/manifest.final.json` 1855 files, 0 sha256 mismatches). **Spike A**: every profile (k = 1, 2, 4, 8 x short, mid) has the same band, 632-840 pt (14 clean lengths of 38), so capacity is at least 8 in both menus (16 not measured). **Spike B** at 736 pt (k = 1 short midpoint): path `pushedOff`, 5/5 opened, first sign 10.5-14.5 ms after the press, both signs (helper `menu open` and a layer-101 window) each time, `AXError` 0, menu closed each time; the fallback was not needed. Stop rules: neither fires; T1-T3 may follow. Afterwards: both helper domains `{}` in `icetest` (owner's `defaults read`), no `vzhelper` in the owner's account |

| 5 | 2026-10-04 | **T1-T3 built** (MEASURED, owner's account, nothing launched; uncommitted on `wip/icebar-build` at `7261666`). Section 8 reviewed by Codex in two rounds (2 P1 + 1 P2 -> CONVERGED). Six new files in `Packages/IceCore`, each suite seen red against a stub before green; one test expectation was wrong (edges 616/856 are on T0's grid, not the grid anchored at 736) and corrected with the plan. Phase 3 (/simcodex, cap two rounds): round 1 simplify 2 P1 (the trim re-used `IdentifierText.trimmed`; the `Result`/`Refusal` wrapper replaced by `isUntrusted` + an optional history) and 3 P2 taken, Codex 1 P2 taken (proposals and accepted observations now share one bound policy, `Grid.inLimits`; test seen red first); round 2 simplify 2 P1 in tests taken, Codex 0. Tests: IceCore 407 in 47 suites green; coverage 96.1 % / 100 % / 100 % (calibrator / menu rule / icon choice); MenuBarDiscovery and MenuBarCapture green; app builds (`CODE_SIGNING_ALLOWED=NO`); `check-a3a4.sh` passes. Probes (`docs/macos-27/probes/visibility`, untouched by T1-T3): 6 test bundles green (13, 8, 29, 44, 25, 97 tests), `IceBarCorpusTests` not run -- the run was stopped (SIGTERM) at a 60 min cap because the 25-test bundle took 2677 s instead of about 7 min (INFERRED: CPU contention with another project's `swift test` running at the same time). Deferred P2: one helper for the three outcome filters; `private` for `Grid`/`decide`/`approach`; integer index limits in `Grid` (16 pt steps are exact, so no misfire today); `IdentifierText` named for identifiers but used for a title; redundant `isFinite` checks kept to mirror rule 1 |

| 6 | 2026-10-04 | **T4-T6 built** (MEASURED, owner's account, nothing launched; on `wip/icebar-build` from `35d705b`). Section 9 reviewed by Codex round 1 (1 P0 + 5 P1 + 2 P2, all ruled, see the Appendix); round 2 stopped on Codex's usage limit and was replaced by the main session's re-read (stated there), with a Codex re-run queued after 14:11. Deviations from section 9, each for testability or a fact found while building: the observer (`HiddenLengthObserver`) and the AX-only `ChevronReader` live in `MenuBarDetectorFeed`, not `Ice/`, so they are tested on the package's fakes; `PressOutcome` (IceCore) decides a press: success, or a messaging timeout after >= 1 s (the menu was up, T0), is accepted, anything else fails -- section 9.5's three values reduce to "pending until the call returns, then accepted or failed"; `observed` carries the outcome only (the machine knows the length it asked for); a rest dwell (1 s) separates two trials; the icon is desaturated but not tinted (a multiply by the bar's black text would make a silhouette). New files: IceCore `HiddenLengthOutcomeRule`, `LayoutSignature`, `IceBarHidingMachine`, `PressTargetRule` (+ `PressOutcome`); `MenuBarDetectorFeed` `ChevronReader`, `HiddenLengthObserver`; `Ice/MenuBar/IceBar27/` coordinator, presser, fallback glyph, manager extension. Edited: `ControlItem.swift`, `MenuBarItemManager.swift`, `IceBar.swift`, `HidingVerifier.swift`, `AppState+HidingCheck.swift`, `HidingVerificationLive.swift`, `a10-ControlItem.expected`. Each new suite seen red before green. Tests: IceCore 466 in 52 suites green; MenuBarDiscovery 85 + 61 green; MenuBarCapture 30 green; line coverage 100 % (IceCore's four new files), 100 % `ChevronReader`, 97.6 % `HiddenLengthObserver`; app builds (`CODE_SIGNING_ALLOWED=NO`); `check-a3a4.sh` and `check-a10.sh` pass. Not run: probes (untouched), anything on a bar (T7/T8) |

## 8. T1-T3 detail (2026-10-04, after T0)

Scope: three new source files and three new test files in `Packages/IceCore`, nothing
else (no Ice wiring: that is T4-T6; no frozen file; `Package.swift` unchanged). All
types `public`, `Sendable`, `Equatable`; no AppKit/CoreGraphics import (IceCore's rule,
`Package.swift`). Tests use Swift Testing, as the package does. Done in the main
session, one unit after another (each is about a hundred lines; worktrees under the
iCloud-managed `~/Documents` invite duplicate files, project memory).

### T1 `HiddenLengthCalibrator.swift`
- `HiddenLengthOutcome`: `folded` / `hiddenClean` / `drawn` / `unknown` (D1's four).
- `HiddenLengthObservation { length: Double; outcome }`.
- `HiddenLengthParameters { step, minLength, maxLength, defaultStart, maxObservations }`,
  `.standard` = 16 pt, 408, 1000, 736, 24. MEASURED basis (note 4): grid 408-1000 by 16,
  band 632-840, midpoint 736. 24 = the 14 clean lengths + 2 edges + 8 steps of approach
  (INFERRED; a bound, not a measurement). The initialiser checks finite values,
  `step > 0`, `minLength <= defaultStart <= maxLength`, `maxObservations > 0`
  (`precondition`, as `PtSpan`).
- `HiddenLengthProposal`: `tryLength(Double)` / `rest(Double)` / `giveUp(Reason)`,
  `Reason` = `unknownOutcome` / `noBand` / `inconsistent` / `stepBound`.
- `HiddenLengthCalibrator.next(observations:lastGood:parameters:) -> HiddenLengthProposal`,
  a stateless function of the whole observation list (the latest observation of a length
  wins), so the caller keeps no phase:
  1. any `unknown`, or an observation whose length is non-finite or outside
     `[minLength, maxLength]` -> `giveUp(.unknownOutcome)` (fail open, D1);
  2. start = `lastGood` if finite and inside `[minLength, maxLength]`, else
     `defaultStart`; the grid is `start + n * step` (anchored at the start, so a last
     good off T0's 408 + 16n grid is still walked exactly); an observation off that grid
     -> `giveUp(.inconsistent)`; no observations -> `tryLength(start)`;
  3. no clean length yet: only `folded` seen -> try the highest observed + step; only
     `drawn` seen -> try the lowest observed - step; outside the limits, or both kinds
     seen with no clean between them -> `giveUp(.noBand)`;
  4. clean lengths seen, `lo`/`hi` the lowest/highest: **every** grid point from `lo`
     to `hi` must have a latest outcome `hiddenClean` -- an unobserved one ->
     `tryLength(it)`, a non-clean one -> `giveUp(.inconsistent)`; the lower edge is
     bracketed when `lo - step` was observed non-clean or lies below `minLength`, the
     upper likewise with `maxLength`; unbracketed lower -> `tryLength(lo - step)`, then
     upper -> `tryLength(hi + step)`; both bracketed -> `rest((lo + hi) / 2)`, the exact
     midpoint (C1/C2's; inside the verified run, never rounded out of it);
  5. the count of distinct observed lengths reaching `maxObservations` without a `rest`
     -> `giveUp(.stepBound)`.
- Not here (T4): the jump from rest between lengths, the baseline, the signature and the
  quiet period.
- Tests (red first): first proposal is the default start; restart from a valid last
  good, and a non-finite or out-of-range last good falls back; a clean start walks down
  then up and rests at the midpoint (the T0 band from 736 -> `rest(736)`, edges 624 and
  848 tried -- corrected 2026-10-04 from "616 and 856", which lie on T0's 408 + 16n
  grid, not on the grid anchored at 736); a folded start walks up into the band, a drawn start walks down; a run
  reaching a grid limit is bracketed by the limit; `unknown` anywhere gives up at once;
  folded then drawn with no clean -> `noBand`; walking off a limit without a clean ->
  `noBand`; a non-clean between cleans -> `inconsistent`; a missing interior grid point
  is tried, not assumed; an off-grid observation -> `inconsistent`; NaN, infinite and
  out-of-range observation lengths give up; a fractional step rests at the exact
  midpoint; the bound -> `stepBound`; a repeated length keeps the latest outcome; a
  one-length band rests on that length.

### T2 `MenuWidthRule.swift`
- `MenuWidthVerdict`: `fits` / `crossesNotch` / `unreadable`.
- `MenuWidthRule.verdict(menuMaxX: Double?, notchMinX: Double?) -> MenuWidthVerdict`:
  either value missing or non-finite -> `unreadable`; `menuMaxX > notchMinX` ->
  `crossesNotch`; else `fits`. No margin constant: menus ending at 758 pt with the
  notch at 771.5 hid cleanly (MEASURED, FINDINGS "The safe width"), so touching or
  stopping short of the edge fits. A screen without a notch gives `notchMinX == nil`
  -> `unreadable`: IceBar on a notch-less display is unmeasured (non-goal: second
  display), and T4 shows the section for anything but `fits` (fail open).
- Tests: short menu fits; ending exactly at the edge fits; one point over crosses;
  missing menu, missing notch, NaN and infinity are unreadable.

### T3 `IceBarIconChoice.swift`
- `IceBarIconChoice`: `cachedImage` / `appIcon` / `title(String)` / `genericGlyph` /
  `none`.
- `IceBarIconChoice.choose(hasCachedImage:isAccessibilitySource:hasAppIcon:title:)`:
  a cached image wins for either source; otherwise a window-sourced item gives `none`
  (today's behaviour on 26, `IceBar.swift:452-456`: no image, no cell); an
  accessibility-sourced item gives `appIcon` if there is one, else the AX title trimmed
  of whitespace if non-empty, else `genericGlyph`. Truncating a long title is the
  view's concern (T5).
- Tests: each branch, the 26 path unchanged, whitespace-only and `nil` titles fall to
  the glyph, the title is trimmed.

### DoD and acceptance for this step
`swift test --package-path Packages/IceCore --enable-code-coverage --scratch-path
<outside ~/Documents>`: every suite green (old and new); line coverage of each new file
>= 80 % (`llvm-cov report`); each new test seen failing first;
`docs/plans/checks/check-a3a4.sh` passes; `git diff --stat` lists only the six new
files and this plan. Rollback: delete the six files.

## 9. T4-T6 detail (2026-10-04, after T1-T3; from `35d705b`)

Scope: wire the three IceCore units into Ice. Nothing is launched and no live
experiment runs in this step (T7/T8 are the owner's). Done in the main session as one
chain (T4 -> T5 -> T6 touch neighbouring files; no parallel candidates).

### 9.0 Facts the design rests on (MEASURED in the tree at `35d705b`)

- `Ice.xcodeproj` has no test target (targets `Ice`, `MenuBarItemService`). Whatever can
  be decided without AppKit therefore goes into new `Packages/IceCore` files and is
  tested there; the Ice side stays thin adapters, checked by the build and by T7.
- `ControlItem.Identifier.length(for:)` (`ControlItem.swift:34-44`) is the only place a
  length is chosen; `updateStatusItemVisibility` (`:414-436`) applies it.
- In IceBar mode `MenuBarSection.show()` keeps the hidden and always-hidden control
  items at `.hideSection` and opens the panel (`MenuBarSection.swift:164-190`), so the
  hidden control item is `.hideSection` for as long as IceBar mode is on.
- `HidingVerifier` only reports `skip(.iceBarMode)` in IceBar mode
  (`VerificationTrigger.swift`), so it takes no captures there. Its seam,
  `HidingVerification.prepare`/`verify` (`MenuBarDetectorFeed`, not frozen), gives a
  shown baseline and per-item `SectionItemCheck`; `verify` warms up with 24 captures
  0.25 s apart (6 s) before it reads.
- `MenuBarAgent`'s items are never discovered items (`ItemCatalog.swift:14`), so the
  capture indicator is not in `itemCache`; capturing the bar summons that indicator
  (FINDINGS, 2026-09-19).
- `DiscoveredFrameReader.read(items: [:])` returns `MenuBarAgent`'s frames without a
  capture; `FoldWitness.isChevron` is the 17.5 +- 0.5 pt rule.
- The expanded hidden divider pushes everything left of it, the always-hidden divider
  and its items included; T0's members were all of those (k up to 8).
- `IceBarContentView` shows "Unable to display menu bar items" when no item of the
  section has a cached image (`MenuBarItemImageCache.swift:342-355`), which is always
  the case on 27.
- On 27 a divider decides sections only while its control item is `.showSection`
  (`MenuBarItemManager.swift:129`, `DiscoveredCachePlan.swift:187`: `.expanded` ->
  no boundary); otherwise an item keeps its previous section and a new one defaults to
  visible (`:123-146`). In IceBar mode the dividers are `.hideSection` throughout, so
  today the hidden section's membership is never refreshed there (r1 of this section).
- `check-a10.sh` (the 2026-09-23 plan's acceptance) pins the diff of `ControlItem.swift`,
  `AppState.swift` and the layout pane against `af4baf1`; it passes today.

### 9.1 Assumptions (stated, not asked)

- A1. The calibrated length applies on 27 **only in IceBar mode**. With IceBar mode off,
  27 behaves as it does today (10 000, which hides nothing, STATUS). Basis: D1/r1 speak
  of IceBar mode; the goal is the IceBar.
- A2. D4's status line has no task number; T4 includes it by reusing the existing
  `hidingCheckStatus` line (no change to the layout pane), because the product rule
  says the pane gives the reason.
- A3. `check-a10.sh`'s expected file for `ControlItem.swift` is regenerated with T4's
  added lines (an older plan's check that pins this file; `AppState.swift` and the pane
  are not touched, so their expectations stand).
- A4. A right click on an IceBar cell on 27 does nothing (r1): only AXPress was
  measured, and a secondary action is not redefined silently. Stated in the limits line.

### 9.2 New pure units in `Packages/IceCore` (new files only; tests first)

**`HiddenLengthOutcomeRule.swift`** -- one length's outcome from what was read:
`outcome(chevronListed: Bool?, checks: [SectionItemCheck], memberCount: Int)`.
`chevronListed == nil` (agent read failed or empty) -> `unknown`; `true` -> `folded`;
any `.checked(.hidden(folded: true))` -> `folded` (pixels see a fold AX has not listed
yet); any `.checked(.stillDrawn)` -> `drawn`; `memberCount > 0`, `checks.count ==
memberCount` and every check `.checked(.hidden(folded: false))` -> `hiddenClean`;
anything else (a skip, a refusal at baseline, an unverifiable, a count mismatch, no
members) -> `unknown`.

**`LayoutSignature.swift`** -- `Equatable`, `Sendable`: ordered item ids of the visible,
hidden and always-hidden sections; frontmost pid; the menu's right edge rounded to a
whole point (`nil` when unreadable); display id; space id. Not in it: frames of items
(they move with the divider, which would make Ice invalidate itself) and
`MenuBarAgent`'s items (not discovered; and Ice's own captures summon the indicator).
D1's "capture indicator appearing" trigger is not a signature field -- a deviation
from D1's wording, for the reason just given. What stands in for it (r1): the rest
margin of rule 4 (a length is rested at only when the lengths 32 pt either side of it
were also clean, more than the indicator's measured 20 pt, since every observation is
taken with the indicator up and the rest is not) and the rest watch of rule 6. An item
that peeks at rest without a `«` is not noticed: section 1's stated limit.

**`IceBarHidingMachine.swift`** -- a pure reducer, `step(state, event, now, parameters)
-> (state, [command])`; the caller (Ice) only executes commands and feeds events.
- States: `off` (not IceBar mode) / `shown(reason)` / `quiet(since)` /
  `baselining` / `calibrating(observations, trying)` / `confirming(length)` /
  `resting(length)`. Reasons: `longMenu`, `menuUnreadable`, `noCleanLength(Reason)`,
  `cannotAssess`, `noMembers`, `unstableLayout`.
- Events: `mode(isIceBar)`, `sample(signature, menuVerdict, isInteracting, isDragging,
  boundaryUsable, memberCount)` (one per tick), `baseline(token, ok: Bool)`,
  `observed(token, HiddenLengthObservation)`, `chevronSeenAtRest`.
- Commands: `setLength(Double?)` (`nil` = standard), `takeBaseline(token)`,
  `observe(token, length)`, `report(Status)`.
- Tokens (r1): every `takeBaseline`/`observe` carries a fresh integer; the machine
  keeps the one it is waiting for and ignores a `baseline`/`observed` with any other
  (a result that arrives after a signature change, an interaction or `mode(false)` is
  dropped, whatever the detector's queue was doing).
- Rules:
  1. a signature different from the one the current state was entered with ->
     `setLength(nil)` at once, state `quiet(now)`, in every state but `off`;
  2. `menuVerdict != .fits` -> `setLength(nil)`, `shown(longMenu | menuUnreadable)`
     (MenuWidthRule; fail open); `memberCount == 0` -> `shown(noMembers)`;
  3. `quiet` -> after `quietPeriod` with an unchanged signature, no interaction,
     `boundaryUsable` (the hidden divider decided the sections in a cache pass since
     the length last became standard, 9.3) and `minInterval` since the last calibration
     start: a cached length for the identical
     signature -> `confirming(length)` with `observe(length)` (one observation;
     `hiddenClean` -> `resting`, anything else drops the cache entry and goes to 4);
     otherwise 4;
  4. `takeBaseline` (section shown) -> `baseline(ok: false)` -> `shown(cannotAssess)`;
     ok -> `calibrating`, driven by `HiddenLengthCalibrator.next`: `tryLength(l)` ->
     `setLength(l)`, `observe(token, l)`; on its `observed` -> `setLength(nil)` first
     (so the next trial is again a jump from rest, as T0 measured), then the next
     proposal;
     `rest(l)` -> only if `l - 32` and `l + 32` are among the clean observations (the
     rest margin; else `shown(noCleanLength(.noBand))`): `setLength(l)`, `resting(l)`,
     cache `[signature: l]`;
     `giveUp(r)` -> `setLength(nil)`, `shown(noCleanLength(r))`
     (`unknownOutcome` -> `cannotAssess`);
  5. interaction starting while `baselining`/`calibrating`/`confirming` ->
     `setLength(nil)`, back to `quiet(now)`;
  6. `chevronSeenAtRest` in `resting` -> `setLength(nil)`, cache entry dropped,
     `quiet(now)`;
  7. rate limit: `maxFailures` (3) calibrations ending in `shown(...)` for one
     signature -> `shown(unstableLayout)` until the signature changes; `minInterval`
     between calibration starts;
  8. `mode(false)` -> `setLength(nil)`, `off`;
  9. `isDragging` (a Command-drag on the bar) in any state but `off` ->
     `setLength(nil)`, `quiet(now)`: the owner arranges items across the real divider,
     and the sections are read again before the next calibration.
- Parameters `.standard`: `quietPeriod` 3 s, `minInterval` 30 s, `maxFailures` 3
  (INFERRED constants, judged in T7; not measurements).
- Status text per state lives here too (`Status.message`): "IceBar active" / "Items
  shown: the frontmost app's menus reach the notch" / "Items shown: no clean hiding
  length found" / "Items shown: an item could not be assessed" / ..., each followed by
  the limits line (app icons; long menus).

**`PressTargetRule.swift`** -- which child of an `AXExtrasMenuBar` an item key names:
`index(for key: ItemKey, identifiers: [String]) -> Int?`: a positional key -> its
`childIndex` if in range; otherwise the one child whose trimmed identifier equals the
key's; none or several -> `nil` (the cell is disabled; never a guess).

Tests (Swift Testing, red before green, >= 80 % line coverage per new file): every
branch of the outcome rule; signature equality and what it ignores; the machine's
rules 1-8 as event sequences (including: a signature change in each state restores
standard first; a cached length confirmed and refused; T0's band walked to
`resting(736)`; a band too narrow for the rest margin -> shown; a stale token ignored
in each waiting state; interaction aborts; a drag at rest restores standard; no
calibration before `boundaryUsable`; three failures -> `unstableLayout`; `mode(false)`
from each state); the press rule's four cases.

### 9.3 T4 Ice wiring (every edit behind `#available(macOS 27, *)`)

- `ControlItem.swift` (edit): a 27-only `calibratedHiddenLength: CGFloat?` (set by the
  coordinator; setting it calls `updateStatusItem()`); in
  `updateStatusItemVisibility(true)`, on 27 **and** IceBar mode: `.hidden` in
  `.hideSection` -> `calibratedHiddenLength ?? Lengths.standard`; `.alwaysHidden` in
  `.hideSection` -> `Lengths.standard` (product rule: one section). Otherwise
  `identifier.length(for: state)` as today. 26 and earlier: unchanged path.
- Divider tracking (edit, `MenuBarItemManager.configureDividerTracking` /
  `recordDividerState` / `dividerSnapshot`, all already 27-only; r1): a divider counts
  as collapsed when it is **physically** at standard length -- `.showSection`, or, in
  IceBar mode, the hidden divider with `calibratedHiddenLength == nil` and the
  always-hidden divider always. `ControlItem` publishes that as one 27-only value;
  the settle clock (`DiscoveredCachePlan.settleSeconds`, 1 s) restarts whenever it
  turns true. The manager keeps whether the last published pass had a usable hidden
  boundary (`boundaryUsable`). With IceBar mode off nothing changes (`.showSection`
  is the only way to be at standard length there).
- `Ice/MenuBar/IceBar27/IceBarHidingCoordinator.swift` (new, `@available(macOS 27, *)`,
  `@MainActor`): owns the machine's state; a 1 s tick builds the `sample` event
  (signature from `itemManager.itemCache`, `NSWorkspace.frontmostApplication`,
  `screen.getApplicationMenuFrame()`, `MenuWidthRule.verdict` against the notch's left
  edge, `appState.activeSpace`, the active-menu-bar display id; `isInteracting` = mouse
  inside the menu bar, `isDraggingMenuBarItem`, or the IceBar presented); executes the
  commands; while `resting`, each tick also reads the agent frames (AX only, no
  capture) and sends `chevronSeenAtRest` when one is a chevron. Created and owned by
  `MenuBarItemManager` in its existing 27 branch (`configureCancellables`), so
  `AppState.swift` is not edited.
- `Ice/MenuBar/IceBar27/HiddenLengthObserver.swift` (new): the adapter of D1.
  `takeBaseline`: `HidingVerification.prepare(sections: [.hidden], sectionMap:,
  explicitCandidates: nil, reusing: nil)` (r1: the members are the hidden section's
  items; always-hidden items are pushed along with them but are not members, so one
  of them that cannot be assessed does not block the IceBar -- a fold among them is
  still a `«`) on a
  `HidingVerification.live` of its own; ok only when `.ready`, no member is in
  `planSkipped` or `baselineRejections`, and `checkableTargets` covers every member.
  `observe(length)`: wait `settle` (1 s, T0's), `verify(prepared)`, read the agent
  frames, apply `HiddenLengthOutcomeRule`. Any cancellation or failure -> `unknown`.
- Verification warm-up: `HidingVerification.live` gains a `warmUpCount` parameter
  (default 24, unchanged for the existing caller); the observer passes 4 (1 s).
  INFERRED, to be judged in T7. Expected cost of a first calibration per signature:
  15 lengths (13 clean + 2 edges from 736) x about 3.5 s, each a visible jump from
  rest -> roughly 1 min of the hidden items flickering (R3); a signature seen before
  costs one observation.
- `IceBarPanel.show` (edit, 27 only): when the coordinator is not `resting`, the panel
  is not opened (the items are on the bar); the status line says why.
- Status: the coordinator writes `appState.hidingCheckStatus` through a new
  `HidingCheckStatus(message:)` initialiser (`HidingVerifier.swift`, additive). One
  writer at a time (r1): in IceBar mode the verifier's `report` closure
  (`AppState+HidingCheck.swift`, 27-only) drops its `skip(.iceBarMode)` lines; on
  `mode(false)` the coordinator clears its line.
- Quit: unchanged; the status item is removed with the app (T8's abort path).

### 9.4 T5 IceBar cell image (edits in `IceBar.swift`, 27 / `.accessibility` only)

- `IceBarItemView.body`: `IceBarIconChoice.choose(hasCachedImage:,
  isAccessibilitySource:, hasAppIcon:, title: item.title)`; `cachedImage` and `none`
  keep today's code path; `appIcon` -> the app's icon desaturated (CoreImage
  `CIColorControls`, saturation 0) and multiplied by the IceBar's foreground colour
  (route C F2: "desaturated, tinted", not a template -- a template of an app icon is a
  filled squircle), 18 pt, cached per pid in the view model for the panel's lifetime;
  `title` -> `Text`, one line, truncated at 12 characters; `genericGlyph` -> SF Symbol
  `app.dashed`. Each cell keeps the click overlay, tooltip and accessibility label.
- `IceBarContentView.content`: on 27 the `imageCache.cacheFailed(for:)` branch is
  skipped (it is always true there).

### 9.5 T6 click on 27

- `Ice/MenuBar/IceBar27/MenuBarItemPresser.swift` (new, 27 only): decode the item's
  key from `MenuBarItem.ID.accessibility`; app element -> `AXExtrasMenuBar` ->
  children -> identifiers (messaging timeout on each element, as `LiveExtrasReader`);
  `PressTargetRule.index`; `AXUIElementPerformAction(child, kAXPressAction)` on a
  background queue (T0: the call may not return until the menu closes). Result (r1), three
  values and no claim that anything opened: `failed` = no target, or the call returned
  an error, whenever it returns; `accepted` = it returned success; `pending` = it has
  not returned yet (T0: with a menu the call returns only when the menu closes, so a
  working press is `pending` for as long as the menu is up -- a timeout cannot mean
  failure). One press per item at a time: a click on a `pending` item is ignored. No
  show-press-rehide fallback (not needed in T0; the owner's rule).
- `IceBarItemView` (edit): for `.accessibility` items the left-click action calls the
  presser after `section.hide()`; the right-click action does nothing (A4) (which leaves the length alone in IceBar mode); a
  `failed` result adds the item id to a `@Published` set on `MenuBarItemManager`
  (`unpressableItems`, 27 only); such a cell is drawn at 40 % opacity, its click
  overlay removed, tooltip "Cannot open on macOS 27". The set is cleared when the item
  cache changes. `MenuBarItemManager.click`/`temporarilyShow` are not edited.

### 9.6 Files

| new | edited |
|---|---|
| `Packages/IceCore/Sources/IceCore/{HiddenLengthOutcomeRule,LayoutSignature,IceBarHidingMachine,PressTargetRule}.swift` and their four test files | `Ice/MenuBar/ControlItem/ControlItem.swift` |
| `Ice/MenuBar/IceBar27/{IceBarHidingCoordinator,HiddenLengthObserver,MenuBarItemPresser}.swift` | `Ice/MenuBar/IceBar/IceBar.swift` |
| | `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift` (owns the coordinator, `unpressableItems`) |
| | `Ice/MenuBar/Verification/HidingVerifier.swift` (`HidingCheckStatus(message:)`), `Ice/Main/AppState+HidingCheck.swift` (one status writer) |
| | `Packages/MenuBarDiscovery/Sources/MenuBarDetectorFeed/HidingVerificationLive.swift` (`warmUpCount`) |
| | `docs/plans/checks/a10-ControlItem.expected`, this plan, `docs/macos-27/STATUS.md` |

Not touched: the ten frozen detector files, `Packages/MenuBarCapture`, `Shared/`,
`MenuBarItemService/`, `AppState.swift`, the layout pane, `MenuBarItemManager.click` /
`temporarilyShow`, anything on the 26 path.

### 9.7 DoD and acceptance for this step

1. IceCore: `swift test --package-path Packages/IceCore --enable-code-coverage` green
   (old and new suites); each new file >= 80 % line coverage; each new suite seen red.
2. `MenuBarDiscovery` tests green (the `warmUpCount` default keeps the existing ones).
3. App builds: `xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug
   CODE_SIGNING_ALLOWED=NO -derivedDataPath <outside ~/Documents> build`.
4. `check-a3a4.sh` passes; `check-a10.sh` passes with the regenerated ControlItem
   expectation, the other two unchanged.
5. AC4 by diff review: every edited line in `Ice/` is inside `#available(macOS 27, *)`,
   an `@available(macOS 27, *)` declaration, or a `.accessibility` case.
6. Not in this step: AC1-AC3 and AC6 (they need T7/T8); the probes' full test run
   (untouched by T4-T6; if run, capped at 90 min with output to a file).

Risks: R5 the machine's signature flips because of Ice's own length change (a section
re-assignment while expanded) -> rule 7 bounds it to three tries, then shown with
`unstableLayout`; seen only in T7. R6 the 4-capture warm-up reads less reliably than
24 -> more `unknown` -> items shown (fail open), judged in T7. R7 an app whose status
item opens a popover rather than a menu: AXPress still succeeds or fails by its error
code, no menu window is required. R8 whether a Command-drag is detected on 27 while
the items are pushed off (`HIDEventManager` sets `isDraggingMenuBarItem` from Command
+ the mouse in the bar): TBD, T7. Rollback: delete the new files, revert the six
edits.

## Appendix. Review record

### Round 1 (Codex gpt-5.6-terra): 6 P1, 2 P2 -- all accepted

| finding | change |
|---|---|
| P1 IceBar mode collapses both hidden dividers; two spacers unmeasured | product rule: one section (hidden) on 27; always-hidden shown |
| P1 `HidingVerifier` is not a simple drawn sensor | adapter: fresh baseline per member, refusals exposed, `hiddenClean` only when all members positively absent and readable; else fail open |
| P1 triggers miss layout changes; stale lengths | any layout-signature change restores standard length at once; recalibrate after a quiet period; reuse only for an identical signature |
| P1 spikes relayout the owner's bar | T0 and T7 in `icetest`; T8 with preflight, abort and bounds |
| P1 click failure boundary | spike B fixes action, detection, timeout, failure; fallback only with timeout, cancellation and guaranteed restore, else the cell is disabled |
| P1 no product rule for partial capacity | all-or-nothing, reason shown; AC1 covers it |
| P2 state invisible | one persistent status line (D4) |
| P2 task order | T0 first, T1-T3 only for what it validated |

### Round 2: 0 P0, 0 P1 -- CONVERGED

Codex confirmed each round-1 change closes its finding against the plan and the cited code. Trend: 6 P1 + 2 P2 -> none.

### Section 8 (T1-T3 detail), 2026-10-04, cap two rounds

Round 1 (Codex gpt-5.6-terra, medium): 0 P0, 2 P1, 1 P2 -- all accepted, each with a
concrete counter-example (re-checked one by one, not taken wholesale).

| finding | change |
|---|---|
| P1 rounding the midpoint can leave the clean run (fractional step) | rest at the exact midpoint |
| P1 an unobserved interior grid point is assumed clean | grid anchored at the start; every point lo..hi must be observed clean (unobserved -> tried, non-clean -> `inconsistent`); off-grid -> `inconsistent` |
| P2 observation length not validated | non-finite or out-of-range -> `giveUp(.unknownOutcome)` |

Round 2: CONVERGED. Trend: 2 P1 + 1 P2 -> none.

### Section 9 (T4-T6 detail), 2026-10-04, cap three rounds

A first call reviewed the file before section 9 was on disk (an edit hook had refused
the write); its one finding ("section 9 missing") is void and not counted.

Round 1 (Codex gpt-5.6-terra, medium): 1 P0, 5 P1, 2 P2. Each checked against the code.

| finding | ruling | change |
|---|---|---|
| P0 a trial length is never applied (`setLength(nil)` then `observe`) | accepted (the text said it) | rule 4: `setLength(l)`, observe, `setLength(nil)` |
| P1 stale `baseline`/`observed` results after an invalidation | accepted | a token per request; others ignored |
| P1 in IceBar mode the dividers are `.hideSection`, so sections are only carried and a new item is "visible" (`MenuBarItemManager.swift:129`, `DiscoveredCachePlan.swift:123-187`) | accepted, confirmed in the code | 9.0 fact; divider tracking by physical length; `boundaryUsable` gates a calibration; rule 9 (drag) |
| P1 observations are taken with the capture indicator up, the rest is not | modified: the indicator cannot be a signature field (Ice's own captures summon it, FINDINGS 2026-09-19), so the suggestion to invalidate on its transitions would invalidate every observation | rest margin of 32 pt either side (> the measured 20 pt); rest watch kept; a peek without `«` stays section 1's limit |
| P1 always-hidden items in the all-or-nothing roster | accepted, with the fact that they are pushed along physically | members = the hidden section only |
| P1 "still running after 1 s = opened" | modified: a timeout as failure is refuted by T0 (the call returns only when the menu closes; `AXError` 0 on 5/5), so it would disable every working menu cell | three results `failed` / `accepted` / `pending`, no "opened" claim, one press per item at a time |
| P2 right click redefined as AXPress | accepted | right click does nothing on 27 |
| P2 two writers of `hidingCheckStatus` | accepted | the verifier's `iceBarMode` skips are dropped in IceBar mode |


Round 2: Codex stopped mid-run on its usage limit (13:17, back at 14:11), with no
verdict; its last message before the cut said the two modified rulings are grounded in
the cited measurements. Degraded as the workflow prescribes: round 2 here is the main
session's own re-read, **not an adversarial review**. It checked the revision's new
parts against the code: a divider reading's usability depends on its frame's position
only (`DiscoveredItem.swift:24-29`), so a hidden divider at standard length in
`.hideSection` is a usable boundary; outside IceBar mode the physical-length rule
equals `state == .showSection`, so nothing changes there; every touched function in
`MenuBarItemManager` is already `@available(macOS 27, *)`. No new finding. Codex
round 2 is re-run in the background after 14:11; a P0/P1 from it stops the
implementation and reopens this section.

Round 2, Codex (re-run 14:13, after the quota came back; it read the plan and the code
as built at `a2daee0`): of the round-1 findings, 7 CLOSED (both modified rulings
upheld: the indicator margin, the press outcome) and 1 still open; 2 new P1, both
confirmed in the code and accepted:

| finding | change |
|---|---|
| P1 `boundaryUsable` is stale: set only when a pass publishes, never cleared when the hidden divider's length changes (round-1 finding still open) | `recordDividerState` clears it whenever the hidden divider's standard-length state changes; only a pass after the settle sets it again |
| P1 a Command-drag shows every section (`HIDEventManager.swift:321-325`, `showAllSectionsOnUserDrag` on by default) and nothing hides them when it ends, so in IceBar mode the calibrated length would never apply again | on the drag's end, in IceBar mode, the coordinator hides the hidden section (dividers back to `.hideSection`) |

Trend: 1 P0 + 5 P1 + 2 P2 -> 2 P1 (both closed in code). Cap three rounds; round 3
is folded into the Phase 3 Codex code review of the same change rather than run on
the plan text again (review-loop stop rule).
