# Plan — safe hiding width on macOS 27

Status: **FINAL** (2026-09-18). Reviewed in three rounds: an Opus 5
adversarial reviewer (rounds 1–2) and Codex (rounds 2–3; its round 1 died on
quota). Codex round 3: no P0. Rulings in the appendix.

Repo HEAD `58afb9c`, branch `macos-27-fix`.

## 0. Evidence this plan starts from

Measured this session (2026-09-18), read-only:

- One display, 1728x1117 pt, notch at x ∈ [771.5, 956.5]
  (`NSScreen.auxiliaryTopLeftArea.maxX` / `auxiliaryTopRightArea.minX`). Captures
  render the notch region black.
- 18 menu bar extras. The leftmost on-bar one (x=1073, w=16) is the
  `MenuBarAgent` **microphone-in-use pill**, which comes and goes on its own. No
  `«` at rest. Free room right of the notch ≈ 116 pt with the pill, ≈ 153 pt
  without.
- `screencapture -x -R 0,0,1728,33` ≈ 65 ms without decoding.
- Ice's hidden control item (`ControlItem.swift` 34–56, 329–430): expanding sets
  `button.image = nil` then `length = 10_000`; collapsing, in the chevron style,
  sets `variableLength` plus a chevron image; in the no-divider style it
  deactivates a private layout constraint, sets length 0 and shrinks the window
  to width 1. Ice never sweeps.

Re-read from the previous session's saved captures:

- The run behind "600 pt hid nothing when started at 600" is `axspike2g`
  (source 15:12:08, binary 15:12:09; spacer created at 1, first step 600). Its
  own capture `menubar-600pt.png` (15:12:20) shows `«` and none of `0 1 2 |`.
  **MEASURED:** in that run, the direct jump to 600 did hide everything. The
  "nothing hid" reading came from AX/AppKit frames.
- **INFERRED, not yet tested:** that those frames were stale. Stage O0 exists to
  test it; until then FINDINGS only gets the capture-backed correction.
- The same run's captures at 900…5000 show `2 1 0` back, no `«`, no `|`, and every
  user icon in place.

## 1. Goal

For each frontmost config and each path (jump, up, down), decide whether

```
upper end of W_hide's bracket  <  lower end of the bracket of every bound below
```

and report the verdict as **holds / fails / insufficient evidence**. Every
transition is a bracket `[last length with the old state, first length with the
new one]` on the grid actually tested; nothing is interpolated.

### Quantities, per leg

A leg is the set of settled samples `(length → state)` of one path, ordered by
**length**, not by time. Jump legs are sets of independent probes. The same
definitions apply to up and down legs.

| symbol | definition | primary signal | fallback (flagged) |
|---|---|---|---|
| `W_hide` | smallest length at which `T` is **overflowed** | `T` marker absent ∧ `«` present ∧ attribution holds (below) | — ; otherwise the sample is "invisible, overflow unconfirmed" and does not count |
| `W_edge` | smallest length at which `S`'s left edge stops moving left | `S` left-edge marker in pixels | `S`'s own AX minX, which was linear and consistent in every earlier run |
| `W_sat` | smallest length at which `S`'s AppKit window width stops growing (the ≈ 5016 clamp in FINDINGS) | AppKit frame | — |
| `W_selfov` | smallest length at which `S` itself is no longer drawn | both `S` markers absent where they would be visible | AX |
| `W_top` | smallest length above `W_hide` at which `T` is visible again | `T` marker present; labelled left-of-notch (crossed) or right-of-notch (room given back) | — |
| `W_harm` | smallest length at which any item right of `S` stops being visible | guard (section 5) | — |

The user's bound, "the width at which the spacer itself crosses the clamp", maps
onto more than one of these (`W_edge`, `W_sat`, `W_selfov`). Rather than pick
one, the verdict is computed against **each** bound separately, and the headline
uses the smallest (`W_edge`, `W_sat`, `W_selfov`, `W_top`, `W_harm`). The user
chooses which reading is theirs from the table.

**Attribution** for `W_hide` (a `«` can also mean `S` overflowed, or `T` can be
invisible for another reason): at the first overflowed width of each config's
scan, quit `T` alone. `«` disappearing and `S`'s markers staying visible
attribute the overflow to `T`. The template of `«` itself is cut from the first
such sample, where overflow was provisionally defined as "`T` absent ∧ a new
`MenuBarAgent` AX item appears", and is accepted only after ≥ 3 lockstep
hide/unhide cycles.

