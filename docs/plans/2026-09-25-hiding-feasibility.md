# Can Ice hide menu bar items on macOS 27? -- the feasibility gate

2026-09-25 · branch `wip/hiding-feasibility` (from `main` d21e1e6) · **v1, desk
research only; no experiment has been run.** v2 after Codex round 1 (Appendix).
The owner approves this plan before anything that changes the menu bar's state,
and each stage in section 6 needs its own go.

Converged order (not re-opened): first this gate -- hiding that is reliable and
recoverable across layouts, app switches and Spaces, or a declared read-only
macOS 27 -- then showing item images, then the XPC service on its own (most
likely disabled, not fixed).

## 1. The decision this plan produces

One of two outcomes, written up for the owner:

- **GO** -- at least one mechanism meets every **mandatory** criterion of section 3,
  and every **owner-waivable** criterion it does not meet was waived by the owner
  *before* its testing began (section 7). Its implementation is a separate plan
  (section 8 lists what it would touch).
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
| D | private visibility restriction (`MBAssessmentModeAssertion` with `MBAssessmentModeConfiguration(allowedSystemItems:allowedBundleIdentifiers:)`) | READ (exports): an allow-list, bundle-id granular for third-party items; the service has no entitlement. "Activated four times" appears in FINDINGS' first commit and nowhere else, with no probe source and no evidence file, so it counts as **not reproduced**. What "assessment mode" does beyond the menu bar is unknown | live on paper only |
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

Each criterion has one disposition: **mandatory** (a failure drops the candidate),
**owner-waivable** (the owner may waive it for a candidate before that candidate is
tested, never after), or **informational** (recorded, decides nothing).

| # | criterion | measured how | disposition |
|---|---|---|---|
| G1 | **effect on the observable population**: every item chosen to be hidden is not drawn; no `«` appears; no other item of the observable population disappears. The observable population is every item discovery lists plus the strip outside them (unexplained ink appearing or vanishing counts), in a bar whose contents the run controls (section 5). A pass says *no observed collateral effect*, not that none exists on another bar; system items discovery does not list are watched by the strip check only | the pixel detector plus the strip check; AX only says where to look | mandatory |
| G2 | **robust**: G1 still holds after (a) the frontmost app changes (narrow, mid, wide menus); (b) an item appears or leaves while hidden; (c) the hiding target's own app relaunches while hidden; (d) a Space switch, including into and out of a full-screen app's Space; (e) the menu bar's own auto-hide, if the owner uses it; (f) display sleep and wake, screen lock and unlock; (g) a second display, if one is attached | the protocol of 6.2 | (a)-(d) mandatory; (e)-(g) owner-waivable |
| G3a | **recoverable, mechanism**: showing restores every hidden item within 2 s; when the process holding the mechanism quits or is killed (SIGKILL), and when `MenuBarAgent` restarts, the bar returns to its true state with no manual step | the protocol of 6.2, N >= 3 each | mandatory -- except that for E the owner may instead accept, before testing, that hiding is **persistent** and undone from System Settings (V1) |
| G3b | **recoverable, Ice**: the same when Ice itself quits or is killed | a separately approved run of a modified Ice after a GO; not part of this study | informational here |
| G4 | **verifiable at runtime**: Ice can tell, for a stated class of items (glyphs with clear background, room >= 41 pt, fold absent at baseline), that G1 holds; every item outside that class, and every unreadable verdict, falls back safely (shown, never reported hidden) | the check's verdicts on the mechanism's own state, capture active | mandatory for C; for E the OS's own state may stand in if Ice can read it |
| G5 | **selectable** at the granularity Ice offers (per item, per section) | E and D act per app (bundle id): two items of one app cannot be separated, and a section mixing items of one app cannot be honoured | mandatory -- E and D fail it unless the owner accepts a per-app mode before testing (V1) |
| G6 | **supportable**: no private entitlement; no side effect beyond the menu bar; nothing the user cannot undo from System Settings if Ice is gone | read, plus a pre-registered list of observations | mandatory; an effect outside the menu bar that cannot be bounded counts as a failure (so D fails it by default, section 4) |

Unsupported unless separately tested, and stated as such in any GO: logout and
login, restart, attaching or detaching a display.

## 4. Order of candidates, and why

1. **E first, if V1 allows it.** If the OS offers the switch, it is robust by
   construction (persisted, applied by the agent itself, visible and reversible in
   System Settings) and needs no geometry. It is also per app and persistent, so it
   passes G3a and G5 only if the owner accepts a persistent per-app mode before it is
   tested (V1); otherwise it is dropped at stage 0.
2. **C second.** Public API and Ice's own mechanism at another length. It is decided
   in the cheapest order: does the detector give a usable verdict in the band at all
   (C1, a smoke test with capture active), is there one length safe in every layout
   (C2), and only then robustness.
