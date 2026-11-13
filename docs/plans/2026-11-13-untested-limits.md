# The limits left by the settings pass: test what automation can reach, then the open items

2026-11-13 · branch `wip/s5-owner-acceptance`, from `1ade8e9` · mode: normal (no loop),
serial (one bar, one pointer: no agents).

## The owner's ask

"沒測試的 先測試，修改的沒確認的 等測試完 告訴我要怎麼確認，都做完 開始把沒做的 開始進行."
In this order: (1) the limits in STATUS's settings-pass section that were never run,
tested by automation; (2) then how the owner confirms the repair they have not seen
(`73ce7c8`); (3) then the open items: push, the rename, installing as the daily Ice.

The owner tests nothing; a limit automation cannot reach is said plainly, not handed
over as a checklist.

## 1. What is tested, how, and what passes

The harness of the settings pass (`settings_lab.py`, `settings_cases.py`,
`settingsdrive`, `settingsfront`), its rules unchanged: a lab-identity copy started by
path, the release Ice's settings exported and compared, sacrificial helpers only, idle
guard, evidence in `~/IceReverse-evidence/<run>-s6/`. The helpers and `icewatch` are
built by `build.sh` into a private scratch directory and reached through `S6_SHARED`:
`/Users/Shared/IceReverse-lab` stays deleted (the owner's cleanup of 2026-11-12), and
`stage-lab.sh` is not needed (it stages for the `icetest` account, which is gone).

| # | Limit (STATUS) | Case | Passes when | If it fails |
|---|---|---|---|---|
| L1 | The custom icon's file chooser was not driven | `L1`: General, Ice icon -> Custom, the chooser opens; Command-Shift-G, the path of a 16 x 16 PNG in the run directory, Return, Return | the chooser is an on-screen window of the lab copy; `IceIcon` stored afterwards holds the image's data; Ice's icon on the bar reads a different pixel mean than before | repair, or remove "Custom" on 27 (the rule of the settings pass: what does not work is not offered) |
| L2 | A click that brings another app forward may come before that app is active (smart rehide, 250 ms) | `L2`: smart rehide on; two `settingsfront` windows, A in front; IceBar opened by a click on empty bar; click B's window, which activates B. 10 tries | closed within 2 s in 10 of 10 | repair: after the 250 ms, wait for the clicked app to become active up to a bound (1 s), then decide; unit-tested in `SmartRehideRule`; L2 again |
| L3 | After leaving `blocked`, the machine hides on the first sample with the roster as it was | `L3`: one member hidden; Ice's own icon Command-dragged left of its divider (`blocked(iconLeftOfDivider)`); while blocked a second Target helper is started (it lands leftmost, left of the divider); the icon dragged back. Sampled every 0.2 s from the drop: the new helper either on the bar or listed in the IceBar roster. 3 tries. Control: the same helper started while Ice rests | the new helper is "listed nowhere" (pushed off and not in the roster) for no longer than in the control plus 1 s, and is listed in the end | repair: leaving `blocked` holds as leaving arranging does (no length until a pass that began afterwards was read); L3 again |
| L4 | Launch at login: that a login starts Ice | not by automation: it needs a logout of the owner's session. Carried into the install (section 3): after the next login the owner makes anyway, the log says whether the 1.0 copy was started by the login item | MEASURED then, from `log show` and the process start time | not run until then |
| L5 | Screen Recording granted while Ice runs may not be seen until a restart | not by automation: granting needs the owner's password in System Settings, and a probe of the opposite direction needs a grant first | stays INFERRED; said so | -- |
| L6 | One Mac, one display, macOS 14 to 26 | not runnable here | stays a stated limit | -- |

Mode on (the other half of L3's limit): on 27 "Use Ice Bar" is not offered and the mode
is on from launch; a fresh launch's roster is empty until its first pass, and `start`
needs members: not a case.

Unit tests first for any repair (TDD), then the live case again. Code goes through
`/simcodex` before anything is reported.

## 2. Confirming `73ce7c8`

It was measured by automation on 2026-11-12 (D2: 10 of 10 quick drags in, run
`-203533-s6`), not seen by the owner. What the owner is told: nothing to do but use it;
the sign of the defect is an item dragged in that is then neither on the bar nor in the
IceBar.

## 3. The open items, after 1 and 2

| # | Item | How |
|---|---|---|
| O1 | Push `wip/s5-owner-acceptance` to `origin` | the standing approval for the `wip/` branch (handoff rule); the untracked `CLAUDE.md` left out |
| O2 | The rename | the name is the owner's: one plain question after a `thecure` debate on whether the bundle id changes with it (it decides O3) |
| O3 | Install as the daily Ice | replaces the owner's `/Applications/Ice.app` (release 0.11.13-dev.2): a backup copy first, the release's settings exported; an ad-hoc build loses the release's Accessibility and Screen Recording grants (they follow the signature), so the owner grants them once. Asked once, with that cost, before anything is touched |

## Codex on this plan (one review, REVISE: 4 P1, 4 P2), and what changed

| # | Point | Answer |
|---|---|---|
| 1 | P1: two `settingsfront` windows overlap; a click meant for B lands on A | one `settingsfront` only: the app in front is the owner's, as in G6; the floating window takes the click; the driver checks the pid at the point |
| 2 | P1: ten closes do not show the late-activation branch was met | each try records when `settingsfront` became front after the button went down (polled every 20 ms); a try is read against the 250 ms decision point |
| 3 | P1: the repair is not unit-testable where the plan put it | if L2 fails, the decision (delay, activation, bound) is taken out of `HIDEventManager` into an IceCore rule with an injected activation reader, tested there first |
| 4 | P1: the helper may be in the roster before the drop | the helper is started at an offset from the drag that puts the icon back (-1.0, +0.5, +1.4 s); the report's roster events say whether the roster at the drop held it; the case needs one try where it did not, and then asserts the order: no length before a roster with the item; the item never pushed off unlisted (0.4 s of sampling slack), not "control plus 1 s" |
| 5 | P2: leaving `blocked` goes to `quiet`, no length on that sample | the case asserts the event order, not a mechanism |
| 6 | P2: `resetIceBarRoster` runs on mode off, not on | corrected: on 27 the mode is on from launch, and a fresh launch's roster is empty until its first pass |
| 7 | P2: a pixel mean is a weak oracle for L1 | the stored icon's data is compared byte for byte with the chosen file; the colour on the bar is secondary |
| 8 | P2: L4, L5 rightly not automated; a start time after a login is not proof the login item started it | L4 reads the launch's parent (`launchd` via the login item record in `sfltool dumpbtm` and the unified log's `backgroundtaskmanagement` lines), not the time alone |

## 4. Stop rules

Each live case at most 3 attempts; a case that cannot get an idle Mac in 10 minutes is
`notRun`. `/simcodex` at most 3 rounds. Codex on this plan: one review, its points
answered here, then the cases.
