# Can Ice hide menu bar items on macOS 27? -- the feasibility gate

2026-09-25 · branch `wip/hiding-feasibility` (from `main` d21e1e6) · **v1, desk
research only; no experiment has been run.** v3 after Codex rounds 1-2 (Appendix).
The owner approves this plan before anything that changes the menu bar's state,
and each stage in section 6 needs its own go.

Converged order (not re-opened): first this gate -- hiding that is reliable and
recoverable across layouts, app switches and Spaces, or a declared read-only
macOS 27 -- then showing item images, then the XPC service on its own (most
likely disabled, not fixed).

## 1. The decision this plan produces

One of two outcomes, written up for the owner:

- **GO** -- at least one mechanism meets every **mandatory** criterion of section 3
  for its **mode**, and every **owner-waivable** criterion it does not meet was waived
  by the owner *before* its testing began (section 7). Its implementation is a
  separate plan (section 8 lists what it would touch). If the owner answered V2 with
  "images first", a GO is feasibility-only: implementation waits for the image track.
- **NO-GO** -- none does. macOS 27 is declared read-only: `STATUS.md` already
  says that this is the fallback, and section 9 lists what read-only mode changes.

Staged elimination (Codex round 1): the owner's value calls and the structural
questions (does the mechanism exist, can it be verified, is there a common safe
setting) are settled first; robustness is run only for a candidate that can still
produce GO. A candidate is dropped the first time it fails a mandatory criterion,
after one replication to rule out a flake. The study stops as soon as the outcome is
settled.

## 2. What is known (desk)

Sources: `docs/macos-27/FINDINGS.md`, `probes/safewidth/RESULTS.md`, the Ice
source, the 2026-09-25 research sweep and its critic (evidence
`20260925-195224-hardening/hide-research/`), and read-only checks run while
writing this plan (dyld exports of `MenuBarClientCore`, strings of
`MenuBarAgent`, code signatures).