`W_harm` is reported as "not observed at the tested lengths (grid listed)",
never as "> L_max": lengths between grid points were not observed.

Informational, never in a verdict: whether `S` covers `F`'s menu titles,
horizontal shifts of user items, the room at each sample.

## 2. Non-goals and residual risks

- No change to Ice. Conclusions are scoped to **this helper topology with Ice's
  chevron-style sequence** (section 3). The no-divider style (private constraint,
  length 0, window width 1) is not replicated.
- One built-in notched display. No external displays or scaling changes.
- Not a production overflow detector.
- **Residual risk 1:** frontmost app switching while the spacer is expanded.
- **Residual risk 2:** two spacers expanded at once (hidden + always-hidden).
- One hidden item stands in for the hidden section.
- No `F` with menus past the notch: macOS would push user items out by itself,
  before any spacer — harm by design.

## 3. Actors — all sacrificial, all ours

Left to right at rest: `T  S  P  | user items … | system items`.

| actor | process | shape |
|---|---|---|
| `T` | helper `com.icespike4.target` | length 16; two-colour marker, colours chosen in B0 from what the strip does **not** contain |
| `S` | the controller (unbundled CLI) | Ice's chevron sequence: rest = `variableLength` + a 16 pt chevron-sized image; expand = `image = nil`, then `length = w`; collapse = the reverse. Thin markers pinned to the button's left and right edges (instrumentation only) |
| `P` | helper `com.icespike4.protected` | length 16; its own two-colour marker |
| `F` | helper `com.icespike4.front`, regular app | main menu from arguments |
| `U` | the user's apps | **never touched**: no click, drag, move, quit or AX write. Read by AX and pixels only |

- All helpers are launched with `open -n` (`-g` for `T`/`P`, foreground for `F`),
  passing `--args <controller pid>`. Each watches that pid with a `DispatchSource`
  process-exit source and exits with it. Lifetime cap longer than the controller
  watchdog. C1 checks each helper appears in `runningApplications` under its
  bundle id. Any helper death voids the trial — except the deliberate quit of
  `T` in the attribution check (section 1), which is followed by a full reset
  before measuring continues.
- The user's frontmost app is recorded at start and restored with `open -a`.
- Creation order `P`, `S`, `T`. C1 verifies from pixels: `T < S < P`, **no user
  item (the pill included) left of `T`**, `T` visible and no `«` at rest. If the
  pill sits left of `T`, nothing runs while the microphone is in use.
- If the room check fails at rest, `S` falls back to length 1 at rest; results
  taken that way are labelled and not compared with the others.
- `com.icespike4.*` defaults are deleted before each launch; the controller
  removes its own `NSStatusItem Preferred Position*` keys.

## 4. Instrument

- **Pixels are primary.** A sample = one strip capture (`screencapture` CLI,
  killed after 1 s) decoded with ImageIO, then AX (messaging timeout 0.25 s),
  then a second capture. Each record carries its own timestamps. AX is accepted
  only when both captures around it agree.
- **Marker search** over the whole strip except user items' rects (the verified
  order means `T`/`P` can never be there): two-colour pattern, ≥ 6 px run per
  colour, **exactly one match** or the sample is `ambiguous`. Negative control in
  B0: the search on a strip with none of our items must return zero matches.
- **User-item guard templates**: at B0, each user item cropped at its AX rect,
  searched later within ±40 pt. Offset 0 = unchanged; elsewhere = shifted
  (informational); not found = see section 5. Items whose crop changes during
  B0's observation are **dynamic**.
- **Presence** of an item in a rect = at least N pixels of that item's calibrated
  colour (the bar is translucent over a textured wallpaper, so "background" has
  no reference). N and colours calibrated in B0.
- **AX classes** for mechanism only, precedence `missing > parked > offscreen >
  overlapped > bar`; `overlapped` = the frame overlaps another item's or the
  `«`'s. `S` is not classified: past `W_edge` its window legitimately overlaps
  visible items.
