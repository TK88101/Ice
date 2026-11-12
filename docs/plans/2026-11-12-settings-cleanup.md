# Settings: only what works on macOS 27 in this fork

2026-11-12 · branch `wip/s5-owner-acceptance` · the owner's instructions the same day.

## The owner's ruling

This is a local fork for the owner's own use. A setting that does not work on macOS 27
is not shown; what was never tried is tried, then kept or removed on the result, not
on a guess. No self-update. The upstream author's links go; the acknowledgements of the
open-source components and the licence stay (GPL-3.0). Version 1.0 once the repair is
complete.

## Done in the first step

| # | What | State |
|---|---|---|
| C1 | The "Menu Bar Layout" pane is not in the sidebar on macOS 27 (Ice cannot move another app's item there). Its two lines, the hiding status and the icon-left-of-divider notice, are in General under "Use Ice Bar" | built; not looked at by the owner yet |
| C2 | The updater is never started and nothing offers a check: the About pane's update section and the menu's "Check for Updates…" are gone. Sparkle stays linked, unused (taking the dependency out of the project is a later step) | built |
| C3 | About: "Contribute", "Report a Bug", "Support Ice" removed; "Acknowledgements" and "Quit Ice" stay | built |

## To be tried, then kept or removed (TBD each)

General: launch at login; Ice Bar location; show on click, hover, scroll; automatically
rehide; item spacing. Menu Bar Appearance: tint, shape, border, shadow. Hotkeys: each
of the five. Advanced: divider style; hide app menus; secondary context menu; hover
delay.

Known not to work, to be removed with that pass: the always-hidden section (T2d: its
divider reads at the hidden divider's frame on macOS 27) with its hotkey; "temporarily
shown item delay" (temporary showing is refused on macOS 27); the search panel's click
(a press there does nothing).

The owner's own findings, 2026-11-12: changing the Ice icon works; "Use Ice Bar" works;
with the location on its default a click anywhere on the bar shows the IceBar under
the pointer ("Show on click" with the dynamic location: as designed, to be confirmed
when the settings are tried one by one).

## Last

Version 1.0 and the name, when every item above is settled.

---

# The pass: every untried setting tried by automation, then kept or removed

2026-11-12, second session · same branch, from `bd1ff18` · mode: normal (no loop),
serial (one bar, one pointer: no agents).

## 1. Goal, non-goals

Goal: on macOS 27 the settings window, Ice's menus and the hotkeys offer only what was
seen to work in a live run driven by automation; everything else is not offered and
has no effect; then the version is 1.0.

Not in this pass: a rename; taking Sparkle or the layout-pane code out of the project;
making a removed feature work instead (the search panel's click, temporary showing,
an always-hidden section); macOS 14 to 26 (not runnable here: their UI and behaviour
stay as upstream, every change is behind `#available(macOS 27, *)` or an
`isMacOS27` argument); the lab matrix; installing as the daily Ice.

The owner tests nothing and is asked nothing. A value judgement the evidence cannot
settle is decided by the rule in section 4 and reported, not asked.

## 2. The harness

All of it under `docs/macos-27/probes/` (one-shot tools, in no Xcode target), built
and run outside `~/Documents`; evidence only in `~/IceReverse-evidence/<run id>-s6/`.

- `settingsdrive.swift`, one file, derived from `dragown.swift`: `move`, `click`
  (left/right, modifiers), `scroll`, `key` (key code + modifiers), `hold-command`
  (down, wait, up), `drag` (Command-drag between two points, slow or within 300 ms),
  `windows <pid>` (CGWindowList: title, layer, bounds), `items` (status items over
  AX: pid, identifier, frame), `axdump <pid>` / `axpress <pid> <title>` (the settings
  window's controls), `shot <rect> <png>`, `selftest`. One JSON object on stdout.
  Guards, as `dragown`: refuses unless the hardware has been idle 5 s
  (`CGEventSource.secondsSinceLastEventType(.hidSystemState)`), re-reads idle before
  every posted event and aborts on hardware input, restores the cursor, releases
  button and Command on abort, watchdog and signals. Presses and drags only at
  points whose AX owner is Ice's lab copy, a sacrificial helper, or empty menu bar
  (the menu bar owner with no item under the point), or a window of the harness's own
  front app (`swfront`-style, for "a click elsewhere"). Never an item of the owner's.
- `run-settings.sh <case>...`: builds nothing; takes an Ice.app built from this
  branch at a scratch path, makes a lab-identity copy (`com.icespike4.lab.r<id>.s6`,
  the `free-run.sh` pattern: explicit path, release Ice's prefs exported before and
  compared after, lab domain deleted at the end, refuses if any Ice runs), writes the
  case's defaults to the lab domain **before launch**, starts Ice with
  `-IceLabReport YES`, starts the helper(s), drives the case, writes
  `<case>.json` (`pass` / `fail` / `notRun` + the measured facts), stops everything.
  Helpers: `Target.app` (one item, `--menu`, lands left of the fresh divider: the
  member) and `Protected.app` (one item seeded right of the divider: a visible
  item that is not Ice's). Their hashes are checked against `lab.env`.
- A case that cannot get an idle Mac within 10 minutes ends `notRun`, never `pass`.
- `test-settings.sh`: the runner against a stub Ice and a stub driver (the
  `test-s5.sh` pattern): guards, defaults written, verdict rules, teardown on
  failure. `settingsdrive selftest`: the pure rules (owner check, idle rule, drop
  points) on made-up frames.

What a case reads: Ice's report (`isIceBarPresented`, `lengthApplied`, roster, cells,
statuses), the IceBar panel's frame from the window list, AX frames of items,
screenshots of the bar strip (pixels compared by the driver; the PNGs stay in the
evidence directory), the lab defaults domain.

## 3. The cases

Every case starts from: IceBar mode on, one member hidden (report: `lengthApplied`,
roster 1, offered). "Shown" = `isIceBarPresented` true and a panel in the window
list; "not shown" = neither, 2 s after the stimulus.

| # | Setting | Stimulus | Works when |
|---|---|---|---|
| G1 | Launch at login | AX-press the toggle on, read `SMAppService` status of the lab copy (a tiny reader in the driver: `launchctl print gui/<uid>` / `sfltool dumpbtm` line for the lab id), press off | status enabled after on, absent after off. Always switched off at the end; teardown checks no login item of the lab id is left |
| G2 | IceBar location: dynamic, mouse pointer, Ice icon | open by a click on empty bar at a known x, and by a click on Ice's icon | panel mid-x within 2 pt of the pointer (pointer), of the icon (icon); dynamic: pointer for the empty-bar click, icon for the icon click; clamped at the screen edge |
| G3 | Show on click | on: click empty bar; off: same; and with it on, a click on the visible helper's item | on: shown, second click closes; off: not shown; **a click on another app's item does not show it** (on 27 `isMouseInsideMenuBarItem` reads a window list that is empty, INFERRED: if measured so, it is a defect to repair, section 5) |
| G4 | Show on hover | on: move to empty bar and rest; move away | shown after the delay; gone after leaving bar and panel; off: not shown |
| G5 | Show on scroll | scroll up / down on the bar | up shows, down hides; off: neither |
| G6 | Automatically rehide: smart, timed (2 s), focused app; off | open, then: click in the harness's own window / wait with the pointer off the bar / bring the harness app to front | smart: closed after the click; timed: closed 2 s (±1) after leaving; focused app: closed on the change; off: still shown after each of the three |
| G7 | Item spacing | **not run through the button**: "Apply" quits and relaunches every app with a menu bar item, the owner's own. Measured instead: with `NSStatusItemSpacing`/`NSStatusItemSelectionPadding` written for the current host, two freshly started helpers' frames against the same two at default; keys deleted after. And read in the code: which pids `applyOffset` would relaunch on 27 (`getMenuBarItems` reads the window list) | kept only if macOS 27 honours the keys **and** `applyOffset` finds the apps on 27. If the keys are honoured but it finds none, the setting changes nothing visible until a re-login: removed |
| A1-A4 | Appearance: tint (solid, gradient), shape (full, split, none), border, shadow | each written as the stored configuration before launch; the bar strip and the 8 pt under it captured with and without | the overlay panel is in the window list and the strip's pixels changed as configured: mean colour toward the tint; border colour on the shape's edge; darker row under the bar with shadow; desktop showing outside a rounded/split shape. Also the editor panel opens from the secondary menu (S2) |
| H1 | Hotkey: toggle hidden section | combination stored before launch (Control-Option-Shift-Command + F13…F17, nobody's shortcut), key posted | IceBar shown, again: closed |
| H2 | Hotkey: toggle always-hidden | known dead with the section (T2d): removed, not run |
| H3 | Hotkey: search menu bar items | key posted; then a click on a row | panel in the window list; the click: known to do nothing (INFERRED from code since 09-25): confirmed once, then removed with the panel's entry points |
| H4 | Hotkey: enable the Ice Bar | key posted | `UseIceBar` flips in the lab domain. See U1 for whether the setting itself stays |
| H5 | Hotkey: toggle application menus | key posted with the harness app in front | the front app's menu titles gone from the bar (AX: Ice frontmost, regular), again: back |
| H6 | The recorder | AX-press a recorder, post a combination with the settings window in front | the combination is in the lab domain and fires |
| V1 | Divider style: none, chevron | each stored before launch; in IceBar mode the dividers rest at `.hideSection`, where neither draws (INFERRED); looked at while resting and during a Command-drag | works if the two styles differ on screen in any state the owner can reach in IceBar mode; else removed |
| V2 | Hide app menus when showing | reachable only outside IceBar mode (the guard in `MenuBarManager`) | follows U1: removed if IceBar mode is the only mode |
| V3 | Secondary context menu | right-click empty bar, on and off; Control-click | on: Ice's small menu in the window list; off: none. Its two entries open the appearance editor and the settings |
| V4 | Show on hover delay | G4 at 0 s and at 1 s | time to shown differs by 1 s ± 0.3 |
| V5 | Show all sections when Command-dragging | on and off, during D1's drag | works if the two differ on screen or in what the drag can do; else removed |
| U1 | "Use Ice Bar" off | one launch with it off, the member left of the divider, the section toggled | if the member is still drawn (as 09-25: 10 of 10), off is a mode in which Ice hides nothing: the toggle, H4 and V2 are removed and IceBar mode is the mode on 27 |
| D1 | Hold Command to get hidden items back | pointer on the bar, Command held 3 s | while held: `length null`, the member's frame on the bar; within 3 s of release: hidden again, roster unchanged. Then held again and the member Command-dragged right of the divider: roster empty, the item on the bar |
| D2 | A quick drag does not lose an item | the helper Command-dragged from right of the divider to left of it within 300 ms, started just after a sample | within 5 s: roster holds it, a cell for it in the IceBar, never "on no list" |
| K1-K3 | Known dead | always-hidden section (T2d), temporarily-shown delay (temporary showing refused on 27), search panel click | not re-proved live except H3's one click: removed |

A case is run up to three times; `works` needs every run to pass, a flaky case is
reported as such and treated as not working unless the cause is the harness's (shown
by the evidence), in which case the harness is repaired and the case run again.

## 4. The rule for keeping and removing

- **Kept**: passed live. **Removed on macOS 27**: failed live, or known dead (K), or
  its only reachable state on 27 does nothing (V1, V2, V5, U1 by their rows).
- **Repaired, not removed**: a kept setting with a defect found by its own case (G3's
  click on another app's item) is repaired when the repair is small and inside the
  setting's own code path; otherwise the setting is removed and the defect recorded.
- Removed means all three: not shown in the settings window; no menu entry or hotkey
  reaches it; a value stored earlier has no effect (the model reads the setting
  through one rule and, on 27, gets the off/default value). Stored values are left in
  the defaults domain untouched.
- The decision table lives in IceCore as `SettingsOffer` (pure): `isOffered(_:isMacOS27:)`
  for every setting and hotkey action, and `effective(_:stored:isMacOS27:)` for those
  whose stored value must be neutralised. The panes, `HotkeysSettings`, the menus and
  the models ask it. Its rows are filled from the cases' results; unit tests state
  every row for 27 and "everything offered, stored value kept" before 27.

## 5. Tasks (each the smallest checkable unit)

| # | Task | DoD |
|---|---|---|
| T1 | `settingsdrive.swift` + `selftest` | selftest passes; `items`, `windows`, `shot` run read-only on this Mac; a `move` and one `click` on empty bar space post and restore the cursor |
| T2 | `run-settings.sh`, `test-settings.sh` | `test-settings.sh` green against stubs (written first, red first); one live smoke case (G3 on) ends `pass` or `fail` with evidence, the Mac afterwards as before (release prefs identical, lab domain empty, no helper, no Ice) |
| T3 | Run every case of section 3 on a build of this branch | a `<case>.json` for each; a results table in the plan's appendix; no `notRun` left, or each one explained |
| T4 | `SettingsOffer` in IceCore, tests first | IceCore tests green, the new file covered ≥ 80 % |
| T5 | The panes, hotkeys, menus and models ask `SettingsOffer`; known-dead and failed settings gone on 27; defects of kept settings repaired (tests first where the logic is pure) | app builds; `docs/plans/checks/check-settings.sh` (grep assertions: no removed control is built outside an `isOffered` guard) green |
| T6 | The cut build, live: `axdump` of every pane, Ice's menu and the secondary menu | exactly the kept controls are present, none of the removed; the removed hotkeys, stored, do not fire; a stored `EnableAlwaysHiddenSection = true` adds no divider; every kept case of section 3 passes again on this build (the regression pass) |
| T7 | Version 1.0 (`MARKETING_VERSION` of the app's two configurations; the build number stays) | About shows 1.0 in the cut build (`axdump`) |
| T8 | `STATUS.md`: one section, every row MEASURED / INFERRED with build and date; memory `lab-round-six-pending` updated | written |

Order: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8. Nothing parallel.

## 6. Tests

Unit: `SettingsOffer` (IceCore, Swift Testing), any pure rule a repair adds;
`settingsdrive selftest`; `test-settings.sh` for the runner. Integration: the app
build; `check-settings.sh`. End to end: T3 and T6 on the live bar. Full run at the
end: IceCore, MenuBarDiscovery, `test_lab_tool.py`, `test_s5_tool.py`, `test-lab.sh`,
`test-s5.sh`, `test-settings.sh`, the app build, `check-a3a4.sh`.
The probes package's full `swift test` (over an hour) is not run: this pass touches
none of its sources.

## 7. What it touches, risks, the way back

Touches: `Ice/Settings/**`, `Ice/Hotkeys/HotkeyAction.swift`, `ControlItem.swift`
(menu entries, always-hidden), `HIDEventManager.swift` (only if G3/G4 need the
repair), `Packages/IceCore` (one new file + tests), `Ice.xcodeproj` (version),
probes (three new files), docs. Not touched: `MenuBarCapture`, the detector files,
the hiding machine.

| Risk | Answer |
|---|---|
| Synthetic input lands on the owner's work | the idle guard before every event; abort on hardware input; cases are seconds long; nothing of the owner's is ever a press or drag target |
| A lab copy changes the release Ice's settings or leaves a login item | own identity by path; prefs compared; G1 always ends off and the teardown checks for a leftover |
| The spacing keys leak into the owner's apps | written only for the seconds two helpers take to start, deleted in a trap; an app the owner starts in that window would read them until its next launch: the window is under 10 s and the run notes the time |
| A case passes for the wrong reason (the report says shown, nothing drawn) | "shown" needs the window list too; appearance needs pixels |
| A removed setting's stored value still acts | `effective` + T6's stored-value checks |
| The MenuBarAgent store changes under other items (seen in every lab run) | diffed before and after, reported; no key added or removed is the bar |

Back: every step is a `wip/` checkpoint commit; the cut is one commit that reverts
alone. The harness changes nothing persistent outside its evidence directory.

## 8. Acceptance

1. Every setting, hotkey and menu entry of section 3 has a measured result or an
   explained reason for none.
2. On the cut build nothing removed is shown, reachable or effective (T6).
3. Every kept setting passes its case on the cut build.
4. The Mac after the last run: no Ice, no helper, release Ice's prefs identical, no
   lab domain, no lab login item, no spacing key.
5. All tests of section 6 green; version 1.0.

## 9. Amendments after the plan review (these override the sections above)

1. **More cases.** G0: "Show Ice icon" off (no icon on the bar; the hotkey and the
   empty-bar click still open the IceBar) and on. G0b: a custom icon stored before
   launch, with and without "dynamic appearance" (the icon's pixels on the bar). A5:
   dynamic appearance (separate light and dark values: the one matching the system's
   current appearance is drawn). A6: inset shape. A7: border colour and width. A8:
   the editor's reset. A control of the appearance editor with no passing case is
   removed like any other.
2. **Removed means inert at the model, not at the view.** On macOS 27 each settings
   model takes `SettingsOffer.effective` when it loads and whenever a value is
   published; `HotkeysSettings` registers no hotkey for an action that is not
   offered, and `HotkeyAction.perform` returns for one. Views, menus and
   `ControlItem` ask the same rule.
3. **The harness never trusts "empty".** A press on empty bar space needs a positive
   AX hit test at the point: the element is the menu bar owner's and no status item
   (of any process, system items included) contains the point; an unreadable or
   ambiguous answer aborts the case.
4. **Each removed setting gets a live check on the cut build** (T6), with its old
   value and hotkey stored before launch: nothing registered, no state change, no
   visible effect (no extra divider, no panel, no relaunch, no menu entry).
5. **G3's repair has one source of truth**: a pure IceCore rule over the last
   discovery set (item frames, system element frames, completeness) answers "is the
   point on an item"; `isMouseInsideMenuBarItem` asks it on 27. No complete set: the
   answer is "on an item", so click, hover, scroll-open and the secondary menu do
   nothing rather than guess.
6. **Item spacing is removed on macOS 27.** Its real path cannot be run without
   quitting the owner's apps, and a keep cannot rest on a different mechanism. Only
   a read-only count of the pids `applyOffset` would relaunch is recorded. (Replaces
   G7.)
7. **G6, focused app**: the front app is recorded before the IceBar is opened; one
   deliberate change of front app closes it; with no change it stays for 10 s.
8. **D2's evidence is the order, read from the report as it is**: for each of ten
   quick drags at random phase, a `length null` (the retire) follows the drag's start
   within 1.2 s although the drag ended before the next sample, then the roster gains
   the item; from 3 s after the drop no snapshot has the item off the bar and absent
   from the roster. No new report event.
9. **Two more cases on the cut build**: every kept setting at a non-default value at
   once; and persistence (values set by AX presses in the settings window, Ice quit
   and started again: still stored, still effective).
10. **Order**: T7 (version 1.0) comes before T6, so the accepted run is of the 1.0
    build. `SettingsOffer`'s tests enumerate every setting and hotkey action
    (`CaseIterable`), so none is without a decision.

## Appendix A: the plan review (Codex gpt-5.6-terra, two rounds, 2026-11-12)

| # | Codex | Ruling |
|---|---|---|
| 1 | controls with no case (icon toggle, custom icon, dynamic appearance, inset, border colour/width, reset) | adopted (9.1) |
| 2 | hiding a control leaves stored values and hotkeys live | adopted (9.2) |
| 3 | "empty menu bar" unsafe as a press target on 27 | adopted (9.3) |
| 4 | a grep cannot prove a removed setting inert | adopted (9.4); the grep check stays as a cheap guard |
| 5 | the hit-test repair has no source of truth | adopted with the source defined (9.5) |
| 6 | machine-readable decision table checked in | rejected: evidence stays outside the repo by project rule; the appendix table (case, run, build, verdict, rule) and exhaustive `SettingsOffer` tests make the same tie. Codex conceded in round 2 |
| 7 | item spacing kept on a different mechanism | adopted: removed (9.6) |
| 8 | focused-app rehide can pass falsely | adopted (9.7) |
| 9 | wall-clock drag timing is not evidence of the race | Codex maintained in round 2 (end states alone cannot tell immediate from delayed repair; and corrected my arithmetic: all ten missing a tick is 0.7^10). Adopted in substance without new instrumentation: the existing `length` events give the order (9.8) |
| 10 | interactions and persistence untested | adopted smaller: one combination case, one persistence case; a pairwise matrix is out of proportion for a one-owner fork (9.9) |
| 11 | version set before the evidence is stable | adopted (9.10) |
