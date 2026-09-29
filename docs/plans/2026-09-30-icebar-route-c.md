# Route C: IceBar on macOS 27 -- feasibility probes

2026-09-30 · branch `wip/icebar-c` (to be created) · v2 after Codex round 1 ·
**Nothing runs until the owner has approved this document, answered O1-O3, and
named a time.** A successor protocol: it does not reopen or reinterpret C2.

## BLOCKED (2026-09-30, found before any instrument work): fold-free baseline

The frozen verifier needs a baseline taken at rest (spacer collapsed, every item
drawn) with the fold absent; otherwise it refuses every item
(`Packages/IceCore/Sources/IceCore/StripAssessor.swift:120-131`,
`Template.swift:43-44` "The fold was up when the baseline was taken, so frames
cannot be trusted"). The owner's situation is by definition the opposite: with
every item drawn the bar overflows and `«` is up. INFERRED consequence: Ice can
never take a valid baseline there, so under O1 it always falls back to shown,
and IceBar never works in exactly the case it exists for. S1 as written (k up to
16 from a rest baseline) stops measuring the owner's case once k exceeds the room
(about 12 helpers in `icetest`, INFERRED from `20260929-234942-c2A` frames).

Candidate fixes, none verified:
- (a) extend the verifier to take templates per item, incrementally, whenever
  that item is drawn with the fold absent (keeps the "never report hidden without
  evidence" guarantee; needs the owner to lift the detector freeze for this
  study and a new pre-registration);
- (b) drop verification, fix the spacer length from measured bands, and watch
  only for `«`, collapsing when it appears (weakens G4 to "no `«`");
- (c) take the baseline in the hidden state and verify restore by other means.

Claude's current lean: (a). **Next step:** a thecure debate with Codex on
Q1 is the inference right (a code counter-example?), Q2 an existing mechanism
missed, Q3 which fix, Q4 the biggest worry; then revise sections 3-5, re-review,
owner approval, and only then the S0/S1 instrument. The first debate round was
cut off by a restart on 2026-09-30 with no answer.

## 0. The owner's goal (2026-09-30)

Items that would otherwise push the bar left past the notch (and make macOS 27
show its `«` overflow) live in Ice's own panel below the bar (IceBar), so the bar
never grows past the notch and `«` never appears. The owner chooses which items
go into IceBar and can add or replace them. The owner saw an interactive mock-up
of routes A, B and C and chose C.

## 1. Relation to the hiding study, and the scope this protocol tests

- **C2 stands as recorded.** Sitting A `20260929-234942-c2A` (macOS 27.0 26A428,
  isolated account, evidence `~/IceReverse-evidence/20260929-234942-c2A`,
  `runner.final.json` sha256 prefix `85ddb372fa8998df`, verified by `vizprobe
  c2-read`): `provisionalFail(k1-long, not shown)`. Three processes, each with 5
  baseline attempts, fold `unreadable`, every item `foldNotAbsentAtBaseline`;
  Menus calibrated to 16 menus, last title edges 1012 and 1058 pt, right of the
  notch (771.5-956.5). MEASURED. The C2 protocol had predicted this as INFERRED
  (`2026-09-28-c2-protocol.md` 6.1 item 4). Whether the owner accepts that
  provisional result under C2's section 1 is a separate decision; nothing here
  depends on its answer, and nothing here changes C2's verdict.
- **The scope under test (O1), fixed before any Route C measurement:**
  1. With a short or mid frontmost menu (last title ends left of the notch),
     IceBar items are pushed off the bar and `«` does not appear.
  2. With a frontmost menu that reaches right of the notch, Ice cannot verify
     hiding (MEASURED above). It then shows every IceBar item on the bar and
     says so in its menu; `«` may appear while that lasts. This is a physical
     limit, not only a detector one: those menus occupy the room the items would
     need (INFERRED from the C2 geometry). The owner's goal holds in case 1 only.
  3. Ice never reports an item hidden that is drawn, folded or in `«`.

## 2. What is known (desk, 2026-09-30)

| gate | evidence | status |
|---|---|---|
| G-hide | C1: one helper at Ice's rest, 616-840 pt every 16 pt step `hidden(folded: false)`, smoke 5/5 at 728 (`20260928-202509-vzc1`) | MEASURED for one item; room depends on the number of items, unmeasured (FINDINGS "Open"; feasibility section 2) |
| G-image | no per-item windows on 27; `MenuBarAgent`'s full-width windows capture alone as glyphs on transparent (FINDINGS, winlist probes) | MEASURED for visible glyphs; pushed-off items unmeasured; capturing changes the bar (FINDINGS "capturing the bar changes it") |
| G-click | AX items expose `AXPress` (FINDINGS:100) | unmeasured on a pushed-off item |
| G-move | human Command-drag swaps items (owner confirmed); synthetic Command-drag moved another process's item in 3 of 4 rounds (FINDINGS "The move primitive") | MEASURED; atomic target binding unsolved (FINDINGS "Open") |
| G-identity | item identity across Ice restart and app relaunch | unmeasured (FINDINGS "Open") |

Ice today refuses move and click for AX-discovered items
(`MenuBarItemManager.swift:752`, `unsupportedSource`). That is a fence, not a
measurement.

## 3. Verdicts

- **PASS**: every stage passes on its primary path.
- **PASS WITH FALLBACK**: every stage passes, some on a named fallback F1-F4
  (section 5), each accepted by the owner in O2 before its stage runs. The
  implementation plan inherits every fallback taken as a hard limit (for F1:
  IceBar holds at most the capacity S1 measured).
- **NO-GO**: a stage fails with no named fallback, or its fallback fails, or the
  owner rejects the needed fallback. The study ends; later stages do not run.
- **SAFETY STOP**: any unexpected target, an owner item touched, a helper left
  running, or a guard tripping; terminal, no further stage, owner told first.
- Per repeat, as in C1/C2: pass, fail or inconclusive; an inconclusive repeat is
  re-run at most twice, a third is *not shown* (a failure). A failure is
  replicated once, in a separate run, before it decides NO-GO.

## 4. Stages

All stages run in the isolated account `icetest`, reusing the C1/C2 instrument
(allowlisted roster guard, console guard, geometry guard, hashed final
manifests, clean teardown, progress lines). Helpers only (`com.icespike4.*`,
VZGlyphs templates); nothing touches the owner's account or bar. Each profile
records the full bar population: every visible and hidden item, each width, the
control item, the capture indicator's frame when present.

| # | question | pass (N) | failure | time |
|---|---|---|---|---|
| S0 | Long menu first: with Menus calibrated `long`, k = 2 IceBar items, does the check return unverifiable, are both items then individually drawn on the bar, and is the bar restored after Menus quits? | 5/5 unverifiable, both drawn, restored; never `hidden` | any `hidden` reading while an item is drawn or in `«`: NO-GO | ~10 min |
| S1 | Profiles k = 1, 2, 4, 8 IceBar items with 3 visible helpers, each at short and mid menus. Coarse scan and refinement as C2 section 4. Is there one length per profile that pushes all k off (each individually `hidden(folded: false)`, fold absent, strip outside the listed items unchanged) and restores all k on collapse? | a band per profile, then N = 5 full cycles at its midpoint | capacity search (F1): k = 1, 2, 4, 8, then 12 and 16 while each passes; after the first failure (replicated), bisect between the last pass and it. The largest passing k is IceBar's capacity. No band at k = 1: NO-GO. Capacity below 4: the sitting ends and the owner decides before S2 | ~3-4 h |
| S2 | Images: with k = 2 pushed off, can `MenuBarAgent` windows or ScreenCaptureKit show their glyphs? Else, snapshots taken while visible. | each IceBar cell shows the glyph of the right item (identity checked against the visible snapshot), legible at 1x and 2x; a helper whose glyph changes is shown as stale, never as current | neither: F2 if O2 accepted it, else NO-GO | ~30 min |
| S3 | Click: `AXPress` on a pushed-off helper. | its own menu opens on screen within 1 s, no other item moves, bar unchanged after close, 5/5 | F3 (single item), tested after S4 (a) passes: 5/5, only the clicked item appears, no `«` left behind. S4 (a) fails or F3 fails: NO-GO | ~40 min |
| S4 | Membership: the owner's add/replace. (a) synthetic Command-drag moves a helper across the spacer (in and out), 10/10 onto the intended slot; (b) after each move, Ice's section model lists the helper in the right section and IceBar shows it. | (a) and (b) 10/10 | (a) fails: F4 if O2 accepted it, then (b) run with a manual Command-drag (owner, 5 moves); else NO-GO. (b) fails: NO-GO | ~40 min |
| S5 | Robustness, N = 5 each, IceBar items k = 4: (a) frontmost app switch short <-> mid; (b) an item appears and one leaves while hidden; (c) an IceBar helper relaunches; (d) Space switch, into and out of a full-screen Space; (e) menu bar auto-hide as the owner has it; (f) display sleep and wake, lock and unlock; (g) Ice quits and relaunches: the same items return to IceBar, none to the wrong section. For (d)-(f) IceBar closes (`IceBar.swift:56`) and reopens with the same membership. | every repeat keeps scope 1.1-1.3 and restores | a false `hidden` or a lost or misplaced item: NO-GO. Second display: waived (V4) | ~2 h |

Order: S0, then S1, S2, S3, S4, S5; each only if the previous passed, with one
exception: if S3's primary path (`AXPress`) fails, S3's verdict is held open, S4
(a) runs next, then F3 is tested (S3 passes or fails on it), then S4 (b). If S4
(a) fails, F3 is unavailable and S3 fails: NO-GO. S0 is first
because it is the known hard case and costs minutes.

## 5. Fallbacks, named before any run

- **F1** (capacity): IceBar holds at most the capacity S1 measures (the owner's
  hope: 8 or more). Items beyond it stay on the bar, where `«` can appear. S2-S5
  keep their fixed k (2, 2, 2, 4), so they run only when the capacity is at
  least 4; a smaller capacity ends the study unless the owner approves a written
  amendment of this plan that re-parameterizes those stages.
- **F2** (images): IceBar shows the owning app's icon and name instead of the
  glyph, the icon rendered monochrome (desaturated, tinted to the bar's text
  color) so it matches the bar (owner's condition, 2026-09-30). No capture.
  Dynamic glyphs (a CPU graph, a timer) are lost. S2 checks, when F2 is taken,
  that each monochrome icon is still distinguishable from the others at 1x.
- **F4** (move): the owner arranges items with a manual Command-drag on the bar
  (native, MEASURED); Ice only detects and records membership (S4 b still
  mandatory).
- **F3** (click, owner's condition 2026-09-30: only the clicked item, as original
  Ice did): clicking an IceBar item moves only that item across the spacer into
  the visible section (the S4 synthetic Command-drag under section 6), presses
  it, and moves it back after its menu closes. Other hidden items never appear.
  Needs S4 (a) to pass, so when S3 fails its F3 test runs after S4 (a); if S4 (a)
  fails, F3 is unavailable and S3's failure is NO-GO. Pass also requires no `«`
  left after the item returns; a transient `«` while it is out is recorded.

## 6. Safety for synthetic input (S3, S4 a)

Each run needs the owner's explicit go for that run (feasibility section 5).
Before every `mouseDown` or `AXPress`: re-read the target's identity and frame
from AX, AX hit test at the point returns the target's PID, the point is covered
by no other item, the layout version is unchanged since the read; any mismatch
cancels. `mouseUp` watchdog 2 s; the Command key released on every exit path.
Console and roster guards run before each event burst. On any wrong target:
SAFETY STOP, helpers quit, preferences domains checked empty, bar compared with
the run's baseline.

## 7. Owner decisions before S0

- **O1** (answered 2026-09-30: accepted): the scope of section 1 (the goal holds
  with short and mid menus; with a menu right of the notch the items show and
  `«` may appear).
- **O2** (answered): accept each of F1-F4 in advance, or reject it (then
  the stage that would need it ends as NO-GO). F4 accepted 2026-09-30; F2
  accepted 2026-09-30 with monochrome icons (section 5); F1 answered 2026-09-30: measure the maximum
  (S1 capacity search), accept the measured capacity; F3 accepted 2026-09-30 only in its
  single-item form (section 5). All of O2 is answered.
- **O3** (answered 2026-09-30: overnight): S0 + S1 in one sitting (~3-4 h), S2-S4 in
  one (~2 h), S5 in one (~2 h), each in `icetest` without switching away. Each
  sitting's start time is still named by the owner.

## 7a. Runner output for an unattended night

The owner reads the Terminal in the morning, so the runner prints in Chinese:
one line per step start and end (step, profile, wall time, elapsed), and a final
line that is exactly one of `結果：完成`, `結果：失敗`, `結果：中斷`,
`結果：安全停止`, followed by the reason in one sentence and the evidence
directory. Mapping: PASS or PASS WITH FALLBACK -> 完成; NO-GO -> 失敗; the
session left the console, a signal, or the watchdog -> 中斷; SAFETY STOP -> 安全停止.
The evidence files stay in English (they are read by the tools).

## 8. Deliverables

- Evidence per run under `~/IceReverse-evidence/<run id>/`, verified before the
  shared copy is deleted; `STATUS.md` and `FINDINGS.md` rows, MEASURED or
  INFERRED with build and date.
- On PASS or PASS WITH FALLBACK: a separate implementation plan for IceBar on 27
  (control item, section model, panel, click path, membership settings), with its
  own review. No Ice code changes under this plan beyond the probe instrument.
