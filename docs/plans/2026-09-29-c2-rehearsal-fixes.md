# C2 rehearsal fixes (2026-09-29)

Amends `2026-09-28-c2-protocol.md`. Source: the first sitting A attempt,
`20260929-002955-c2A` (macOS 27.0, 26A428), which stopped after 47 s with no
points.

## What the run showed

| step | result | cause |
|---|---|---|
| 1, 2 `k1-long` | `menus.calibrationFailed: no menu count puts the last title in long` | step 1 ran with the isolated session on console (MEASURED: loginwindow log, switch away at 00:30:35) |
| 3 `k1-long` | child exit 2, no evidence directory -> runner fail-closed `safetyStop` | `step1.setup: no bar geometry (NSScreen.main unavailable)`: the owner had switched back to their own account (MEASURED: Terminal output + loginwindow log) |

Calibration cause, INFERRED: `launchAndCalibrateMenus` reads the Menus
helper's title edges *before* activating it, so Terminal owns the bar during
calibration and the helper's titles are not laid out there. Not confirmed:
calibration reads were not recorded. (Ruled out: too few menus -- the helper is
`.regular` and 40 `Mnn` titles are far wider than 1000 pt.)

## Changes

1. **Activate before calibrating** (`StageC1Menus.swift`): activate Menus right
   after `up`, then calibrate. The existing post-calibration activation and
   frontmost check stay.
2. **Record every calibration read** (`menus.calibrationRead`: count,
   lastTitleEnd or null), so a repeat failure is diagnosable from evidence.
3. **Console guard** (`C2Run.swift`): refuse to start off console; before each
   step, if the session is no longer on console, record `sessionOffConsole` and
   finish as `safetyStop` for that configuration, with a stderr line saying so.
4. **Progress lines** (`C2Run.swift`): one stderr line per step start and end
   (step, configuration, wall time, elapsed), so the owner can see progress on
   screen without touching the Mac. The final verdict line is unchanged.
5. **Roster refusal message** names the foreign bundle ids, and an empty read
   gets its own message (done 2026-09-29, before this plan).

## Tests

- `I7C2MenusTests`: a fake whose titles are only laid out while Menus is
  frontmost still calibrates (RED before change 1); calibration reads are
  recorded, one per `menus <n>` sent.
- Existing C2/I7 suites stay green.

## Owner instruction added to section 7

Once the command is pasted, stay in the isolated account until the runner
prints its final `c2-run: sitting A: ...` line; switching away stops the
sitting.
