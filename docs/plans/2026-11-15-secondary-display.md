# Second display: hidden items drawn on the other bar

2026-11-15 · branch `wip/secondary-display` · the owner's report the same day
(two screenshots taken at the same instant, 2026-11-14 18:09:41). Labels: MEASURED,
INFERRED, TBD.

## The report

With the daily Ice running, the built-in display's bar hides the hidden section's
items; the second display's bar draws them, and the IceBar lists them too, so they
appear twice. The owner calls it a bug of the external display.

## Facts

| # | Fact | Grade |
|---|---|---|
| F1 | On macOS 27 IceBar mode hides by resting the hidden divider at one length (`calibratedHiddenLength`). The daily Ice runs `.unverified`, which never observes, so it applies `HiddenLengthParameters.standard.defaultStart` = 736 pt directly (`IceBarHidingMachine.start`, `bestEffortLength`) | MEASURED (code) |
| F2 | The hiding band (pushed items neither folded behind `«` nor drawn) was measured on the built-in display only: 632-840 pt for up to eight items, run `20261004-105226-spike`; other displays, notch geometries and item counts are untested (FINDINGS "Open") | MEASURED |
| F3 | The displays now: built-in 1728 x 1117 pt, notch (aux top-left area 771.5 pt wide); `Sidecar Display (AirPlay)` 1314 x 985 pt, left of it, no notch | MEASURED (`NSScreen`, 2026-11-15) |
| F4 | At one instant the built-in bar hid the six members and the Sidecar bar drew them (one perhaps behind a `«`, unresolved from the screenshot); each bar showed a different app's menus (Finder; Azathoth's Whisper) | MEASURED (the owner's screenshots) |
| F5 | A status item has one `length`, shared by its copy on every display's bar | INFERRED (AppKit API: `NSStatusItem.length` is one property) |
| F6 | The coordinator samples `NSScreen.screenWithActiveMenuBar`; a change of `displayID` in the layout signature is structural and retires the length (`LayoutSignature`, `.displayChanged`) | MEASURED (code) |
| F7 | The owner's goal is preference hiding on their own bar (memory: goal-is-preference-hiding-not-overflow); the owner works with the Sidecar attached | MEASURED (owner's statements, screenshots) |

**Hypothesis H (not yet a cause):** the two bars take the same length and give
different results because the band depends on the display (width, notch, that bar's
app menu, items). T0's first step tests H; if H fails, the plan returns to review.

## Goal and non-goals

Goal: with the owner's two displays connected, the IceBar never lists an item that
is also drawn on a bar the owner can see. Preferred outcome: the members hidden on
both bars. Where measurement shows that cannot be had, or cannot be shown, Ice
falls back so that no duplicate appears (see T1), and STATUS and the README say so.

Non-goals: displays other than the owner's two as measured; mirrored displays;
macOS 14-26 (unchanged path); verification in the daily mode (ruled 2026-11-12);
the frozen detector and `Packages/MenuBarCapture`.

## Unknowns

| # | Unknown | Settled by |
|---|---|---|
| U0 | H: both bars take one length and differ in result | T0 step 1 |
| U1 | Each bar's set of hiding lengths, and their intersection | T0 step 2-3 |
| U2 | Whether that set moves with each bar's own app-menu frame | T0 step 3 |

(U3 of the first draft, "taken at once", dropped: T1 needs settled states only.)

## Tasks

### T-1 Lab length command (prerequisite of T0, lab only)

`LabReportCommand` gains `length <points>` and `length standard`, parsed only in a
report launch (the lab copy); the session sets `calibratedHiddenLength` directly and
records it, and the machine's own commands are suppressed while a held length is
set (the existing `holdLength` path). The daily Ice never parses commands.

DoD: Swift Testing parse tests first (valid, out of range 0 or above 4000,
non-numeric, extra words -> no command); IceCore green.