- **Settle, pixel first**: capture every ≥ 100 ms (actual cadence measured in C1)
  until our markers' positions and states and the static-template signature are
  unchanged over the hold span from Stage O (600 ms until then). Timeout 5 s →
  restore, flag `unsettled`.
- **Evidence**: every run writes to `~/IceReverse-evidence/<run-id>/` — JSONL,
  the captures at every transition, guard event and Stage O sample, and a
  manifest (git SHA, binary hash, config, timestamps). Outside the repo on
  purpose: the strips show the user's installed apps and the date. Only
  `RESULTS.md` (with run ids) is committed.

## 5. Safety guard

Nothing is driven towards harm on purpose: up legs stop at `W_top` + 3 steps.
The guard is for surprises.

- **Continuous while `S` ≠ rest**: captures at ≥ 4 Hz throughout settles and
  holds, and during `F` activation, resets and helper launches.
- **Deadman**: a separate thread; if no guard-clean capture has completed for 2 s
  while `S` ≠ rest, the controller process exits. `S` dies with it, helpers exit
  through the pid watch.
- **Trigger**, persisting over 2 consecutive captures: `P` not found; a static
  user template not found; a dynamic item failing presence; or the pill present
  in AX but absent in pixels (**that is harm, never a "toggle"**).
- A static template miss whose rect still has presence **and** whose static
  neighbours on both sides are found at offset 0 is an appearance change, not a
  move: logged, item reclassified dynamic, no trigger. A dynamic item without a
  static neighbour on each side cannot be verified → **unknown → stop**.
- **Action**: `S` to rest in the same run-loop turn; restoration confirmed by the
  guard templates, not by a full settle.
  - Restored → harm event with its captures; **the config stops**, down leg
    marked untested. No reproduction.
  - Not restored → full teardown, stop the campaign, report.
- Changes coinciding with our own actions are never re-baselined. Between
  trials only dynamic-item changes count as drift; anything else stops the
  campaign.
- **Room drift**: the leftmost user item's x is recorded on every sample; a trial
  whose rest room before and after differs by > 1 pt is void (retry ≤ 2×). The
  pill turning on/off by itself (AX presence changes) voids the trial likewise.
  Two failed retries → "incomplete", never "no interval". Results are stratified
  by pill state.
- Frontmost ≠ `F` → void, retry ≤ 2×.
- Controller watchdog 25 min per run. Exposure per harm event is **measured**
  (first triggering capture to restored capture) and reported, not promised.

## 6. Protocol

Run order follows the doubt, not the framework: the cheapest checks of the
central question come first.

### B0 — session baseline (nothing of ours running)

Read-only for 60 s with the user's own frontmost app: user-item templates,
static/dynamic split, room, pill state and **position**, the negative control for
marker search, and marker colours picked from what the strip does not contain.

### C — per config calibration and null control

C1: launch `F`(config), `P`, `S`, `T`; the checks of section 3; capture cadence,
decode time, AX time and guard-restore time measured. C2: 30 s at rest with the
guard on — drift with our items present.

### O0 — replicate the original anomaly (F-mid)

The original topology: one process holding a spacer created at 1 and three
24 pt probes, as `axspike2g`. Paths: **jump** 1 → 600 and **step** 1 → 300 → 600.
N = 3 each, full reset between. Captures + AX at 0.25, 0.5, 1, 2, 4, 8 s.

O0 has its own topology check, because the section 3 roles do not map onto it:
there is no `P`, and all three probes are targets that are **expected** to
vanish. Checked instead: our four items sit left of every user item, nothing of
the user's is left of them, and each probe carries a distinct marker so the
captures say which ones are visible. No `P` is added — it would change the
topology being replicated. The user-item guard, the deadman and the room/pill
rules apply unchanged.

### Scan — per config coarse jump scan

From rest, jump to every length on a 32 pt grid up to 1200, plus 2000, 5000,
10 000, with the reset type that is safe before O1 (full). Yields brackets for
every quantity, `S`'s left bound, the `«` template and the attribution check.
Bisection later happens only **inside** a bracket found here, per config and
path — never inside one borrowed from another config.

### O1 — protocol for this topology (F-mid)

At `W_hide`, `W_edge` and `W_top` brackets ± 8: jump from a full reset, jump from a
light reset (`S` back to rest, verified), and a Δ=16 step path. N = 3, holds to
8 s.

