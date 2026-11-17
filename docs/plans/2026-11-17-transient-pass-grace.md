# Transient pass grace: one bad pass no longer shows the hidden items

2026-11-17 · branch `wip/transient-pass-grace` (from `main` ea1eaa6) · the owner's
report the same day (built-in display only, daily Ice 1.1.5). Labels: MEASURED,
INFERRED, TBD.

## The owner's report

"With no external display connected, the hidden items came out again" (screenshot
09:50), and once more at about 11:25.

## What is wrong

Evidence: `~/IceReverse-evidence/20261117-builtin-shown/icebar-stream.log`
(`log stream`, category `IceBar*`, 09:53 to 11:26; `.info` is not persisted, so the
09:50 event itself was not recorded).

| # | Fact | Grade |
|---|---|---|
| F1 | Nine retires in 93 min, all `display 1->1` | MEASURED |
| F2 | Four (10:20:22, 10:21:37, 10:32:17, 11:25:52) are one bad pass: items 9-10 -> 5-6 (-6), `blocked(iconUnreadable,ownReadNotOk)`, the next pass about 3 s later is normal again | MEASURED |
| F3 | Three (10:50:34, 10:52:17, 11:25:37) are a pass with a process that did not answer: `blocked(discoveryIncomplete,ownReadNotOk)`; 11:25:37 is an app on the owner's bar quitting (named in the evidence folder) (members 6 -> 5), relaunched 11:25:50 (`ps` start time) | MEASURED |
| F4 | One (10:03:54) is a complete pass with one item added that is not read right of the boundary: structural `itemsChanged`, as designed (plan 2026-11-13-flash-on-item-change, limits) | MEASURED |
| F5 | One (10:42:26) is the hold before the IceBar opens, as designed | MEASURED |
| F6 | Every failed precondition and every structural change retires the length at once (`IceBarHidingMachine.handle`); a pass runs about every 5 s, so a single bad pass shows the items until the next one | MEASURED (code) |

## Design (converged with Codex in four rounds, 2026-11-17)

G1 An *unreadable pass*: hide-at-once (`transientGrace` 5 s in `.unverified`, 0 in
`.standard`), the machine resting at a length, not dragging or held, the pass
blocked and every reason one of `iceIconNotRightOfDivider(.iconUnreadable)`,
`iceIconNotRightOfDivider(.dividerUnusable)`, `ownReadNotOk` (so the pass was
complete; `IceBarHidingMachine.isUnreadable`).

G2 Such a pass is set aside whole: it is not the new reference and its items are not
compared with the old ones (a pass that cannot read Ice's own icon cannot tell a
real change from a misread; F2's four are all structural against the reference).
The rest keeps its length and records `suspect` (a token); the first such pass asks
for a pass at once (`.reread`) and arms the grace (`.armGrace(token:after:)`).

G3 The next readable sample ends the grace and is handled as today against the
reference from before it: soft keeps the length, structural or any other block
retires. A drag or a hold retires at once.

G4 The grace runs out on the coordinator's own clock (`Task.sleep`, then
`.graceExpired(token:)`), not on the next sample: a stalled read must not stretch
it. A current token blocks as today; an old one does nothing.

G5 The state says `requestedNotVerified(.transientRead)`, never `blocked`. Log lines
`IceBar grace: began, would block: ...`, `recovered / expired / ended by a retire
after X s` measure what the grace changed on the owner's bar.

Not changed (known limits, the debate's verdict): `discoveryIncomplete` still retires
at once (F3: telling a process that only failed to answer from a new one needs a
process identity snapshot; not this plan); F4 and a returning member retire as
before; the verifying mode is unchanged.

Exposure accepted: an item that really arrived left of the divider during a grace
stays unlisted until the next readable pass (which retires) or the grace's end,
at most 5 s, the same order as today's pass interval.

Codex's worry: the order inside `handle` (set aside before the reference is
replaced). Pinned by `referenceIsNotTheUnreadablePass`.

## Verification

- IceCore: 905 tests, `IceBarHidingMachineGraceTests` (16); line coverage of the
  changed files 97.8-100 %.
- Debug build of `Ice`.
- Live: the daily Ice, the `IceBar grace:` lines against the `IceBar retire:` lines
  of 2026-11-17's stream.

## Released

Merged into `main` and released as v1.1.6 on 2026-11-17; the signed Release build is
the daily Ice (the 1.1.5 it replaced and the settings export are in
`~/Ice-release-archive/`, the 34 settings unchanged).