### T0 Measure on the lab copy with the real roster (gates everything after it)

Instrument: a lab copy of Ice (lab identity, plan 2026-11-13-untested-limits
section 5) with the owner's preferences imported, so its hidden section holds the
owner's members in the owner's order; plus one sacrificial helper
(`vzhelper --items 1`, `com.icespike4.target`, known glyph) placed as an extra
member left of the divider. A probe command `dualband` (in
`docs/macos-27/probes/visibility`, built by its `build.sh`, in no Xcode target)
drives it through T-1's command.

Judging, per bar and sample, three readings: the helper glyph drawn or not (the
`VZGlyphs` template check); a `«` drawn on that bar or not (the existing chevron
kernel); the member strip (the bar region the members occupy at standard length)
clear or not. A sample **hides** on that bar only if the helper is not drawn, no `«`
is drawn and the strip is clear; no attribution of a `«` to an item is needed. Any
reading that cannot decide makes the sample `unreadable`. Each length is settled
1.0 s, then sampled at 1.0 s and 2.0 s; the two must agree, or the sample is
`unreadable`. A condition with an unreadable sample at a candidate length
or its 16 pt neighbours is `inconclusive`.

Condition key: each bar's app-menu right edge **read from pixels** (the last
menu-title glyph run in that bar's strip; AX cannot give it per bar: on macOS 27
`readApplicationMenuFrame` reads the menu owner's frame whatever the screen,
`Extensions.swift:585`), the active display, and the topology fingerprint (display
ids, frames, scale, mirroring); not the names "short/mid/long". On each bar four
menu conditions are produced with `swfront` (none, short, mid, and long enough that
the system truncates it against the status area), and the inactive bar's menus are
whatever it shows, recorded. Each sample carries the fingerprint of both captures.

Steps:
1. U0: standard length, then a jump to 736; both bars captured 1 s and 3 s after.
   "Both bars take one length" is read as: the lab copy's control item reports the
   applied length 736 (AppKit `length`, one property per item; F5) **and** on each
   bar the pixel x of the protected item right of the divider is unchanged while
   the gap between it and the nearest drawn item left of the divider grows by the
   same amount, within 2 pt, on both bars (or that gap reaches the bar's left
   room on both). Per-bar AX lengths do not exist: a status item has one AX element,
   read on the active bar only. H holds if that reads true and the two bars differ
   in whether the sample hides. Any unreadable quantity: U0 inconclusive -> D.
2. Coarse sweep 0-3000 pt by 64, upward, **owner's members only** (no helper), in
   every menu condition and with the active menu bar on each display: per bar,
   where `hides` changes. If the top of the range is still changing, extend by 1000
   once; if still changing, the result is "unknown above", never "none".
3. Fine sweep, same roster, by 16 over every transition of step 2 +- 128 pt, up and
   down, every condition; each candidate point (hides) repeated three times by jump
   from standard length. Verdict per bar and reading:
   `hides = !chevronDrawn && stripClear`, fields stored apart. A point counts for a
   bar only if every reading on it hides. **P and the margins come from step 3.**
4. Judge cross-check: the helper added as one more member; at the points of step 3
   that bound P (the outermost hiding points and their outside neighbours, per bar)
   the helper's glyph is read beside the strip. Where helper and strip disagree, the
   strip judge is not trusted: the whole T0 is inconclusive -> D.

Estimated length: step 2 about 47 points x 8 conditions x 2.2 s, about 14 min;
step 3 about 10-20 min; step 4 under 2 min; run in parts as below.

Safety, per sample: both displays connected with the recorded topology, the lab
copy and helper alive, no hardware input for the last 5 s; any failure stops, sets
standard length, restores. Starts only after five minutes without hardware input.
Each part is bounded at 20 minutes and restores fully; parts resume where the last
one ended. Restore, in a `defer`-style teardown: lab copy quit, helper
quit, daily Ice relaunched by path; then verified: daily Ice PID and bundle id,
preferences export equal to the one taken before, the daily Ice's hidden length back
at its rest (lab report of the daily Ice is not available: read the divider's AX
width), and a strip of each bar saved for comparison.