### Outcome table for O0 and O1 — rows checked in this order

| # | observation | conclusion |
|---|---|---|
| 1 | one path's own repeats differ in pixels | protocol not fixed → **stop and report** |
| 2 | paths differ in pixels at hold ≥ 2 s | path dependence → every number labelled with its path; jump primary |
| 3 | paths differ in pixels only before hold h* | settle → hold ≥ 2·h* |
| 4 | pixels agree; AX disagrees with pixels on a path | stale AX **reproduced** (MEASURED) |
| 5 | pixels agree; AX agrees | anomaly not reproduced; stale AX stays INFERRED |

For O1 additionally: if full and light resets agree, Stage M may use light
resets; otherwise full.

### M — characterization, configs F-narrow (app menu only, ≈ 80), F-mid (7 menus, ≈ 365), F-wide (ends just left of the notch, ≈ 700)

Expected edges are targets; the report uses measured ones. Per config:

- **scan** (above), then **jump**: bisect each bracket to ±4 pt, N = 3.
- **up**: staircase from rest, Δ=16, Δ=4 within ±32 pt of each bracket, to
  `W_top` + 3 steps; **down**: from there back to rest, same steps. N = 3. A harm
  stop ends the config.
- **toggle**: 5 cycles rest ↔ the candidate width (middle of the jump interval)
  on the same items. `T` must be overflowed at the width and visible at rest each
  time; a failure **vetoes** that config's interval.

### A — analysis

Per (config, path, bound): brackets, spread over repeats, three-valued verdict,
margin; the headline over the smallest bound; the informational records; the
intersection of per-config jump intervals (whether one constant serves all
three). Any relation claimed between a transition and the geometry (which has
two spans on this display) must hold in all three configs within ±4 pt, or it is
not written as more than a coincidence.

### Duration

B0 1 min; C 6 min; O0 2 min; scans ≈ 4 min each; O1 ≈ 11 min; M ≈ 15 min per
config. About 80 min of machine time, in runs of ≤ 20 min. The Mac cannot be used
during a run; the user is told before each one.

## 7. Code layout

SwiftPM package `docs/macos-27/probes/safewidth/`, outside the Xcode build:

