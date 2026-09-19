# Safe-width measurements — results

Machine: macOS 27.0 (26A428), one built-in 1728x1117 pt display, notch at
x ∈ [771.5, 956.5], 15 user menu bar items. Protocol:
`docs/plans/2026-09-18-safe-width.md`.

Raw evidence (JSONL, captures, manifests) lives outside the repository in
`~/IceReverse-evidence/<run id>/`; the strips show the user's installed apps, so
only these tables are committed. Every claim is tagged MEASURED or INFERRED and
cites its run.

## Actors

`T` (target, 12 pt) · `S` (spacer, this process) · `P` (protected proxy, 12 pt),
left to right, all ours; then the user's items, which are only ever read.
`F` is our frontmost app, whose menu width is the config.

**Every run that contributes a number to the O1, scan and M tables rests `S` at
Ice's own chevron rest** (`variableLength` plus the chevron image; AppKit reports
a 32 pt window, in all 2 942 rest samples of the eight `ice` runs): their
`rest.mode` records say `ice`, with no fallback. (The
instrument run below did not — it rested at a fixed 12 pt — and O0 rebuilt the
original topology, which has no rest mode at all.) Ice's rest fits only because
`T` and `P` are 12 pt wide. With 16 pt helpers — and again whenever the microphone
pill was in the bar, which costs ≈ 37 pt — Ice's rest did **not** fit: `T` came up
already overflowed and the runs of 19:43–19:51 fell back to a fixed 12 pt rest
(`rest.mode` `fixed`, e.g. `20260918-194747-c-mid`). None of those runs
contributes a number here. So the room right of the notch, ≈ 115 pt, holds Ice's
own rest plus two 12 pt items and no more.

## Instrument (`20260918-195652-c-mid`)

| measurement | value |
|---|---|
| one sample (capture + AX + all detections) | median 78 ms, max 124 ms ≈ 12 Hz |
| return to rest from an 8 pt expansion | 1.27 s to a clean, settled rest (the guard did not fire: a guard-triggered restore has never been timed) |
| null control, 15 s at rest | 47 clean, 0 suspect, 0 harm |
| frontmost during the run | `com.icespike4.front` in 73 / 73 samples |
| teardown | every static user item back at its baseline position |
| rest mode | fixed 12 pt: this run still used 16 pt helpers |

## O0 — the "order dependence" does not reproduce (`20260918-195745-o0`)

The original topology rebuilt (one process: a spacer created at length 1, then
three 24 pt probes), F-mid, jump 1 → 600 against step 1 → 300 → 600, N = 3 each,
captures from 0.25 s to 8 s.

| path | probes visible in pixels at 600 pt | AX for the same instant |
|---|---|---|
| jump | none, ~0.2 s → 8 s, all 3 repeats | probe0 alone at x=1024, probe1+probe2 stacked at 967 |
| step | none, ~0.1 s → 8 s, all 3 repeats | all three stacked at 1024 |

**MEASURED:** the pixels are identical on both paths. **MEASURED:** AX describes
that one visual state two different ways depending on the path, and gives a
probe a distinct on-bar position the screen does not show; during the jump one
capture caught AX reporting the spacer still at its old x with its new width
(x=1055, w=602), which cannot be true, corrected ≈ 0.1 s later.

Pre-registered outcome row 4 — **pixels agree, AX disagrees with pixels: stale AX
reproduced.** Protocol from here: pixels decide, AX explains.

## O1 — paths agree at the transitions (`20260918-203137-o1`)

F-mid, widths on both sides of each transition, three paths, N = 3 planned. The
microphone pill arrived during the third repeat and voided it from 632 pt up, so
632–872 have N = 2 per path, and one 32 pt step was voided the same way. 872's
step path has N = 1: in the first repeat the full reset before it failed its
rest check (`T` marker absent) and the step was skipped. Every valid repeat
agrees with the others.

| length | jump (full reset) | jump (light reset) | step (Δ=64) |
|---|---|---|---|
| 16 | visible | visible | visible |
| 32 | overflowed | overflowed | overflowed |
| 632 | overflowed | overflowed | overflowed |
| 680 | invisible, overflow unconfirmed | same | same |
| 856 / 872 | visible | visible | visible |

**MEASURED:** no path dependence in pixels, and a light reset (S back to rest,
verified) gives the same state as a full reset. Stage M therefore uses light
resets and reports one set of numbers per path without extra labelling.

## Scans and M — the quantities (all three configs)

Configs by measured menu right edge: **narrow** 72 pt (2 menus), **mid** 440 pt
(8 menus), **wide** 758 pt (13 menus, ending just left of the notch).

