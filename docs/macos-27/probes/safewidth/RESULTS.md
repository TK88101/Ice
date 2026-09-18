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

**Every run reported below rests `S` at Ice's own chevron rest**
(`variableLength` plus the chevron image; AppKit reports 24–32 pt): their
`rest.mode` records say `ice`, with no fallback. That is only true because `T`
and `P` are 12 pt wide. With 16 pt helpers — and again whenever the microphone
pill was in the bar, which costs ≈ 37 pt — Ice's rest did **not** fit: `T` came up
already overflowed and the runs of 19:43–19:51 fell back to a fixed 12 pt rest
(`rest.mode` `fixed`, e.g. `20260918-194747-c-mid`). None of those runs
contributes a number here. So the room right of the notch, ≈ 115 pt, holds Ice's
own rest plus two 12 pt items and no more.

## Instrument (`20260918-195652-c-mid`)

| measurement | value |
|---|---|
| one sample (capture + AX + all detections) | median 78 ms, max 124 ms ≈ 12 Hz |
| guard restore from an expansion | 1.27 s to a clean, settled rest |
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

F-mid, widths on both sides of each transition, three paths, N = 3.

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
| `W_hide` (target overflows) | (16, 20] | (16, 20] | (16, 20] |
| `W_selfov` (S stops taking room) — **AX-derived** | (652, 656] | (652, 656] | (652, 656] |
| `W_top` (target visible again) | (640, 864] | (640, 864] | (640, 864] |
| `W_sat` (AppKit width stops growing at 5016) | (2000, 5000] | (2000, 5000] | (2000, 5000] |
| `W_edge` (left edge plateaus) | (648, 652] | (648, 652] | (648, 652] |
| `W_harm` (anything right of S stops being visible) | **not observed at any tested length up to 10 000** | same | same |

`W_hide` and `W_selfov` are bisected to ±4 pt and identical in all three repeats
of every config (runs `20260918-204150-m-mid`, `…-m-narrow`, `…-m-wide`); the
others are the scan grid's brackets (`…-scan-<config>`).

`W_top` cannot be bisected: between ≈ 672 and ≈ 832 the target is invisible while
the chevron is **gone**, so it is neither overflowed nor visible — the state the
protocol calls "invisible, overflow unconfirmed". The bracket stays as the grid
gives it.

`W_selfov` is the one quantity here with no pixel signal behind it: an expanded
spacer draws nothing (Ice's does the same), so "is S still taking room" reads S's
AX x against the x it rests at. AX is the signal O0 showed lying during
transitions; these readings are taken after the pixels settled, and the bracket
repeated identically in every config and repeat, but it is AX-derived and the
headline margin does not depend on it — `W_top`, which is pixel-based, bounds the
interval at 640 too.

`W_edge` is not visible on the scan grid at all — S's left edge does not plateau
there, it simply stops moving left and the item returns to its rest x while its
window keeps growing to the right. The M staircases, whose steps are fine enough,
bracket it at (648, 652] in every config and both directions: the same event as
`W_selfov`, seen through `spacerLeft` instead of through S's rest x.

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
config and on every path, a margin of ≈ 620 pt. The safe interval on this
machine is therefore about **[20, 640] pt**, identical in all three configs, so a
single constant serves all of them — 300 pt was toggled five times per config
with the same items and hid the target every time.

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
hiding anything (MEASURED, all three scans). Ice's constant does not hide on this
machine; a value inside [20, 640] does.

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

**The first of those two stops was swallowed.** It happened on a return-to-rest
whose outcome the stage discarded, so nothing latched, and the run went on to 60
more expansions, up to 10 000 pt, before the second stop landed inside a probe
that did latch. Fixed after the fact: every return to rest now goes through the
same latch as a probe, and no stage expands after a stop.

**Teardown was clean in 15 of 18 runs.** Three flagged displaced items:
`20260918-194520-c-mid` (two `MenuBarAgent` items — the microphone pill arrived
mid-run), `…-195745-o0` (the clock, whose text changed), `…-200903-scan-mid`
(the Teams badge). All three are appearance or arrival events in place, none is
an item pushed out of the bar.

**The guard's own pill rule was inert during these runs.** "The pill is in AX but
not in pixels, therefore something pushed it out" could not fire, because the
live code passed no pill reading into the guard; the pill was instead handled by
waiting for it to go and voiding trials where it appeared. It is wired in now —
and, on review, the first wiring would have confused the overflow chevron for the
pill, so the pill is now identified by its own orange in its own span. What
protected the bar during the runs above was the user-item templates, not this
rule.

## Not measured here

- Only this display, this set of 15 user items, and this afternoon's wallpapers.
- The frontmost menu width made **no** difference to any transition (the notch,
  not the app menus, bounds the room on this machine). Whether the room formula
  depends on the number of user items was not tested — the user's items were
  never changed.
- Ice's own rest width (no room for it here), the no-divider control-item style,
  two spacers at once, app switching while the spacer is expanded, external
  displays, and lengths between grid points.