| # | candidate | what the evidence says | status |
|---|---|---|---|
| A | Ice's divider at `Lengths.expanded` (10 000 pt) | MEASURED: 10 of 10 checks `stillDrawn` on Ice `2e0c553`. The safe-width runs had already shown that at 10 000 pt the spacer gives the room back | not a mechanism on 27 |
| B | public push-out, lengths in about [20, 640] pt | MEASURED on helpers: hides, and always raises the system's `«` fold | **stopped by the owner**; excluded |
| C | the no-fold band, spacer length from (652, 656] up to (836, 852] (848-864 coming down) | MEASURED once: one rest position (Ice's 32 pt chevron rest), one display, 15 user items, a 12 pt helper, one afternoon. Only the lower edge was jump-bisected; the upper edge is bracketed by 16 pt staircases. The mechanism is unknown (the window-covers-the-slot idea was refuted). AX keeps the hidden item at an x that depends on the path taken | live candidate; transfer unproven |
| D | private visibility restriction (`MBAssessmentModeAssertion` with `MBAssessmentModeConfiguration(allowedSystemItems:allowedBundleIdentifiers:)`) | READ (exports): an allow-list, bundle-id granular for third-party items; the service has no entitlement. "Activated four times" appears in FINDINGS' first commit and nowhere else, with no probe source and no evidence file, so it counts as **not reproduced**. What "assessment mode" does beyond the menu bar is unknown | NO-GO under G6 (section 4); not tested |
| E | the system's own per-app allowance (`TrackedApplicationsPreferences.TrackedApplication.isAllowed`, with a setter; `MenuBarAgent` logs `Creating status item %s, isAllowed: %d` and `Disallowed application %s`) | READ this session (exports, agent strings). INFERRED: this is the per-app switch in System Settings' menu bar settings, and the agent refuses a disallowed app's status items. Per app, not per item; persisted by the OS; the store sits behind a `SecuredPreferencesController` (group `com.apple.MenuBar`), so whether a third party may write it is UNKNOWN | **new lead** |
| F | `NSStatusItem.isVisible = false` | only the owning app can set it | cannot hide other apps' items |

Constraints any GO has to live with (READ unless tagged):

- **The detector** decides from pixels: it needs a baseline taken with the fold
  absent, at least 41 pt of room right of the notch, and a glyph with clear
  background (solid blocks read `notObserved`). Each capture summons a ~20 pt
  `MenuBarAgent` indicator left of the items (MEASURED), which takes room. It has
  never judged a state a spacer caused: its `hidden(folded: false)` verdicts came
  from helpers hiding themselves. INFERRED: in the band, where AX still lists the
  item at a path-dependent x, its placement veto may answer
  `contradictsAccessibility`.
- **Room on this machine** is about 88 pt right of the notch -- Ice's rest plus two
  12 pt items. Varying the number of items, the variable that sets the band, does
  not fit here (MEASURED, RESULTS.md).
- **The owner's own configuration is IceBar mode.** On 27 its images are blank
  (MEASURED) and clicks on items are refused (INFERRED), so a hider alone does not
  give the owner hidden items they can reach; expanding in place does.
- **ShowOnClick** decides whether a click hit an item from the per-item window list,
  empty on 27, so with it on, any click on a user item toggles the hidden section
  (READ, first-run plan F9).
- **Launch order**: the hidden divider is expanded one main-queue turn after it is
  created, before discovery runs (F3), so a hider would hide before any baseline
  exists.
- **Fences**: A10 allows only pre-written lines in `ControlItem.swift`,
  `AppState.swift` and the layout pane; A8b keeps every action out of the
  discovery, feed and verification directories; A4 freezes the detector files.

## 3. The gate -- what a mechanism must show

Two **modes**, fixed before testing:

- **Mode I -- per item, reverting.** What Ice offers today: any item or section can be
  hidden, and hiding ends when Ice (or the mechanism's holder) goes away.
- **Mode P -- persistent, per app.** Only if the owner accepts it (V1): hiding an app
  stops the OS showing all of its items until it is allowed again; it survives Ice;
  it is undone in System Settings. Only candidate E can offer it.

Each criterion has exactly one disposition within a mode: **mandatory** (a failure
drops the candidate), **owner-waivable** (the owner may waive it before that
candidate is tested, never after), or **informational** (recorded, decides nothing).

| # | criterion | measured how | Mode I | Mode P |
|---|---|---|---|---|
| G1 | **effect on the observable population**: every item chosen to be hidden is not drawn; no `«` appears; no other item of the observable population disappears. The observable population is every item discovery lists plus the strip outside them (unexplained ink appearing or vanishing counts), in a bar whose contents the run controls (section 5). A pass says *no observed collateral effect*, not that none exists on another bar | the pixel detector plus the strip check; AX only says where to look | mandatory | mandatory |
| G2 | **robust**: G1 still holds after (a) the frontmost app changes (narrow, mid, wide menus); (b) an item appears or leaves while hidden; (c) the hiding target's own app relaunches while hidden; (d) a Space switch, including into and out of a full-screen app's Space; (e) the menu bar's own auto-hide, set as the owner has it; (f) display sleep and wake, screen lock and unlock; (g) a second display, if one is attached | the protocol of 6.2 | (a)-(d) mandatory; (e)-(g) owner-waivable | same |
| G3a | **recoverable, mechanism**: showing restores every hidden item within 2 s; when the mechanism's holder quits or is killed (SIGKILL), and when `MenuBarAgent` restarts, the bar returns to its true state with no manual step | the protocol of 6.2, N >= 3 each | mandatory | -- (replaced by G3p) |
| G3p | **recoverable, persistent**: allowing the app again -- from Ice, and from System Settings with Ice gone -- restores every item of it within 2 s; a `MenuBarAgent` restart neither loses nor corrupts the setting | same | -- | mandatory |
| G3b | **recoverable, Ice**: G3a or G3p when Ice itself quits or is killed | a separately approved run of a modified Ice after a GO; not part of this study | informational | informational |
| G4 | **verifiable at runtime**: Ice can tell, for a stated class of items (glyphs with clear background, room >= 41 pt, fold absent at baseline), that G1 holds -- or, for E, can read the OS's allowance state for the intended app; every item outside that class, every unreadable verdict and every unreadable state falls back safely (shown, never reported hidden) | the check's verdicts with capture active (C); E3 (E) | mandatory | mandatory |
| G5 | **selectable** at the granularity of the mode: per item and per section (Mode I); per app (Mode P) | by construction | mandatory | mandatory |
| G6 | **supportable**: no private entitlement; no side effect beyond the menu bar that cannot be bounded; nothing the user cannot undo from System Settings if Ice is gone | read, plus the pre-registered observations | mandatory | mandatory |

Unsupported unless separately tested, and stated as such in any GO: logout and
login, restart, attaching or detaching a display.

## 4. Order of candidates, and why

1. **E first, in Mode P, if V1 allows it.** If the OS offers the switch, it is robust
   by construction (persisted, applied by the agent itself, visible and reversible in
   System Settings) and needs no geometry. Without V1 it is dropped at stage 0.
2. **C second, in Mode I.** Public API and Ice's own mechanism at another length. It
   is decided in the cheapest order: does the detector give a usable verdict in the
   band at all (C1, a smoke test with capture active), is there one length safe in
   every layout (C2), and only then robustness.
3. **D is NO-GO under G6, and not tested here.** A private "assessment mode"
   assertion whose effects outside the menu bar are unknown: no finite list of
   observations can bound them, so it cannot meet G6 (Codex round 2). If the owner
   ever wants it characterized, that is a separate research-only experiment in an
   isolated account, and its result can never produce a GO.

## 5. Environment

- **Sacrificial helpers only**: `com.icespike4.target` / `.protected` (vzhelper);
  never the user's items.
- **An isolated macOS user account is required** for every run that expands a spacer
  (all of C -- the owner's standing constraint is that no spacer is expanded on their
  bar) and for any programmatic read or write of E's store (E2, E3). Its empty bar
  also gives the room this account lacks. Its menu bar settings (auto-hide, and
  whatever S0.4 records) are set to match the owner's before any run. Creating it is
  the owner's action; so is lifting the no-spacer constraint inside it.
- On the owner's own account, only E1 (the owner switching the **helper's** entry by
  hand) and stage 0 run.
- **Latch**: the first credible disappearance of anything outside the target -- one
  miss, not two -- stops the run and restores at once (the spacer collapsed, the
  helper's entry switched back), then the bar is re-read.
- Ice itself is not run in this study (G3b is a later, separate go).
- Event injection (a Space switch by Control-arrow, clicks) happens only with the
  owner's explicit go for that run; the alternative is the owner doing it by hand
  while the instrument records.
- Session-wide steps -- display sleep, screen lock, `killall MenuBarAgent` -- each
  need their own go, and in the isolated account.
- No recordings kept; captures used for verdicts are deleted afterwards or kept only
  in the evidence directory, as the owner decides. Output that names apps goes only
  to the evidence directory.

## 6. Stages

Each task: what, then DoD. Before each stage's go, its runs are pre-registered in a
short protocol document (stimulus, timing, settled-state predicate, controls, reset
check, accounting -- 6.2), which Codex reviews.

### Stage 0 -- desk, eyes and the owner's value calls; no state change

| # | task | DoD |
|---|---|---|
| S0.1 | The owner opens System Settings' menu bar settings **and only looks**: is there a per-app "allow in the menu bar" list, and are the sacrificial helpers in it? | yes/no recorded, with a screenshot the owner may delete |
| S0.2 | Read-only: where the tracked-application store lives, who owns it, whether it is under an app-data privacy fence (reading another group container can raise a privacy prompt -- so this runs with the owner present, or not at all). It says nothing about whether writing is safe | ownership and protection recorded; no content read |
| S0.3 | Read-only: `MenuBarAgent` log lines for `Disallowed application` over the last day (count only) | count recorded |
| S0.4 | The environment: isolated account yes/no; second display yes/no; the owner's menu bar settings (auto-hide on/off, and any per-app switches already off -- count only) | recorded; it scopes stages 1-2 and sets up the isolated account |
| S0.5 | The owner answers V1, V2 and V4 (section 7) | answers recorded before stage 1 |

**Dropped after stage 0**: E if S0.1 finds no such setting or V1 is no.

### Stage 1 -- structure: does it exist, can it be verified, is there a safe setting

| # | task | pass | DoD |
|---|---|---|---|
| E1 | The owner switches the **helper's** entry off in System Settings by hand, then on again; the instrument watches | helper not drawn, no `«`, nothing else of the observable population changed; on again restores it; the setting survives the helper relaunching | verdicts, N = 3 |
| E2 | Isolated account only, and only if E1 passes: can a third-party process change the helper's entry (the public preferences path, or the private setter) without an entitlement or a prompt? The helper's pre-state is recorded; after every attempt -- success, error or crash -- the entry is verified back at its pre-state | it can, and E1's pass holds when it does | yes/no, with the error if no; restoration verified after each attempt |
| E3 | Isolated account only, and only if E2 passes (G4 for E): can a third-party process **read** the allowance state and tie it to the intended app's bundle id -- and what does it get when the read is denied, the store is mid-write, or the entry names an app that has since changed? | the state reads correctly for the helper both ways; every failure case yields "unknown", which Ice would show as not hidden | the reads, and the result of each failure case |
| C1 | Isolated account: a coarse scan (16 pt steps) finds the band for one helper at Ice's rest; then a **smoke test at its midpoint** with capture active: does the detector give `hidden(folded: false)`, and `restored` after collapsing, with stable controls -- or does the AX placement veto refuse, or does the capture indicator move the band? | the detector decides, N = 5, no `contradictsAccessibility`, the band unmoved by capturing | verdicts; if it fails, C is dropped and no edge is mapped |
| C2 | Only if C1 passes. Isolated account: bracket both edges (jump path, 4 pt) with 1-4 helper items and three frontmost-menu widths; pick **one** length inside the intersection of all conservatively bracketed bands, with at least 16 pt of margin to every edge; at that length, in every configuration, a baseline G1 and G4 pass (N = 5, the detector deciding) before any robustness run | such a length exists and passes its baseline | the brackets, the length, its baseline verdicts |

### Stage 2 -- robustness and recovery (only a candidate that can still produce GO)

The G2 dimensions and G3a, in the order (a), (b), (c), G3a, (d), then the
owner-waivable ones not waived. Each dimension is its own run and, where section 5
says so, its own go.

### 6.2 The run protocol (skeleton; each stage's pre-registration fills it in)

- **Settled state**: two consecutive stable captures at least 1 s apart, starting no
  earlier than 1 s after the stimulus; no settled state within 10 s is a failure of
  that run.
- **Controls**: the `.protected` helper stays drawn throughout; the strip outside the
  listed items is compared against the run's own baseline.
- **Reset check between repeats**: every helper drawn at its baseline x, the fold
  absent, the spacer collapsed (C), the helper's entry allowed (E) -- or the run
  stops.
- **Accounting**: each repeat is pass, fail or inconclusive (an unreadable verdict,
  a Space slide caught mid-capture). An inconclusive repeat is re-run at most twice;
  a third inconclusive counts as *not shown*, which is a failure for a mandatory
  criterion. A failure is replicated once before it drops the candidate.
- N >= 5 per G2 dimension, N >= 3 per G3a path.

### Stage 3 -- decision

A report to the owner: per candidate, the gate table filled in with MEASURED
results, the kill (if any) and the evidence; the GO/NO-GO recommendation, with Jev's
per-requirement reading of the value calls beside it.

## 7. Value calls the owner makes before stage 1 (not decided by evidence)

- **V1** Mode P for macOS 27 (candidate E): hiding means the OS stops showing all of
  an app's items until it is allowed again -- surviving Ice quitting, undone in System
  Settings -- and two items of one app cannot be separated. Acceptable?
- **V2** IceBar mode, the owner's configuration, cannot show hidden items on 27 (blank
  images, refused clicks). Is a hider useful with items expanded in place -- or does
  it need the image track first, making any GO feasibility-only until then?
- **V4** Which of G2(e)-(g) -- auto-hide, sleep and lock, a second display -- may be
  waived as stated gaps?

(V3, whether the private assertion D may be considered, fell away in round 2: D is
NO-GO under G6.)

## 8. If GO -- what an implementation would touch (for scale, not now)

- `ControlItem.updateStatusItemVisibility` is the only place hiding state becomes a
  length; a 27 branch goes there -- A10 has to be lifted for `ControlItem.swift` (the
  owner rewrites its expected-lines file).
- For E (Mode P): a per-app model beside Ice's sections, the settings UI to say so,
  and Ice reading the OS's state (E3) to show what is hidden.
- For C: a runtime length choice confirmed by the detector, which makes
  `HidingVerifier` a gate rather than a report -- an architecture change against A8b's
  "the check never acts".
- D10's timing, if "collapsed" must wait for a confirmed hide; the launch order (F3);
  ShowOnClick (F9) disabled or fixed on 27; IceBar disabled on 27 until images work.

## 9. If NO-GO -- read-only mode (for scale, not now)

Hide triggers disabled on 27: `ControlItem.performAction` (A10 lift),
`HIDEventManager` show-on-click and show-on-scroll and `GeneralSettingsPane`'s
toggles (unfenced), IceBar off on 27; the layout pane's status line says read-only
(the slot A10 already allows); `STATUS.md` and the README line updated. If E exists,
Ice can point to System Settings as the way to hide an app on 27.

## 10. The XPC service (separate track, recorded here because it was found here)

READ and MEASURED this session: the local build of Ice and its
`MenuBarItemService.xpc` are ad-hoc signed with no team identifier; the release Ice
(0.11.13-dev.2) and its service carry a Developer ID team; both ends of the session
require `.isFromSameTeam()`. INFERRED: the failure measured on 27 is this build's
signing, not macOS 27. Setup awaits `start()`, which has no timeout (READ), so a hang
would stall setup -- the disable plan should bound it. `MenuBarItem.swift:307` is the
one call site outside A10's fence; `AppState.swift:72` is inside it. Its own plan.

## 11. Risks

| risk | response |
|---|---|
| a stage changes the owner's bar | on the owner's account only stage 0 and E1 (the helper's own entry, by hand); every spacer run and every programmatic read or write of E's store in the isolated account; the one-miss latch |
| E is a system setting, so an experiment changes System Settings state | only the helper's entry, pre-state recorded, verified back after every attempt |
| D leaves a restriction in place, or acts outside the menu bar | not tested; NO-GO under G6 |
| measuring disturbs the band (the capture indicator takes room) | C1 measures exactly that before any edge is mapped; if capturing moves the band, C fails G4 |
| a verdict is unreadable (Space slide, indicator churn) | 6.2: inconclusive, re-run at most twice, then *not shown* |
| the study drifts into building | stages 0-2 change no Ice source; implementation is a separate plan |

## Appendix -- review record

### Round 1 -- Codex (gpt-5.6-terra, medium)

| finding | ruling | how |
|---|---|---|
| P0 E is persistent, so it contradicts G3 when Ice dies | **adopted, modified** | not an automatic NO-GO: G3 split (G3a mechanism, G3b Ice); for E the owner decides before testing whether a persistent per-app mode is acceptable (V1); without it E is dropped at stage 0 |
| P0 D's effects outside the menu bar cannot be bounded by observation (G6) | **adopted** | D excluded by default; back only with V3 yes and E, C dropped, with G6 narrowed to a pre-registered list and results limited to that population |
| P1 the decision rule disagreed with the criteria's labels | adopted | one disposition per criterion; waivers only before testing (section 1, 3) |
| P1 G4/C3 cannot speak for "the user's bar" | adopted | G4 scoped to a stated item class with a safe fallback; C1 is a smoke test of the detector in the band, with capture active, before any edge is mapped |
| P1 G1's "nothing else disappears" cannot be shown | adopted | the observable population defined; a pass means no observed collateral effect |
| P1 G5 is not met "by construction" by E or D | adopted | E and D fail G5 unless the owner accepts a per-app mode (V1) |
| P1 D1 assumes a complete allow-list inventory | adopted | a pre-registered population, results limited to it |
| P1 C1 would expand a spacer on the owner's bar | adopted | the owner's standing constraint already forbids it: every spacer run is in the isolated account; the latch fires on one miss |
| P1 N >= 5 is not a protocol | **adopted, modified** | a protocol skeleton now (6.2); each stage pre-registers its runs, reviewed by Codex before that stage's go |
| P2 G2 misses relaunch, auto-hide, logout, display attach | adopted in part | relaunch while hidden and auto-hide added; logout, restart and display attach/detach listed as unsupported unless tested |
| P2 C2's "edges move less than the width" rule | adopted | one pre-selected length inside the intersection of the bands, 16 pt margin, tested under G2(b) |
| P2 holder death is not Ice death | adopted | G3a / G3b |
| P2 E2 had no pre-state or rollback | adopted | isolated account; pre-state recorded and verified after every attempt |
| P3 mapping C's edges before knowing the detector can decide | adopted | C1 smoke test first |
| P3 stage 2 over-designed | adopted | staged elimination (section 1) |

### Round 2 -- Codex

Round 1: 12 resolved or modification accepted (the P0 on E, the protocol, G2
coverage); 3 maintained, all conceded:

| finding | ruling | how |
|---|---|---|
| P0 (maintained) D can re-enter by narrowing G6 to a finite list | **conceded** | D is NO-GO under G6 and not tested; a research-only look could never produce GO; V3 falls away |
| P1 (maintained) G3a/G5 carried "mandatory, except" -- not one disposition | **conceded** | two modes fixed before testing: Mode I (per item, reverting) and Mode P (persistent, per app; V1); G3p and a per-app G5 in Mode P; one disposition per criterion per mode |
| P1 (maintained) D's per-app granularity had no owner decision | moot | D out |
| P1 new: E has no runtime-verification test (G4) | adopted | E3: read the state, tie it to the bundle id, every failure case yields "unknown" |
| P1 new: C2's chosen length had no baseline pass | adopted | baseline G1 + G4, N = 5, in every configuration, before any robustness run |
| P1 new: V2 did not affect the decision | adopted | "images first" makes a GO feasibility-only (section 1) |
| P2 new: the isolated account's auto-hide may differ from the owner's | adopted | its menu bar settings mirror the owner's, recorded at S0.4 |