| quantity | narrow | mid | wide |
|---|---|---|---|
| `W_hide` (target overflows) — **for a 32 pt rest**; a 28 pt rest gives (8, 16] | (16, 20] | (16, 20] | (16, 20] |
| target leaves the fold: not drawn, no chevron — pixels, every path | (652, 656] | (652, 656] | (652, 656] |
| `W_selfov` (S stops taking room) — **AX-derived, jump path only** | (652, 656] | (652, 656] | (652, 656] |
| `W_edge` (S's AX left edge stops moving) — staircases | (648, 652] | (648, 652] | (648, 652] |
| `W_top` (target visible again) — staircases, up / down | (836, 852] / (848, 864] | same | same |
| `W_sat` (AppKit width stops growing at 5016) | (2000, 5000] | (2000, 5000] | (2000, 5000] |
| `W_harm` (anything right of S stops being visible) | **not observed at any tested length up to 10 000** | same | same |

`W_hide` and `W_selfov` are bisected on the jump path to ±4 pt and identical in
all three repeats of every config (runs `20260918-204150-m-mid`, `…-m-narrow`,
`…-m-wide`). The staircase rows come from the same runs' up and down legs (4 pt
steps near a transition, 16 pt elsewhere): 17 legs, 16 of them complete, and
every one agrees on each transition it reached. `W_sat` and `W_harm` are the scan
grid's brackets (`…-scan-<config>`), whose view of `W_top` is the coarser
(640, 864].

`W_top` has no jump bisection. The bisection's rule needs an overflowed sample
below the transition, and the length it tried, 752, was in the state between:
the target not drawn and the chevron gone, neither overflowed nor visible — the
state the protocol calls "invisible, overflow unconfirmed". The staircases
bracket it directly instead. Up and down agree with one threshold in (848, 852];
the 16 pt steps there cannot say whether it has any hysteresis. The state between
runs from 656 to 836 going up (848 coming down) — not "≈ 672 to ≈ 832", which was
the scan grid's view of it.