| target | kind | contents |
|---|---|---|
| `SafeWidthCore` | library, no AppKit/AX/CG/ImageIO (IceCore's rule) | RGBA buffer, marker search, template search, presence, pixel-first settle, guard (persistence, neighbour rule, room drift), per-leg brackets, verdicts, scan/bisection planner, runner over a `World` protocol |
| `SafeWidthCoreTests` | swift-testing | unit tests; runner tests against a scripted fake `World`: harm, stale AX, drift, pill, focus loss, helper death, deadman, never settling |
| `swctl` | executable | the only AppKit/AX/ImageIO/`screencapture` code: `World` adapter, `S` with Ice's sequence, stages, evidence writer |
| `swhelper` | executable | `T` / `P`; marker; pid watch |
| `swfront` | executable | `F` |
| `build.sh` | script | builds with a scratch path outside `~/Documents`; assembles and ad-hoc signs the `.app`s there |

## 8. Tasks, in run order

| # | task | DoD |
|---|---|---|
| 1 | skeleton, `build.sh` | builds with an outside scratch path; signed `.app`s; only sources in the repo |
| 2 | TDD pixels: buffer, marker search, template search, presence | red first; unique-match and negative-control cases; x in points |
| 3 | TDD guard | 2-capture persistence; neighbour rule; unknown → stop; pill AX/pixel rule; room drift; own-action rule |
| 4 | TDD settle + runner basics | stable span; timeout → restore; deadman; void rules |
| 5 | helpers, `F`, `swctl` adapters | B0 and C1 pass on this machine |
| 6 | run B0, C (F-mid), O0 | O0 lands on a row; evidence dir complete |
| 7 | TDD brackets, verdicts, planner | per-leg brackets by length; three-valued verdicts; bisection only inside own brackets |
| 8 | scan F-mid, `«` template, attribution, O1 | O1 lands on a row; protocol written into RESULTS.md **before** M |
| 9 | M for three configs | tables per config/path/bound; toggle checks |
| 10 | A, docs | RESULTS.md; FINDINGS updated with tags (order-dependence text per O0's row); probes README row |

## 9. Acceptance criteria

1. `SafeWidthCore` tests pass; its line coverage ≥ 80 % (`llvm-cov report`).
2. IceCore's 14 tests pass; nothing under `Ice/` or `Packages/` changes.
3. O0 and O1 each land on a row of the outcome table; under the chosen protocol,
   repeats give the same pixel class and bracket ends within ±4 pt.
4. For each config × {jump, up, down} × bound: bracket and verdict. Overall:
   "holds in every measured condition", a named counterexample, or "insufficient
   evidence" with what is missing.
5. Safety: no harm event, or each one reported with captures and measured
   exposure; session-end user templates match B0 (dynamic items verified by the
   neighbour rule); no `com.icespike4.*` process alive; frontmost app restored;
   every run's evidence manifest complete.
6. FINDINGS: every new statement tagged MEASURED or INFERRED; nothing from the
   Refuted table used as a premise.

## 10. Test strategy

Unit: tasks 2, 3, 7. Integration: task 4's runner against a scripted fake
`World`, every failure path. E2E: B0/C1 are the smoke test gating all runs;
O0 → M are the end-to-end runs.

## 11. Impact

Repo: `docs/macos-27/probes/safewidth/`, this plan, edits to `FINDINGS.md` and
`probes/README.md`. Outside the repo: `~/IceReverse-evidence/`. Machine: three
helper apps and one CLI create status items; `F` takes focus during runs
(~80 min total). User items: never acted on; affected only if the menu bar's
own layout reacts to our spacer in an unseen way, which the guard and deadman
bound.

## 12. Risks and rollback

| # | risk | mitigation |
|---|---|---|
| R1 | unexpected harm to a user item | no deliberate harm, continuous guard, deadman, config stop |
| R2 | false marker matches | colours from B0, two-colour + unique match, negative control, user rects excluded |
| R3 | stale AX read as state | pixels primary; AX accepted only between agreeing captures |
| R4 | drift read as harm or transition | B0 static/dynamic, neighbour rule, room drift void, pill rules |
| R5 | actors not where assumed | pixel-verified order and "nothing of theirs left of `T`" at every reset |
| R6 | `F` activation refused | `open -n`, frontmost verified, config void |
| R7 | room too tight | C1 room check, labelled fallback rest |
| R8 | over-generalisation | scope stated in §2; three-valued verdicts |

Rollback: all additive. Delete the package, this plan and the evidence dir;
revert the two doc edits. Runtime state dies with the processes.

## 13. Unknowns ledger

| unknown | answered by |
|---|---|
| Was the FINDINGS order dependence stale AX? | O0 |
| Does `T` cross the notch or overflow at its edge? | scans (`W_top` label) |
| Where does `«` appear; does it shift user items? | scans, template search |
| Is `S`'s left bound set by `F`? | scans across configs |
| Does `S` cover `F`'s menus? | informational record |
| Does state survive a light reset or a toggle? | O1, toggle checks |
| Where is the pill relative to new items? | C1 |

Premortem — "the numbers were wrong because…": AX was stale again; the pill
moved the room; an icon changed appearance and looked like harm; a marker
colour matched the wallpaper; the helpers were not where we thought; a bracket
was borrowed from another config; the user clicked during a run. Each has a
mitigation above.

---

## Appendix — review debate

### Round 1

Codex failed on quota mid-read (`You've hit your usage limit … 5:41 PM`) and was
replaced by an independent Opus 5 adversarial reviewer (24 items). Rulings as
recorded in v2: 18 adopted, 6 modified or partly rejected (2, 7, 8, 10, 17, 24).
Item 1 verified in person (`menubar-600pt.png`: `«`, no probes).

### Round 2 — the six disputed items

| # | Opus 5 | Codex | outcome |
|---|---|---|---|
| 2 | accept | re-raise: presence can be satisfied by a neighbour or the spacer; no baseline before our first launch | **Codex wins** → B0 before anything of ours; neighbour rule; unverifiable → stop |
| 7 | accept | re-raise: per-capture checks are not continuous protection; hold 8 s vs timeout 5 s; exposure promise unverified | **Codex wins** → ≥ 4 Hz guard incl. holds, per-call deadlines, deadman, exposure measured not promised |
| 8 | re-raise: the pill pushed into overflow is filed as a toggle; the pill may sit left of `T` | accept | **Opus wins** → pill AX-present ∧ pixel-absent = harm; C1 checks nothing of the user's is left of `T` |
| 10 | accept (plus N7) | re-raise: down-leg ordering by length; guard stop vs reset+jump down is a contradiction and not the inverse path | **Codex wins** → ordering by length; harm stop ends the config, down untested |
| 17 | re-raise: exclude user rects; second colour near the wallpaper | accept (plus unique match) | **Opus wins** → user rects excluded, colours from B0, negative control, unique match |
| 24 | accept | re-raise: one toggle at one width proves nothing about other configs | **Codex wins** → toggle per config at the candidate width, failure vetoes |

### Round 2 — new items

| source | item | ruling |
|---|---|---|
| Codex 1 | order dependence adjudicated early; no row for "not reproduced" | **adopt** → O0 replicates the original topology; outcome rows 4/5; FINDINGS text follows O0 |
| Codex 2 | three different "clamp" observables conflated; "literal reading" wrong | **adopt** → `W_edge`, `W_sat`, `W_selfov` separate; verdict per bound; user picks the reading |
| Codex 3 | bisection has no valid bracket (visible→hidden→visible) | **adopt** → per-config coarse jump scan first; bisect only inside own brackets |
| Codex 4 | verdict ignores measurement uncertainty; `W_harm > L_max` overclaims | **adopt** → brackets, three-valued verdict, grid listed |
| Codex 5 | `«` does not identify `T` | **adopt** → quit-`T` attribution; "overflow unconfirmed" not counted |
| Codex 9/10 | toggle scope; Ice extrapolation (image cleared, no-divider path) | **adopt** → `S` follows Ice's chevron sequence; conclusions scoped; "records what Ice does today" deleted |
| Codex 11/12/13 | pill stratification; unique match; "same instant" impossible | **adopt** |
| Codex 14 | cost inversion; evidence only in volatile scratch; **drop the 80 % coverage gate** | **adopt** run order and durable evidence; **reject** dropping coverage: the 80 % gate is the user's own DoD (global CLAUDE.md §9) — user-decided, not re-debated |
| Opus N1 | no "not reproduced" row; row precedence | **adopt** (same as Codex 1) |
| Opus N2 | duration too low; seed brackets | **adopt** with Codex 3's per-config scans; recounted ≈ 80 min |
| Opus N3 | `S` marker invisible after give-back and under `F`-wide menus | **adopt** → AX minX fallback, flagged |
| Opus N4 | rarely-changing icons misread as harm | **modify** → neighbour rule instead of AX (AX is the stale signal) |
| Opus N5 | room drift from width-changing items | **adopt** → room recorded per sample, >1 pt drift voids |
| Opus N6 | cooperative activation vs child processes | **adopt** → `open -n` + pid argument |
| Opus N7/N8/N9/N10/N11/N12 | clause contradiction; left bound needs growth; circular `«` template; rest numeric value; exposure unmeasured; "background" undefined | **adopt** all |

### Round 3 — Codex convergence check on v3

"No other P0 within scope." N4 modification (neighbour rule instead of AX):
accepted by Codex. Two P1 items introduced by v3, both **adopted**:

| item | ruling |
|---|---|
| "any helper death voids the trial" collides with the deliberate quit of `T` for attribution | exception written into §3; full reset after attribution |
| O0's original topology has no `P` and its probes are expected to vanish, yet C1's `T < S < P` / `P`-lost rules were implied | O0-specific topology check written into §6; no `P` added |

No item left in dispute. Plan final.

### Round 4 — Codex after the runs (code review of the four commits + claims against the raw evidence)

Run after Codex's quota reset: `codex review --base safewidth-review-base`
(58afb9c..f6d1f02) and a `codex exec` pass reading `~/IceReverse-evidence/`.
Every item was checked against the code or the JSONL before a ruling.

| source | item | ruling |
|---|---|---|
| code P1 | attribution and template validation expand and rest outside the latch | **adopt, extended** → every expansion goes through `Actors.expand` (refuses once stopped or fired, latches what the guard says); also O0's discarded rest outcome, and the attribution failure path that left `S` expanded |
| code P1 | a light reset can latch a stop, then `jump` expands anyway | **adopt** → `jump` re-checks `canExpand` after its resets |
| code P1 | the pill rule needs the pill's orange to identify it, so a pushed-out pill is never seen | **adopt the finding, reject the remedy** → Codex proposed carrying a colour-confirmed identity across captures; that cannot see a pill that arrives already squeezed out, which is the case the rule exists for. Instead the chevron is identified by its AX width (17.5 pt, every reading) and anything else leading is the pill; a hidden pill no longer voids as `pillToggled` (`pillAXPresent` → `pillDrawn`), so the guard's persistence decides |
| code P2 | a censored repeat's `maxTested` is ignored once any repeat observed the bound | **adopt** → it caps the margin; two tests, one Codex's own example |
| code P2 | hold samples are discarded; the staircase never holds | **adopt** → a probe with holds is characterised by the state after the longest; M passes `--hold` to staircase and toggle. Latent: no reported run used `--hold` |
| claims | "the second stop latched" | **adopt** → neither latched; 54 expansions between, 6 after (to 10 000), all guard-clean |
| claims | `W_edge` and `W_selfov` "the same event" | **modify** → the two AX readings differ by path (staircase edge stays at 368; jump x back at 1012), so "same event" is INFERRED — but the pixels add a path-independent transition at (652, 656] that Codex did not raise, now in the tables |
| claims | O1 "N = 3" | **adopt** → N = 2 at 632–872, 872 step N = 1 (a failed reset), one 32 pt step void |
| claims | "guard restore 1.27 s" | **adopt** → a return to rest from 8 pt; the guard did not fire |
| claims | FINDINGS lists `W_selfov` without its AX qualifier | **adopt** → a "read from" column |
| claims | "`W_top` cannot be bisected; ≈ 672–832" | **adopt** → the staircases bracket it at (836, 852] up / (848, 864] down; the state between starts at 656 |
| claims | "every reported run rests at Ice's rest" | **adopt** → scoped to O1, scan and M |
| claims | "Ice's constant hides nothing" | **modify** → MEASURED for our spacer, INFERRED for Ice; kept as the headline |

The rejected remedy goes back to Codex with the fix diff.

### Round 5 — Codex on the round-4 fixes

`codex review --uncommitted` plus a `codex exec` re-review of the rejected remedy.

| item | ruling |
|---|---|
| debate: the pill remedy | **Codex concedes**: a sticky colour-confirmed identity cannot cover a pill that is squeezed out on arrival; no counterexample where the width rule fails and its remedy succeeds. No other round-4 ruling disputed |
| review P2: `holds.last` is not always the latest observation — a short hold can expire mid-transition, before settling | **adopt** → `ProbeOutcome.settled` carries `latest`, the capture the probe ended on (the later of the settled capture and the last hold); `Actors` characterises by it; a test for a hold that expires before settling |

No item left in dispute.

---

## Deviations (ledger, written as they happen)

Format: trigger → conservative option taken → reason.

1. B0 (run `20260918-190735-b0`) found Safari frontmost, the microphone pill
   absent, and a Chrome item leftmost at x=1072 → nothing changed in the
   protocol; room right of the notch is still ≈ 115 pt → recorded as the B0 facts.
2. The wallpaper changed between 16:12 (yellow bar, black icons) and 19:07
   (dark red bar, white icons); the bar is translucent, so every template and
   the icon colour depend on the time of day → **every controller run takes its
   own 8-capture baseline before launching anything** (templates, static/dynamic,
   ink colour, marker negative control); the session B0 only supplies the marker
   colour candidates → a wallpaper change mid-run shows up as a guard stop, which
   is safe, and the run is repeated.
3. Captures were 33 pt tall; the bar is 32 pt and the bottom row belongs to the
   window underneath (48/48 dark columns under the Chrome item) → every decoded
   strip is cut to 32 pt → the row below the bar changes with other windows and
   polluted presence counts and templates.
4. Presence was defined as "dark pixels"; icons are white on a dark bar and some
   (Chrome) are coloured → presence uses the run's ink colour (white on a dark bar,
   black on a light one) → a coloured static icon that changes appearance will
   read as lost and stop the config: a false stop, never a missed harm.
5. `open -b <bundle id>` cannot activate our helper apps (they live in a scratch
   directory and LaunchServices has no record of them), and an app with no
   windows loses the front as soon as a background helper launches — the frontmost
   app during the first C runs was the user's terminal, not F → F now has a small
   window in the bottom-left corner (away from the strip and from what shows
   through the bar), re-activates itself when it resigns active, and is activated
   by path → without this the F config dimension is not actually in effect.
6. One assessment took 1.4 s because the AX walk asked every running app and paid
   the messaging timeout for each unresponsive one → the walk now asks only the
   pids that owned a menu bar extra at this run's baseline, and the frontmost
   app's menus are read once per config instead of once per capture → 78 ms
   median, ≈ 12 Hz, which is what the guard needs.
7. S's edge markers are drawn only while S is at rest; an expanded spacer renders
   nothing (Ice's does the same) → "is S still taking room" reads S's AX x
   instead, flagged as an AX-derived value: while S squeezes its x moves left,
   and when it gives the room back its x returns to the rest position while its
   window keeps growing rightward.
8. The `«` template stopped matching as S grew: the bar is translucent, so the
   same glyph over another part of the wallpaper is a different crop → the
   chevron is now "a new MenuBarAgent item in AX **and** ink pixels drawn in its
   span"; the validated template is kept as a corroborating signal.
9. Phase 3 review (four cleanup agents + Codex, after the measurements were in)
   found the guard's own microphone-pill rule inert — the live code passed no
   pill reading in, so "AX-present ∧ pixel-absent = harm" could never fire →
   wired in, and RESULTS says plainly that the rule was not what protected the
   bar during the reported runs → a rule nobody can trigger is not a safeguard.
10. The same review found a `stop` was not latched: a stage kept expanding after
    the guard said it could not verify the bar → `stop` now latches in `Actors`
    and every stage, toggle included, refuses to expand afterwards.
11. `Runner` checked focus, helpers and the pill **before** the guard's verdict,
    so a capture showing both harm and a lost focus was reported as a plain void
    → the guard's verdict is now read first, with its test rewritten to pin the
    new order → the one that matters must not be the one that gets dropped.
12. Two claims in RESULTS were stronger than the evidence: "no guard event fired
    in the entire campaign" (a superseded scan had two `stop` decisions) and a
    verdict table that hid narrow's partial up leg → both corrected against the
    raw JSONL, and `W_selfov` is now labelled AX-derived → this is the same
    failure mode the whole Refuted table is made of.
13. Codex's post-run review (appendix, round 4) found entry 10 was not true:
    the latch had gaps — attribution and validation bypassed it, and a light
    reset could latch a stop that the jump then ignored — and the pill wiring of
    entry 9 was inert a second time, because identifying the pill by its orange
    excludes exactly a pill that has been pushed out → one latched `expand` for
    every stage, and the chevron identified by width instead of the pill by
    colour → two rounds of "fixed" each needed another review; a safety claim is
    only as good as the last reviewer's read of the code.
14. The same review's claims pass found RESULTS still stronger than the JSONL in
    eight places, and entry 12 itself misplaced the two `stop` decisions: they
    were in the **reported** mid scan (`20260918-202525-scan-mid`), not a
    superseded one → every claim re-checked against the JSONL before being
    rewritten; the staircases turned out to bracket `W_top` and to show a
    path-independent pixel transition at (652, 656] the tables had left out.

## Open thread for the next session

- The user explained what `«` is: macOS 27's own fold, triggered when the items
  exceed the room right of the notch, expanding back across the notch. The
  attribution check says Ice's squeeze-out hiding *is* that fold, so a fixed Ice
  raises the chevron every time it hides. Written into FINDINGS.
- The one measured exception is the 656–836 pt region (848 coming down: no
  chevron, target drawn nowhere, AX still claims an on-bar x). Mechanism
  unknown. Next experiment, if it is wanted: is that state clickable, does it
  survive an app switch, does it come back reliably, and does it move with the
  number of user items?
- Codex's post-run review is done and ruled (appendix, round 4). The latch and
  pill fixes are unit-tested in `SafeWidthCore` but have not run live; the
  first live run should confirm the pill rule on a real pill (its AX width and
  where AX puts it when pushed out are unrecorded).