3. **D excluded by default.** A private "assessment mode" assertion whose effects
   outside the menu bar are unknown and cannot be bounded by observation (G6), whose
   allow-list hides everything unlisted -- including items that appear while it is
   held -- and which needs a complete, stable inventory of every other app and system
   item to be selective. It is reconsidered only if the owner answers V3 yes **and**
   E and C are both dropped; then G6 is narrowed to a pre-registered list of
   observations, and any result is limited to the isolated account's population.

## 5. Environment

- **Sacrificial helpers only**: `com.icespike4.target` / `.protected` (vzhelper);
  never the user's items.
- **An isolated macOS user account is required** for every run that expands a spacer
  (all of C -- the owner's standing constraint is that no spacer is expanded on their
  bar), for any programmatic write of E (E2), and for D. Its empty bar also gives the
  room this account lacks. Creating it is the owner's action; so is lifting the
  no-spacer constraint inside it.
- On the owner's own account, only E1 (the owner switching the **helper's** entry by
  hand) and stage 0 run.
- **Latch**: the first credible disappearance of anything outside the target -- one
  miss, not two -- stops the run and restores at once (the spacer collapsed, the
  helper's entry switched back, the holder quit), then the bar is re-read.
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
| S0.4 | The environment: isolated account yes/no; second display yes/no; the menu bar's auto-hide on/off | recorded; it scopes stages 1-2 |
| S0.5 | The owner answers V1-V4 (section 7) | answers recorded before stage 1 |

**Dropped after stage 0**: E if S0.1 finds no such setting or V1 is no; D unless V3
is yes (and even then it waits for E and C to be dropped).

### Stage 1 -- structure: does it exist, can it be verified, is there a safe setting

| # | task | pass | DoD |
|---|---|---|---|
| E1 | The owner switches the **helper's** entry off in System Settings by hand, then on again; the instrument watches | helper not drawn, no `«`, nothing else of the observable population changed; on again restores it; the setting survives the helper relaunching | verdicts, N = 3 |
| E2 | Isolated account only, and only if E1 passes: can a third-party process change the helper's entry (the public preferences path, or the private setter) without an entitlement or a prompt? The helper's pre-state is recorded; after every attempt -- success, error or crash -- the entry is verified back at its pre-state | it can, and E1's pass holds when it does | yes/no, with the error if no; restoration verified after each attempt |
| C1 | Isolated account: a coarse scan (16 pt steps) finds the band for one helper at Ice's rest; then a **smoke test at its midpoint** with capture active: does the detector give `hidden(folded: false)`, and `restored` after collapsing, with stable controls -- or does the AX placement veto refuse, or does the capture indicator move the band? | the detector decides, N = 5, no `contradictsAccessibility`, the band unmoved by capturing | verdicts; if it fails, C is dropped and no edge is mapped |
| C2 | Only if C1 passes. Isolated account: bracket both edges (jump path, 4 pt) with 1-4 helper items and three frontmost-menu widths; pick **one** length inside the intersection of all conservatively bracketed bands, with at least 16 pt of margin to every edge; then test exactly that length under G2(b) | such a length exists and holds | the brackets, the length, its G2(b) result |
| D1 | Only if D is back in (V3 yes, E and C dropped). Isolated account, a pre-registered population: activate the assertion allowing that population except the helper; observe the pre-registered list; invalidate; then kill the holding process | only the helper disappears; invalidation and holder death both restore; nothing on the list changes outside the menu bar | observations, N = 3, limited to that population |

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

- **V1** A **persistent, per-app** mode for macOS 27 (E): hiding means the OS stops
  showing an app's items until it is allowed again -- surviving Ice quitting, undone in
  System Settings -- and two items of one app cannot be separated. Acceptable?
- **V2** IceBar mode, the owner's configuration, cannot show hidden items on 27 (blank
  images, refused clicks). Is a hider useful without it, i.e. with items expanded in
  place -- or does GO also need the image track first?
- **V3** May a private-API mechanism (D) be considered at all, given FINDINGS' "do not
  build core behaviour on it"?
- **V4** Which of G2(e)-(g) -- auto-hide, sleep and lock, a second display -- may be
  waived as stated gaps?

## 8. If GO -- what an implementation would touch (for scale, not now)

- `ControlItem.updateStatusItemVisibility` is the only place hiding state becomes a
  length; a 27 branch goes there -- A10 has to be lifted for `ControlItem.swift` (the
  owner rewrites its expected-lines file).
- For E: a per-app model beside Ice's sections, and the settings UI to say so.
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
| a stage changes the owner's bar | on the owner's account only stage 0 and E1 (the helper's own entry, by hand); every spacer, write and assertion run in the isolated account; the one-miss latch |
| E is a system setting, so an experiment changes System Settings state | only the helper's entry, pre-state recorded, verified back after every attempt |
| D leaves a restriction in place, or acts outside the menu bar | excluded by default; if the owner brings it back, isolated account only, holder death observed first, results limited to the pre-registered population |
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
