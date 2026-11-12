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