`W_selfov` has no pixel signal of its own: an expanded spacer draws nothing
(Ice's does the same), so "is S still taking room" reads S's AX x against the x
it rests at. On the jump path S's AX x reads 1012 from 656 on — 8 pt right of the
1004 it rests at, and 16 pt right of the 996 it holds while overflowed.
On the staircases it never is: S's AX left edge moves left with the length, reaches
368 at 652, and stays at 368 above it — so the staircases report `W_edge`, and
`W_selfov` as not observed. That is the O0 finding again, the same pixels with two
AX stories, one per path. What does not depend on the path is the pixel
transition in the same place: at 652 the target is overflowed, at 656 it is not
drawn and the chevron is gone, on every path, in every config and repeat.
**INFERRED:** the three readings are one event — the spacer running out of room
to take — seen three ways. No AX reading carries the headline: the pixel-based
bounds (`W_top`, and the fold transition at 652) put the interval's top at 640 on
the scan grid and at 652 on the staircases.

`W_edge` does not show on the scan grid at all: every scan length is a jump, and
on a jump S's AX x is back at rest above 652, so no plateau can appear.

### Verdict

| config | jump | up | down | toggle at 300 pt | legs |
|---|---|---|---|---|---|
| narrow | holds | holds | holds | 5 / 5 | up rep 1 cut short at 836 pt (F lost the front): 3 jump / 3 up (one partial) / **2** down |
| mid | holds | holds | holds | 5 / 5 | 3 / 3 / 3 complete |
| wide | holds | holds | holds | 5 / 5 | 3 / 3 / 3 complete |

A jump leg is 5 probes (the bisection steps); an up or down leg is 97.

narrow's partial up leg stopped at 836 pt — above `W_hide` and above `W_selfov`,
below `W_top` — so it contributes a hide bracket and no top bracket; its verdict
rests on the other two repeats for `W_top`.

**MEASURED:** `max W_hide upper end (20) < min bound lower end (640)` in every
config and on every path, a margin of ≈ 620 pt against the scan grid (the M
runs' own headlines: 632 on the jump path, 628 on each staircase, in every
config). The safe interval on this
machine is therefore about **[20, 640] pt**, identical in all three configs, so a
single constant serves all of them — 300 pt was toggled five times per config
with the same items and hid the target every time.

The interval's lower end is **not** a machine constant: it tracks the spacer's
own rest width. The 28 pt rest of the earlier runs hides at (8, 16] instead of
(16, 20]. Since Ice rests its control item at 32 pt everywhere (2 942 samples),
the lower end for Ice is ≈ 16 and no plausible constant falls below it; but the
number 20 belongs to this topology, not to the machine.

Scope: grid-scoped. Lengths between grid points were not observed, and `W_harm`
"not observed" means exactly that — no harm was seen at the lengths tested, and
none was ever driven for on purpose.

### Attribution of the overflow (each scan run)

The three scans behind the table — `20260918-202525-scan-mid`,
`…-205131-scan-narrow`, `…-210852-scan-wide` — all had the `«` template
**rejected** by its validation cycles, so the AX-plus-ink rule was the detector
for every sample in them. (Three earlier mid scans, superseded by the one above,
used 16 pt helpers or had the template validated mid-run; none contributes a
number here.)

At the first overflowed length, quitting `T` alone made the chevron disappear
while S stayed drawn, in all three configs — so the chevron is `T`'s overflow,
not S's. The cut `«` template validated in the first scan but was rejected in
later ones: the bar is translucent, so the same glyph over another part of the
wallpaper is a different crop. The operative rule is therefore "a new
MenuBarAgent item in AX **and** ink drawn in its span".

### What this says about Ice's own constant

At 10 000 pt — Ice's `Lengths.expanded` — the target is **visible** in every
config: 10 000 is far above `W_top`, so the spacer gives the room back instead of
hiding anything (MEASURED, all three scans, for our spacer with a 12 pt target).
In the mid scan that sample came after the run should already have stopped (see
Safety); it settled with the guard clean and matches the other two configs.

**INFERRED** for Ice itself: its control item is the same kind of object — an
`NSStatusItem` resting the same way and expanded to the same length, with the
hidden items to its left — but Ice was not run, and the items it hides are the
user's, not 12 pt helpers. So: on this machine a spacer at Ice's constant hides
nothing, and one inside [20, 640] does.

## Safety

Across all 18 runs the guard never reached `restore`, the deadman never fired,
and no `com.icespike4.*` process outlived its run. Three qualifications, all
found by review against the raw evidence rather than by the runs themselves:

**Two `stop` decisions, in the reported mid scan** (`20260918-202525-scan-mid`,
captures `00023-guard.png` and `00132-guard.png`). The captures show the menu bar
mid-slide during a Space switch — the user's items on the left half, the Apple
menu and F's menus on the right — so every template missed at once: 15 × itemLost
plus the clock unverifiable, with the whole strip displaced. The guard's job
there is to refuse to say the bar is fine, and it did. Not harm, and not caused
by the spacer; caused by macOS switching Spaces under the run.

**Neither stop latched.** The first happened on a return to rest whose outcome
the stage discarded. The second happened inside the 1088 pt probe, and the build
that ran did not stop the scan on it either. Between the two the run expanded
54 times; after the second, 6 more times — 1120, 1152, 1184, 2000, 5000 and
10 000 pt. Every one of those later expansions started from a rest check that
passed and settled with the guard clean, which is why nothing came of it, but
the protocol said to stop. Fixed after the fact, twice over: first every return
to rest went through the probe latch; then review found the latch still had
gaps — the scan's attribution and template validation expanded without it, a
light reset could latch a stop and the jump would expand anyway, and O0 ignored
how its rests ended. Now every expansion goes through one call that refuses once
the guard has stopped or fired and latches whatever the guard says, the jump
re-checks after its reset, and O0 ends on any rest that does not settle.

**Teardown was clean in 15 of 18 runs.** Three flagged displaced items:
`20260918-194520-c-mid` (two `MenuBarAgent` items — the microphone pill arrived
mid-run), `…-195745-o0` (the clock, whose text changed), `…-200903-scan-mid`
(the Teams badge). All three are appearance or arrival events in place, none is
an item pushed out of the bar.

**The guard's own pill rule was inert during these runs, and stayed inert
through two attempts to wire it.** "The pill is in AX but not in pixels,
therefore something pushed it out" could not fire, because the live code passed
no pill reading into the guard; the pill was instead handled by waiting for it
to go and voiding trials where it appeared. The first wiring would have mistaken
the overflow chevron for the pill. The second told them apart by requiring the
pill's own orange in its own span — which a pill pushed out of the bar never
shows, so the rule still could not fire. Now the chevron is recognised by its AX
width (17.5 pt in every one of ≈ 8 900 readings) and any other MenuBarAgent item
standing where the pill does is the pill, drawn if its orange is there and
hidden if not; a hidden pill no longer voids the trial, it goes to the guard.
**Not exercised live:** no run has used this code, and neither the pill's AX
width nor where AX puts a pill that has been pushed out has ever been recorded.
What protected the bar during the runs above was the user-item templates, not
this rule.

## Not measured here

- Only this display, this set of 15 user items, and this afternoon's wallpapers.
- The frontmost menu width made **no** difference to any transition (the notch,
  not the app menus, bounds the room on this machine). Whether the room formula
  depends on the number of user items was not tested — the user's items were
  never changed.
- The instrument as it stands after review round 4: the latch and pill fixes
  are unit-tested in `SafeWidthCore` and built, but `swctl` has no tests and no
  run has been made since.
- Ice's own rest width (no room for it here), the no-divider control-item style,
  two spacers at once, app switching while the spacer is expanded, external
  displays, and lengths between grid points.
