# Can Ice hide menu bar items on macOS 27? -- the feasibility gate

2026-09-25 · branch `wip/hiding-feasibility` (from `main` d21e1e6) · **v1, desk
research only; no experiment has been run.** The owner approves this plan before
anything that changes the menu bar's state, and each stage in section 6 needs its
own go.

Converged order (not re-opened): first this gate -- hiding that is reliable and
recoverable across layouts, app switches and Spaces, or a declared read-only
macOS 27 -- then showing item images, then the XPC service on its own (most
likely disabled, not fixed).

## 1. The decision this plan produces

One of two outcomes, written up for the owner:

- **GO** -- at least one mechanism passes every gate criterion (section 3). Its
  implementation is a separate plan (section 8 lists what it would touch).
- **NO-GO** -- none does. macOS 27 is declared read-only: `STATUS.md` already
  says that this is the fallback, and section 9 lists what read-only mode changes.

A candidate is dropped the first time it fails a kill criterion (G1, G3 or G6),
after one replication to rule out a flake. The study stops as soon as the outcome
is settled.

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

| # | criterion | measured how | kind |
|---|---|---|---|
| G1 | **effect**: every item chosen to be hidden is not drawn; no `«` appears; nothing else disappears (other items, system items, the microphone/camera indicator) | the pixel detector plus a strip check of every other listed item; AX only says where to look | kill |
| G2 | **robust**: G1 still holds after (a) the frontmost app changes (narrow, mid, wide menus); (b) an item appears or leaves while hidden; (c) a Space switch, including into and out of a full-screen app's Space; (d) display sleep and wake, screen lock and unlock; (e) a second display, if one is attached | N >= 5 each; a verdict of `unreadable` counts as not shown, never as a pass | kill for (a)-(c); (d)-(e) owner may accept a stated gap |
| G3 | **recoverable**: showing restores every hidden item within 2 s; after Ice quits, after Ice is killed (SIGKILL), and after `MenuBarAgent` restarts, the bar returns to its true state with no manual step | detector plus the strip check, N >= 3 each | kill |
| G4 | **verifiable at runtime**: Ice itself can tell that G1 holds on the user's bar, or it would fail silently | the check's verdict on the mechanism's own state | kill for C; E and D may substitute the OS's own state if it can be read |
| G5 | **selectable** at the granularity Ice offers (per item, per section) | by construction | value call if only per app |
| G6 | **supportable**: no private entitlement; no side effect beyond the menu bar; nothing the user cannot undo from System Settings if Ice is gone | read + observed during G1-G3 | kill |

## 4. Order of candidates, and why