Evidence to `~/IceReverse-evidence/<run id>/`; only tables enter the repo
(FINDINGS).

DoD: U0 answered; per bar and condition the set of hiding grid points (discrete),
with unreadable/inconclusive counts; teardown verified.

### T1 Decide the branch (rule fixed now, before T0)

Let P_d be the grid points that hide on bar d in every recorded condition, and
P = P_builtin ∩ P_sidecar. A point's margin is its distance to the nearest point
not in P (or the sweep edge).

- **A** P has a point with margin >= 32 pt on both sides: the default length
  becomes the P point of largest margin (a measured point, never a computed
  midpoint), applied when the recorded topology is present; it is re-checked in T3
  under every condition before it ships. T2a.
- **D** (fallback) otherwise -- P empty, margin under 32 pt, any condition
  inconclusive, H false, or U2 shows the set moving with the menu frame so that no
  point survives: while more than one non-mirrored display is connected, Ice does
  not hide (standard length) and does not offer the IceBar; the layout pane says
  why. A single display behaves as today. T2d.
- A per-display length that follows the active menu bar (the first draft's B) is
  not built: it still leaves the members drawn on the other bar beside the IceBar,
  the duplicate reported. If T0 lands in D, the owner is told, in one line, that
  hiding on one bar only is possible and what it costs; built only on the owner's
  word, as a new plan.

DoD: the branch and its numbers in the appendix "T0 result".

### T2a One measured length (branch A)

IceCore, pure: `MultiDisplayLengthRule` decides the length from the topology:
the measured topology (an allowlist entry: display vendor/model ids from
`CGDisplayVendorNumber`/`CGDisplayModelNumber`, frames, scale, macOS build, the
owner's member count of step 4, helper excluded -- matched exactly --, with the run
id) gets the measured point; a single display keeps 736; anything else (another
topology, another member count) goes to D's fallback. There is no runtime menu
gate (no per-bar menu frame can be read at run time); instead rule A requires the
point to hide on both bars in all four menu conditions of each bar, the longest
being truncated against the status area, i.e. the bar's worst case. If the set
moves with the menu so that no point survives all four, D. Stated limit: menus
between and beyond the four conditions are covered by inference (the worst case
bounds them), said so in STATUS as INFERRED.

### T2d Fallback (branch D, and A's unknown topologies)

`IceBarHidingSample` gains `displayCount` (non-mirrored, from `NSScreen.screens`
and `CGDisplayMirrorsDisplay`); the machine's precondition set gains
`multipleDisplays`, which retires the length and withholds the IceBar like any
failed precondition, with an owner message.

State transitions (both T2a and T2d), each a test: a display connected or
disconnected while resting, while a drag holds the bar, while the IceBar panel is
open (closed by `send`, existing), while the length is unset; the topology flapping
twice within 1 s (one re-decision per settled topology: the coordinator also
listens to `NSApplication.didChangeScreenParametersNotification` and samples at
once). Settling: a topology change (fingerprint: display ids, frames, scale,
mirroring) retires the length at once to D's state and bumps a generation; the
rule is decided only when one fingerprint has held for 2 s. Every sample, delayed
task (the detached menu read, `rereadSoon`) and command carries the generation it
was made under; `execute(.setLength)` compares it with the current generation on the
main actor right before applying, and drops it if older. The notification handler
bumps the generation and cancels `work`/`reread` synchronously before setting the
fallback. Tests: two changes within the
2 s, a stale callback after a change leaves the length unchanged, a stale
`setLength` after retire is dropped, connect-disconnect-connect. Today's structural `.displayChanged` for a change of active display stays
for the verified mode; in the unverified mode a change of active display alone,
with the topology unchanged, re-applies the same length without retiring it (no
standard-length flash every time the owner clicks on the other display).

DoD: Swift Testing tests first for the rule, the precondition and every transition
above; IceCore coverage of the new code at least 80 %; all package tests green; the
app builds.

### T3 Verify on the live bars

`dualband check` with the lab copy running the built code (no T-1 overrides): both
bars captured at rest after a member change, in each menu condition of T0, plus a
display disconnect and reconnect.

DoD: A, every sample hides on both bars in every T0 menu condition;
D, standard length and no IceBar while both displays are connected, and today's
behaviour after a disconnect. No unreadable sample in the check.

### T4 Statement

STATUS row(s) and README line: what hides with which displays, MEASURED with run id,
build and date.

DoD: the rows exist; `checks/` grep passes if one covers STATUS.

## Acceptance

1. T0's U0 answer and point sets exist; T1's branch follows the rule above.
2. All package tests green (`swift test` for IceCore, MenuBarDiscovery); the app
   builds.
3. T3 passes per the branch.
4. After every live run the daily Ice and its preferences are as before (export
   compared, divider width read).

## Test strategy

TDD in IceCore for every rule and transition (T-1, T2a/T2d). Integration: the app
build plus T3 (the coordinator has no unit harness). E2E: T3 on the two real
displays. The probe's judge gets unit tests on strips recorded in T0.

## Impact

Code: `Packages/IceCore` (the lab command, one rule file, the precondition),
`IceBarHidingCoordinator.swift`, `LabReport.swift`; a probe command. Not touched:
MenuBarCapture, the detector, pre-27 paths.

## Risks and rollback

| Risk | Answer |
|---|---|
| The probe stops the daily Ice while the owner returns | idle gate, abort on input, verified teardown |
| CleanMyMac or iCloud alters the staged lab copy | lab.env hashes verified before T0 and T3 (memory) |
| The Sidecar disconnects mid-run | per-sample topology check: the part is void, restored, rerun once |
| The member strip judge is fooled by an item that changes on its own (clock, indicator) | the strip excludes items right of the divider; a disagreement with the helper judge is unreadable |
| A shipped length meets a roster of more members than measured | the allowlist entry records the member count; more members go to D |

Rollback: the branch is a `wip/` branch; nothing merged without the owner.

## Appendix: review

### Round 1 (Codex gpt-5.6-terra, medium)

| # | Codex point | Ruling | Why |
|---|---|---|---|
| 1 | Cause unproven | adopted | H stated as hypothesis; T0 step 1 tests it |
| 2 | Probe helpers do not transfer to Ice's roster | adopted | T0 uses the lab copy with the owner's members plus one helper; T-1 added |
| 3 | 408-1000 not a proven bound | adopted | coarse 0-3000, extension, "unknown" not "none" |
| 4 | Band as interval | adopted | discrete grid points, margin rule |
| 5 | U2 conditions by name | adopted | observed per-bar menu frames as the key |
| 6 | U3 not answerable, not needed | adopted | dropped |
| 7 | unreadable has no role | adopted | inconclusive rule, goes to D |
| 8 | No repetition | adopted | three jumps per candidate, up and down sweeps |
| 9 | Snapped midpoint may leave the band | adopted | measured point of largest margin |
| 10 | Branches incomplete; C unsafe | adopted | D fallback covers every other outcome; C removed |
| 11 | Geometry key insufficient | adopted | allowlist of the measured topology with member count |
| 12 | Unknown geometry -> built-in length dangerous | adopted | unknown multi-display -> D |
| 13 | Transitions unspecified | adopted | transition list, each a test |
| 14 | Active-display length leaves a duplicate | adopted | B not built; owner told if D |
| 15 | Observer/T3 epoch | modified | T3 judges both bars by pixels, independent of the in-app observer; epochs recorded by the probe |
| 16 | F1 wording | adopted | rewritten |
| 17 | T0 safety | adopted | per-sample topology/liveness, verified teardown |
| S | Simpler fix: disable hiding on multiple displays, no measurement | rejected as the fix, kept as fallback D | F7: the owner's goal is hiding on their own bar, and they work with the Sidecar attached; turning hiding off whenever it is attached removes the feature for their daily setup. It is the safe outcome when T0 cannot show a shared length |

### Round 2 (Codex)

Codex accepted rulings 1-17 and S (D as fallback, provided T2d's races are closed).

| # | Codex point | Ruling | Why |
|---|---|---|---|
| 2.1 | H must be read as both bars' AX length 736 | modified | there is no per-bar AX length (one AX element per status item, read on the active bar). Replaced by a defined quantity: AppKit length 736 plus the same measured gap growth on both bars within 2 pt; unreadable -> inconclusive -> D |
| 2.2 | A `«` cannot be attributed to the helper | adopted, modified | no attribution needed: a sample hides only with no `«` on that bar at all |
| 2.3 | No settle rule in the sweeps | adopted | 1.0 s settle, samples at 1.0 and 2.0 s must agree |
| 2.4 | Allowlist ignores menu frames | adopted | per-bar covered `maxX` range in the entry, runtime gate, T0 covers the longest menus |
| 2.5 | Member count match unspecified | adopted | exact match, tested |
| 2.6 | Topology flapping races | adopted | immediate retire, fingerprint held 2 s, generation token, tests |

### Round 3 (Codex)

Accepted by Codex: 2.1 (no per-bar AX length; gap criterion), 2.2, 2.3.

| # | Codex point | Ruling | Why |
|---|---|---|---|
| 3.1 | Per-bar menu frame cannot be read (2.4 rebutted) | adopted | verified: `Extensions.swift:585` ignores the screen on 27. Menu edge read from pixels in T0; no runtime gate; A requires all four menu conditions per bar, the worst being truncation against the status area |
| 3.2 | Helper makes exact count never match | adopted | count is the owner's members; step 4 re-reads the points without the helper |
| 3.3 | Generation not checked at execution | adopted | generation on every sample/task/command, checked in `execute` on the main actor; tests |
| 3.4 | `absent` undefined vs the three readings | adopted | one predicate `hides`, fields stored apart |

### Round 4 (Codex)

Accepted by Codex: 3.1-3.4.

| # | Codex point | Ruling | Why |
|---|---|---|---|
| 4.1 | Step 4 re-reads helper points only; margins from the wrong roster | adopted | step 4 is a full fine sweep without the helper; P and margins from step 4 only |
| 4.2 | T3 expects D on an undetectable menu edge | adopted | that DoD removed; limit stated as INFERRED in STATUS |

### Round 5 (Codex)

Accepted by Codex: 4.1, 4.2.

| # | Codex point | Ruling | Why |
|---|---|---|---|
| 5.1 | Step 4's fine sweep borrows the helper roster's transitions | adopted, restructured | coarse and fine sweeps now run on the owner's roster only; the helper only cross-checks the strip judge at P's bounding points (disagreement -> inconclusive -> D) |

### Phase-2 defect: T0's instrument (Codex quick re-review, 2026-11-15)

Found in implementation: a lab-identity copy in the owner's account gets an empty
roster (plan 2026-11-12-s5-owner-acceptance F4, C1: its divider is a new item, the
owner's members land right of it; MenuBarAgent's position store is not ours to
write). "Lab copy with the owner's roster" cannot be built under the lab-identity
rule. Options: (1) one owner-approved T0 sitting with a local Debug build under the
daily identity; (2) helpers as stand-ins (rejected in round 1, not transferable);
(3) no measurement, D. Codex and I agree on (1) as the only transferable one, as an
exception the owner must grant, with these guards (all adopted):

| # | Guard |
|---|---|
| G1 | The T0 control surface (length command, report) compiled only into Debug (`#if DEBUG`), and accepted only when the bundle id is exactly the daily one; Release contains no parser path for it; tests for accept/refuse and a `checks/` grep that the Release binary has no `IceOwnerT0` string |
| G2 | The owner accepts that MenuBarAgent may change values of its store by itself; we never write it; the store is exported before, after, and after a settle, diffed and reported; an owner key added/removed, an order change, or the daily divider/icon moving stops the run |
| G3 | Daily Ice and its service quit first; the Debug build exec'd by absolute path, PID and image path verified; the domain exported with its hash; restored only after the Debug build exited; then the daily Ice relaunched by path, settled, the domain exported again and compared; any difference is a failure, evidence kept, no retry |
| G4 | The helper only in step 4 (P's bounds), listed as an extra risk the owner accepts; without it step 4 is dropped and T0 ends inconclusive -> D |
| G5 | Preflight: no other process with the daily id; a second instance during the run aborts; teardown relaunches only the verified `/Applications/Ice.app` |
| G6 | The gate is compile-time (`DEBUG`), the launch argument a second gate only |

If the owner declines: no measurement; D ships.

### Phase-2 notes on T0's judge (2026-11-15, implementation)

- Members' AX frames stack on macOS 27 (all four at x 991-1031, status `stacked:4`), so
  the spot is the divider's own frame minus the members' summed widths (they stand side
  by side left of it at standard length), plus 4 pt slack.
- On the built-in bar a third-party notch window covers 677-1048 pt, which holds the
  members' standard-length spot: there the owner cannot see them at any length. A spot
  at least 80 % under masks (the notch, other processes' small windows over the bar) is
  "blind by cover", allowed on the built-in bar only; that bar then hides when nothing
  new is drawn outside the masks and the spot (`newForeground` only). The Sidecar bar may
  not be blind (a mapping error must not pass silently).

## T0 result (run `20261115-dualband-5`, Debug `6408ca4`+G1 under the daily identity, 2026-11-15 17:34-17:40 JST)

| What | Reading | Grade |
|---|---|---|
| Roster | 4 members of the owner's (the IceBar's) | MEASURED (lab report) |
| U0 | at 736 pt: built-in bar hides (blind by cover), Sidecar bar does not (new 207 px, spot 342 px), at 1 s and 3 s alike. "Both bars take the same length" could not be read: the divider's AX width stays 18 pt whatever the length; the strips show it only by eye | MEASURED / not readable |
| Coarse, built-in active, no menus and 4 menus (`a0-m0`, `a0-m4`) | Sidecar: **no length of 64-2944 pt by 64 hides** (46 of 46 `drawn`, both reads agreeing); at 704 and 1472 pt the strips are identical: the members packed right after the frontmost app's menus, drawn. Built-in: every length "hides", because the members' spot lies under the notch and a third-party notch window (Alcove) at standard length too | MEASURED (pixels, and by eye on the saved strips) |
| The rest (10 and 24 menus, Sidecar active, fine sweep, helper) | not run: the sitting stopped at `a0-m10` (built-in spot no longer covered once its bar is compressed) and was not resumed, because rule T1 was already decided | -- |
| Teardown, every sitting (5) | daily Ice relaunched by path; preferences equal (semantic compare); MenuBarAgent store: 0 keys and 0 values changed. Sitting 1's teardown did not run (a bug, fixed); the daily Ice was down 2 min and restored by hand from the export | MEASURED |

**Branch: D.** P = ∩ over conditions; in `a0-m0` the Sidecar bar has no hiding point,
so P is empty whatever the other conditions show. T2d (already built) is the fix; T2a
is not built. Limit stated: on the owner's two displays, one status item length cannot
hide the members on the Sidecar bar at all (it gives the room back and the members are
drawn after the menus), so while the Sidecar is connected Ice does not hide and offers
no IceBar.
