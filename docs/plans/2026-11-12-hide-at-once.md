# Hide at once: Ice stops checking its own hide

2026-11-12 · branch `wip/s5-owner-acceptance` · the owner's ruling the same day, after
the free-use run `20261112-181149-free`; debated with Codex (one round, agreed on the
cause and on one fix-and-look cycle). Labels: MEASURED, INFERRED, TBD.

## The owner's requirement

"Dropping an item left of Ice's divider is the moment it is done": hidden, and
clickable in the IceBar, at once. Three seconds is already long.

## What was wrong (STATUS, "Free use on the owner's bar")

| # | Fact | Grade |
|---|---|---|
| W1 | Before it rests, the machine retires the length whenever the pointer is on the menu bar (`isInteracting`), and starts over | MEASURED (run `-181149-free`: 4 hides undone within 2 to 5 s) |
| W2 | It hides only after a baseline with the section shown, a 20 s settle and, on a bar where no baseline finds a reference, three more such cycles 30 s apart: about 3 minutes | MEASURED (run `20261112-173803`: first lasting rest 187 s after start) |
| W3 | On the owner's bar the checks can never succeed (it overflows at rest; the frozen baseline gives no template with a fold present) | MEASURED (probe, 2026-11-12) |
| W4 | A cache pass, which is what tells Ice an item is now left of the divider, runs every 5 s | MEASURED (code: `MenuBarItemManager.configureCancellables`) |

## Design

D1 `IceBarHidingParameters.verifies`. With it off (`.unverified`, what Ice now runs
with): on the first sample where the divider has decided the sections and a member is
left of it, the machine sets the best-effort length (736, or the last verified one) and
rests, IceBar offered, state "hiding requested, not verified" with every member
unchecked (the parent plan's O1 and D-c, unchanged). No baseline, no observation, no
quiet period, no interval between hides, no regard for the pointer; a soft layout
change (front app, menu edge, Space) owes nothing. Kept: a Command-drag and a failed
precondition retire the length; a structural change (items or members) retires it and
hides again.

D2 With it on (`.standard`; `-IceLabVerify YES`, which `run-lab.sh` now passes): the
machine as it was, so the lab matrix means what it meant.

D3 `IceBarHidingCoordinator.rereadSoon`: when the length becomes standard or a drag
ends, one cache pass is run as soon as the divider has settled (1 s, plus 0.15 s) and
the machine sampled right after it, so a drop is hidden in about that time and not at
the next 5 s pass.

D4 Taking an item out (the owner, 2026-11-12: "how do I get it out?"). The owner is
arranging, and Ice gives the real divider and the hidden items back, during a
Command-drag as before and now also while Command is held with the pointer on the menu
bar (`IceBarArrangingRule`): hold Command, the members are drawn, drag one right of the
divider, let go. A change of the modifier keys samples the machine at once. Arranging
several items at once in the layout pane, as Ice does before macOS 27, needs Ice to
move another app's item itself: refused on macOS 27 in this fork (a synthetic drag
moved a helper 3 of 4 times, 2026-09; never tried on a real item). To be measured
before anything is built on it.

Not done: any capture-based check in this mode; changing the frozen detector; changing
how membership is decided (still: left of the divider at standard length).

## Limits, said to the owner

- Ice cannot say "verified" in this mode, anywhere; the pane says "not verified".
- Every change of members shows the hidden items on the bar for about a second (the
  divider must stand at standard length to decide who is left of it).
- 736 pt is a best-effort length: measured to hide on the owner's bar by eye
  (run `20261112-173803`), not proven for another display or arrangement.

## Tests and gate

`IceBarHidingMachineTests`, "Hiding at once": hides on the first sample; says
unverified; the pointer neither delays nor undoes; drag and drop; a member added;
soft changes owe nothing; waits for the boundary; preconditions block; the standard
parameters still verify. App build. Codex review. Then one measured run on the owner's
bar with a sacrificial helper (time from the helper's start to the length applied),
and the owner's own look. If it does not rest within seconds under ordinary mouse use,
the project stops (the owner, 2026-11-12).