1. **E first.** If the OS offers the switch, it is robust by construction
   (persisted, applied by the agent itself, restored by it, visible and reversible
   in System Settings) and needs no geometry. What can kill it is cheap to learn:
   whether it exists on 27 as a user setting, whether a third party can set it
   without an entitlement or a privacy prompt, and whether per-app granularity is
   acceptable (G5, the owner's call).
2. **C second.** Public API and Ice's own mechanism at another length. What can kill
   it: the band moving with the room (so a fixed length fails G2a/b), a runtime
   length choice the detector cannot confirm (G4), or the band not surviving a
   Space or app switch.
3. **D last.** A private "assessment mode" assertion whose allow-list hides
   everything unlisted -- including items that appear while it is held -- with no
   measured restore on invalidation or on holder death. It is attempted only in an
   isolated account, and only if E and C both fail.

## 5. Environment

- **Sacrificial helpers only**: `com.icespike4.target` / `.protected` (vzhelper);
  never the user's items; the user-item safety monitor stops a run on two
  consecutive misses.
- **An isolated macOS user account is strongly preferred**, and required for D and
  for C's transfer runs: an empty bar gives the room this account lacks, and nothing
  of the owner's can be hidden by an allow-list or displaced by a spacer. Creating
  it is the owner's action.
- Ice itself is not run in stages 0-2 (the mechanisms are exercised by the probes);
  a stage-3 run of a modified Ice would be a separate go.
- Event injection (a Space switch by Control-arrow, clicks) happens only with the
  owner's explicit go for that run; the alternative is the owner doing it by hand
  while the instrument records.
- Session-wide steps -- display sleep, screen lock, `killall MenuBarAgent` -- each
  need their own go.
- No recordings kept; captures used for verdicts are deleted afterwards or kept only
  in the evidence directory, as the owner decides. Output that names apps goes only
  to the evidence directory.

## 6. Stages

Each task: what, then DoD.

### Stage 0 -- desk and eyes only, no state change

| # | task | DoD |
|---|---|---|
| S0.1 | The owner opens System Settings' menu bar settings **and only looks**: is there a per-app "allow in the menu bar" list, and are the sacrificial helpers in it? | yes/no recorded, with a screenshot the owner may delete |
| S0.2 | Read-only: where the tracked-application store lives, who owns it, whether it is under an app-data privacy fence (reading another group container can raise a privacy prompt -- so this runs with the owner present, or not at all) | ownership and protection recorded; no content read |
| S0.3 | Read-only: `MenuBarAgent` log lines for `Disallowed application` over the last day (count only), to learn whether the gate already acts on this machine | count recorded |
| S0.4 | Decide the environment: isolated account yes/no; second display yes/no | recorded; it scopes stages 1-2 |

**Kill after stage 0**: if S0.1 finds no such setting, E is dropped.

### Stage 1 -- does the mechanism exist (helpers only; each run its own go)

| # | task | pass | DoD |
|---|---|---|---|
| E1 | The owner switches the **helper's** entry off in System Settings (by hand -- nothing programmatic yet), then on again; the instrument watches | helper not drawn, no `«`, nothing else changed; on again restores it; the setting survives the helper relaunching | verdicts, N = 3 |
| E2 | Only if E1 passes and S0.2 allows: can a third-party process change that entry for the helper (the public preferences path, or the private setter), without an entitlement or a prompt? | it can, and E1's pass holds | yes/no, with the error if no |
| C1 | Reproduce the band on today's build with the helper as target (the safe-width instrument, jump path); bisect the upper edge, which was never bisected | the band exists; both edges bracketed to 4 pt | brackets recorded |
| C2 | In the isolated account: repeat C1 with 1-4 helper items and three frontmost-menu widths | the band's edges move less than its width, so one length can serve all layouts -- or they move predictably from a quantity Ice can read | edges per configuration |
| C3 | In the band: does the detector give `hidden(folded: false)` for the target, and `restored` after showing -- or does the AX placement veto refuse? | the detector decides; no `contradictsAccessibility` | verdicts, N = 5 |
| D1 | Isolated account only, and only if E and C are dead: activate the assertion allowing everything except the helper; observe; invalidate; then kill the holding process | only the helper disappears; invalidation and holder death both restore; no side effect outside the menu bar | observations, N = 3 |

### Stage 2 -- robustness and recovery (surviving candidates only)

G2 (a)-(e) and G3 as defined in section 3, N >= 5 (G3: N >= 3), with the
candidate hiding the helper. Each dimension is its own run and its own go where
section 5 says so. The first failure of a kill criterion ends that candidate after
one replication.

### Stage 3 -- decision

A report to the owner: per candidate, the gate table filled in with MEASURED
results, the kill (if any) and the evidence; the GO/NO-GO recommendation. The
value calls in section 7 are put to the owner, with Jev's per-requirement reading
beside them.

## 7. Value calls the owner makes (not decided by evidence)

- **V1** Per-app hiding (E) instead of per-item: acceptable for macOS 27?
- **V2** IceBar mode, the owner's configuration, cannot show hidden items on 27. Is a
  hider useful without it, i.e. with items expanded in place -- or does the gate
  also require the image track first?
- **V3** Whether a private-API mechanism (D) may be considered at all, given
  FINDINGS' "do not build core behaviour on it".
- **V4** Whether G2(d) (sleep, lock) and G2(e) (second display) may be accepted as
  stated gaps rather than kills.

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
| a stage changes the owner's bar | helpers only; isolated account for D and C2; the safety monitor; each stage its own go |
| E is a system setting, so an experiment changes System Settings state | only the helper's entry, switched back at the end of the run; the owner does it by hand in E1 |
| D leaves a restriction in place after its holder dies | D runs only in the isolated account, last, and its first observation is holder death |
| measuring disturbs the band (the capture indicator takes room) | C3 measures exactly that; if verification shifts the band, C fails G4 |
| a verdict is unreadable (Space slide, indicator churn) | an unreadable run is inconclusive and repeated, never a pass |
| the study drifts into building | stages 0-2 change no Ice source; implementation is a separate plan |

## Appendix -- review record

(to be filled by the Codex debate and Jev's readings)
