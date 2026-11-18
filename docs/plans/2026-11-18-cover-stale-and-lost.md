# The cover: a background that is wrong stays wrong, and the cover stays off after Mission Control

2026-11-18 · branch `wip/cover-stale-and-lost` (from `main` bcffb4c, v1.1.7) · follows
plan 2026-11-15-cover. Labels: MEASURED, INFERRED, TBD. macOS 27.2.1 (26B131).

## What is wrong

Evidence: `~/IceReverse-evidence/20261118-sidecar-dark/` (the owner's screenshot
`owner-182317.png`, `now*-d2.png`, `probe.swift`, `agent.swift`, `watch.swift` and
`watch.log`, `ice-stream.log`, `ice-sample.txt`; Dock lines from `log show`).

| # | Fact | Grade |
|---|---|---|
| M1 | 18:23:17, Sidecar bar (display 7, 1314 pt, no notch): three cover panels over the three members, each showing the wallpaper's own pattern at 0.50 of the bar's brightness beside it (panel `(75,51,28)` / `(57,34,15)`, bar `(150,101,56)` / `(116,70,30)`) | MEASURED (owner's screenshot, pixels) |
| M2 | A panel is shown only when the strip pair of its capture passed `CoverPixels.isTransparent` (20 % of item-free columns equal within 2). So when that strip was taken, the bar on screen was at 0.50 too: the capture was right for its moment, and the moment passed | INFERRED from the code |
| M3 | Nothing asked for another capture afterwards. A background is taken again only on: the key (Space id of that display, light/dark, wallpaper store date), the notifications of D2 of the cover plan, a change of the windows under the strip, 30 minutes | MEASURED (code) |
| M4 | What dimmed the desktop to 0.50, and when the capture was taken: unknown. The Dock logged no Mission Control and no Space swap on display 7 between 15:00 and 18:23:17; Ice's `cover:` lines are `info` and were gone from the log within minutes | TBD |
| M5 | At 18:35 a capture of the same strip by `probe` reads full brightness (`below` mean 139.9, 83.0, 32.9), and the panels then show the right background | MEASURED |
| M6 | 2026-11-16: the same class, 0.83 of the bar's brightness after the iPad was connected (repair `7395057`, two delayed invalidations, never seen live) | MEASURED then, INFERRED cause |
| M7 | 18:24:46.070 Mission Control opened (Dock), 18:24:46.593 `cover: ... 7:0/0/0`, 18:24:47.723 closed, 18:24:48.054 `7:3/3/0`, 18:24:48.136 `7:0/0/0`, 18:24:48.040-.624 a grace began and recovered, then `hiding: notVerified(stale:3)` | MEASURED (`log show` at 18:26, lines quoted in the session) |
| M8 | 18:26 and 18:29:22: the three members drawn on the Sidecar bar, no `Ice Cover` window on screen. 18:33:20: three panels again. Between: Space swaps on display 1 at 18:27 (x2), 18:30:59, 18:31:19 and on display 7 at 18:31:18 | MEASURED (screenshots, window list, Dock) |
| M9 | The 1 Hz tick ran throughout (`timer` in `IceBarHidingCoordinator`), and the cover was active (a report with bars, not the empty one of `sync(active: false)`). So for about five minutes every pass found no block on display 7 | INFERRED from M7, M8 and the code |
| M10 | Why no pass found a block: unknown. With no panel over them, members answer the hit test on the Sidecar bar while the built-in bar is the active one (`watch.log` 18:36:09, 18:38:23: `1510@676-707:ok`, `1521:ok`) | TBD / MEASURED |
| M11 | A capture session shows the system's dot for 10-20 s, which moves every item 3 pt (F8 of the cover plan, MEASURED 2026-11-15). Today also: a `MenuBarAgent` slot 16 pt wide comes and goes among the members with no capture of mine (18:35:36-18:36:09, 18:38:13-18:38:23) and moves them 44 pt; what it is: TBD (not this plan's) | MEASURED |
| M12 | When the members move (M11), the panels follow at the next 1 Hz pass: for up to a second a member is drawn beside its panel (`watch.log` 18:38:23.171, panels at the old places, members answering) | MEASURED |

The structural fault behind M1 and M6: one capture is trusted for 30 minutes, and
what can make it wrong is a list of signals that has now been incomplete twice.

## Goal and non-goals

Goal:
1. A background taken at a moment that passes (a fade, a dim, a transition) is
   replaced without any signal, at the capture budget's next slot (12 s after the
   capture when nothing else captures), while the bar has a block to cover.
2. After Mission Control the members are covered again within 3 s of its end.
3. The next incident can be read from the log a day later.

Non-goals: another way to hide on a bar without a notch; `MenuBarCapture` and the
detector files (frozen); the built-in bar; finding every system state that dims;
M12 (the second a moved member shows); a capture for a bar that has no block (it
would show the dot for nothing: a ladder step that falls due meanwhile is taken
when the bar has candidates again).

Limit kept (L2 of the cover plan, narrowed): a background that changes with no
signal after it was confirmed twice is wrong until the next signal or 30 minutes.
A background that never holds still is redrawn at the steps of D1: every 300 s
once it has shown itself to move.

## Design

**D1 A background is confirmed, not trusted.** One pure rule in IceCore,
`CoverBackgroundTrust`, is the only place that says whether a display's
background is to be captured now and why; `CoverController.needsCapture` asks it
and decides nothing itself (round 1, finding 11). Per display:

```
state:  capturedAt, confirmDue (a time, or none), step (0 | 1 | 2 = confirmed), unequalRun, failedRun, failedAt
asked only while the bar's last pass left it a block (not merely a candidate)
reason(now, hasUsableImage, keyEqual, stale) -> size | key | stale | refresh | confirm | nil
    failedRun > 0 and now - failedAt < retry(failedRun) -> nil
    no usable image -> size;  key differs -> key;  stale -> stale;
    now - capturedAt >= 1800 -> refresh;
    confirmDue reached -> confirm
wait(n)  = 12 for n < 4, 300 from then on
retry(n) = 12 for n <= 2, 60 for n == 3, 300 from then on
captured(reason, equal) at t:                    failedRun 0, capturedAt t
    the new strip always replaces the held one (the newer capture is the better one)
    reason size | key | stale:         step 0, unequalRun unchanged,
                                       confirmDue = max(t + 12, min(confirmDue if any, t + wait(unequalRun)))
    reason refresh | confirm, equal:   step + 1 (at most 2), unequalRun 0, confirmDue = t + 48 at step 1, none at step 2
    reason refresh | confirm, unequal: step 0, unequalRun + 1, confirmDue = t + wait(unequalRun)
captureFailed (the image calls returned nothing):  failedRun + 1, failedAt now; the held image and confirmDue stay
```

The confirmation has its own deadline, which a signal's capture cannot push
back (round 3): it only keeps it at least 12 s after the newest strip, so the two
strips compared are never of one moment.

One capture answers every reason pending; the first in the order above is the
one logged. `equal`: `CoverPixels.sameColumns` over the whole strip at least
`equalShare` = 0.98, and over the columns of the bar's current blocks (each
padded 8 pt) at least 0.98 as well, so a change only behind the members restarts
the ladder too (finding 5; since the newer strip is always the one shown, a
wrong `equal` costs a later step, never a wrong panel).

So: 12 s and 60 s after a new background; each unequal capture starts again 12 s
later; from the fourth unequal in a row the steps are 300 s apart, for as long
as the background keeps moving (round 1, findings 3 and 4: a background that
moves is wrong under a snapshot anyway, and five minutes serve it better than
thirty). Only an equal comparison clears `unequalRun`: a signal's capture does
not, so signals that keep coming cannot refill the 12 s steps (round 2). The
signals themselves capture at the budget's pace as in 1.1.7; that cost is
unchanged and not this plan's. With a block up, every state has a finite next
capture, so no wrong background stays for more than 300 s plus the budget's
wait, and none of the loops is faster than 1.1.7's: a capture that keeps
failing is tried at 12, 12, 60, then every 300 s (1.1.7 tries every 12 s for
ever, `CoverController.swift:405`).

The bound is the budget's, not a clock's: an owed capture waits for
`CoverCaptureBudget` like any other (two calls of at most four in a second, then
none for 12 s; another display's session delays it by one rest).

Why a ladder and not a shorter refresh: M11. Two extra sessions per new
background cost two dot episodes; a refresh every minute would keep the bar
moving.

**D2 What a capture was is logged where it lasts.** One `notice` line per capture
(`IceBar cover: capture display 7 luma 0.412, equal true|false|first, transparent
true|false|failed`; with T4 also `reason key|stale|refresh|confirm|size, step 1,
unequal 0`, which only the rule of D1 can say) and the existing `cover:` report
line raised from `info` to `notice`. Low volume (on change only). No app names,
no pixels.

**D3 Why a bar has members and no block is logged, with where the numbers came
from.** When a pass leaves a bar with fewer covered slots than candidates, or
with no candidate while the roster has members, one `notice` line, at most once
per change: `IceBar cover: display 7 uncovered, members 3 memberOwners 3 vetoed
[pid,pid] coverable 0, set complete|incomplete|none pass 412 grace true|false,
slots 11 hosted 7 candidates 0 verified 0 silent 0 failed 0, read
ok|unreadable`. Pids and counts only (finding 10). `hosted` is the number of
slots with a child of another process: 0 is Mission Control's emptiness.

**D4 The cover after Mission Control: measured first, then one targeted fix.**
T0 runs a build that has only D2 and D3 (no change of behaviour) and reads the
line for the outage. Round 1's reading of the code, which I checked: every pass
overwrites `lastDiscoveredSet` (`MenuBarItemManager.swift:657`), a transient one
too, and `coverableOwners` (`:72-76`) lets any item of that set that is not a
member veto its pid; `syncCover` runs on every machine step, so the veto lasts as
long as the passes keep listing such an item. That fits M7's two reports 82 ms
apart (a pass forced by a changed `coverable`). It does not yet say which item
vetoed three pids for five minutes: INFERRED until T0.

| Hypothesis | D3 would read | Fix |
|---|---|---|
| H-a a member's pid is vetoed by an item the passes list after Mission Control under a key that is no member's | `coverable 0`, `vetoed` = the members' pids | by what T0 shows the item to be: the veto is taken from the roster's last trusted pass, or the key rule is repaired |
| H-b the members answer no hit test and the silent track does not let them stand | `candidates 3 verified 0`, silent or failed counts | per the count: a stale agent slot is no overlap, or a failed answer does not reset a track that stood |
| H-c the bar is unreadable and keeps the empty state of the Mission Control pass | `read unreadable` | an unreadable bar keeps its last readable state |
| none of these | | stop, amend this plan with what D3 read, quick review of the amendment |

While Mission Control shows, the tree lists no hosted child and the panels go
(M7, 18:24:46.593; `hosted 0`). Whether the members are drawn on the Sidecar bar
then is not measured. T0 measures it with one capture. Holding panels through
that emptiness is **not built in this plan** (round 1, findings 7 and 8: a panel
takes clicks, and an empty array is not proof of a transient). If T0 shows the
members drawn, the result goes into STATUS as an open limit with its length, and
a hold is a plan of its own: the reader answering `.readable | .unreadable |
.noHostedChildren`, scoped to blocks already up, ended by any slot in a block's
place.

**D5 cut** (round 1, finding 9): a grace's end as a signal for a capture is
unproven; D1 covers a strip changed by Mission Control when it is next confirmed.

## Tasks

| # | Task | DoD |
|---|---|---|
| T1 | D3 and D2's first half (luma, equal, transparent; no reason yet), tests first: the controller's report carries them; the coordinator logs them at `notice` | `CoverControllerTests` for the counts and the capture facts; no behaviour test changes; Debug and Release build |
| T0 | Reproduce M7-M9 on a Release build of T1 under the daily identity (prefs exported first, restored after; launched by path; the daily Ice quit meanwhile), `log stream` and `watch` running: up to six `open -a "Mission Control"`, each closed after 1.5 s; one capture during one of them | D3's line for the outage in `~/IceReverse-evidence/20261118-cover-N/`; the hypothesis named, or the plan amended; whether the members are drawn during Mission Control |
| T2 | D4's fix for the hypothesis found, test first | a unit or controller test that fails before and passes after |
| T3 | `CoverBackgroundTrust` in IceCore, tests first | every transition of D1's table; the reason order; `wait(n)`, `retry(n)`; a signal's capture leaves `unequalRun` and does not push `confirmDue` back; 100 % of the new file covered |
| T4 | `CoverController` asks the rule; the strip comparison in `CoverPixels` | `CoverControllerTests`: a dim first strip is replaced at 12 s with no signal; an equal one is next captured at 60 s and then not before a signal or 1800 s; unequal in a row: 12, 12, 12, 12, 300, 300; stale signals every 12 s between them neither bring the 12 s steps back nor put the 300 s confirmation off; a bar with candidates and no block is granted no capture, and a step that fell due meanwhile is taken when a block is up again; a capture that returns nothing is retried at 12, 12, 60, 300 and the held image stays; the capture line gains reason, step, unequal; the budget never exceeded with two displays owing |
| T5 | Live check, automated, bounded to 20 minutes: (a) six Mission Control openings: three `Ice Cover` windows within 3 s of each close; (b) with the panels up, my own borderless window at 50 % black over the whole Sidecar display, below the bar's level, is up when a capture is forced (a Space-independent signal: the window itself changes the under-strip signature) and closed 2 s later: the panel's pixels equal the bar's beside it within 15 s of the close, with no further signal than the ladder (the window's close changes the signature too, so the check is also run with D1 off to show the difference is the ladder's: if it cannot be told apart, (b) is reported as not shown and the unit tests stand alone); (c) no `uncovered` line at rest for 5 minutes | results table in STATUS (MEASURED, 26B131, date); a FAIL is reported as a FAIL |
| T6 | STATUS and the cover plan's limits updated; memory | L2 narrowed, D1-D4 listed |

Order: T1, T0, T2, then T3, T4 (round 1, finding 12: the outage is reproduced
before the capture cadence changes). Serial; no agents.

## Acceptance

1. `swift test` green in `IceCore` and `MenuBarCover`; new rule file 100 %, packages >= 80 %.
2. Debug and Release build of `Ice`.
3. T5 (a) and (c) pass, (b) passes or is reported as not shown, on 26B131.
4. The owner's 34 settings equal the export after the run.

## Tests

Unit (IceCore: the ladder; `CoverPixels`), integration (`CoverControllerTests`
with the fake reader, capturer, presenter and clock that exist), end to end (T5
on the real bar, read by `watch` and `probe`, no checklist for the owner).

## What it touches

`Packages/IceCore/Sources/IceCore/CoverBackgroundTrust.swift` (new) and its
tests; `Packages/MenuBarCover/Sources/MenuBarCover/CoverController.swift`,
`CoverPixels.swift`, `CoverTypes.swift` and tests;
`Ice/MenuBar/IceBar27/IceBarHidingCoordinator.swift`; for H-a
`Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`; `docs/macos-27/STATUS.md`.
Nothing in `MenuBarCapture`, the detector, the machine's rules.

## Risks and the way back

| Risk | Answer |
|---|---|
| The ladder's captures show the dot twice more per new background (M11) | accepted: 12 s and 60 s only; counted in T5 |
| A background that never holds still restarts the ladder | four at 12 s, then one every 300 s while a block is up |
| T0 does not reproduce in six openings | ship D1-D3; say plainly that D4 is open and that D3 will name it at the owner's next Mission Control (the lines last now) |
| `notice` lines in the system log | three kinds, on change only, pids and counts only |
| T5 (b) cannot isolate the ladder from the signature signal | said in the task; the controller tests are the proof of the rule, (b) only of the pixels |

Back: `/Applications/Ice.app` stays 1.1.7 until the owner says otherwise; the
branch is local.

## Open

M4 (what dims to 0.50); M10 (why no block for five minutes) until T0.

## Appendix: review

Cap: three rounds (Codex gpt-5.6-terra, medium).

### Round 1

| # | Finding | Ruling |
|---|---|---|
| 1 | High: the outage is most likely `coverableOwners` vetoing members from a transient `lastDiscoveredSet`; instrument that chain first | adopted (D4's text, T0 before any fix); the code path checked at `MenuBarItemManager.swift:72-76`, `:657` |
| 2 | High: a bar with no candidates gets no capture grant, so D1 repairs nothing then | modified: the guarantee is narrowed to bars with a block (goal 1, non-goals); not decoupled, because a capture for a bar with nothing to cover shows the dot for nothing (M11) |
| 3 | High: "12 s at most, 60 s worst" is no generic bound (budget, two displays, four unequal stop at 48 s) | adopted: the bound is stated as the budget's next slot; a 300 s step after four unequal |
| 4 | Medium: `maxRestarts` cannot tell a long transition from an animation | adopted with 3: `wait(4)` = 300 s once |
| 5 | Medium: 0.98 of the whole strip can certify a panel wrong behind the members | modified: the newer strip always replaces the held one, so equality decides only the ladder; the blocks' columns are compared too. Not "compare block regions only": blocks move (M11) |
| 6 | Medium: restart semantics unspecified | adopted: D1's table |
| 7 | High: holding panels through an empty read is unsafe | adopted: not built here; measured in T0, a plan of its own if needed |
| 8 | Medium: unreadable and empty are blurred | adopted as the shape that later plan must have |
| 9 | Medium: D5 is an unproven proxy | adopted: cut |
| 10 | Medium: D3's line cannot tell the roster from the veto | adopted: members, memberOwners, vetoed pids, set completeness, pass, grace |
| 11 | Low: the trust type must be the single scheduler or stay private | adopted: single source, `needsCapture` only asks it |
| 12 | High: T0 after T1-T3 turns the investigation into a moving target | adopted: logging-only build first, then the fix, then the ladder |

### Round 2

Findings 5 and 7 of round 1: stand, said Codex.

| # | Finding | Ruling |
|---|---|---|
| 2' | Medium: captures are admitted on candidates, not blocks (`CoverController.swift:245`): a candidate that fails verification still gets a capture, a dot for nothing | adopted: the rule is asked only for a bar with a block; T4 tests candidates without a block |
| 13 | High: a capture that returns nothing leaves `size` due at every budget slot, for ever | adopted: `captureFailed`, `retry(n)` 12, 12, 60, 300. It never gives up: without an image the members are drawn. 1.1.7 already loops at 12 s here; this makes it slower, not new |
| 14 | Medium: repeated stale signals reset `unequalRun` and defeat the limit | modified: a signal's capture leaves `unequalRun`; only an equal comparison clears it. The signals' own captures stay as in 1.1.7 (the background did change); the cost is stated in D1. Also `wait` no longer ends in "never": that state would have kept a dim capture for 30 minutes |
| 15 | Medium: T1 cannot log `reason confirm` before the rule exists | adopted: T1 logs luma, equal, transparent; reason, step, unequal come with T4 |

### Round 3

| # | Finding | Ruling |
|---|---|---|
| 14' | Medium: leaving `unequalRun` alone is not enough: each signal's capture moves `capturedAt`, so signals that keep coming put the confirmation off for ever | adopted as proposed: `confirmDue` is a deadline of its own, never pushed back by a signal's capture |

Trend: 12 findings, 4, 1; nothing disputed is left (findings 2, 5, 7 as modified
stand by Codex's own word in round 2; 14 ended as Codex proposed). The cap is
reached and the plan is final. What the review could not settle is what the
plan itself leaves to T0: M10's cause.

## Amendment A: what T0 read (2026-11-18, run `20261118-cover-1`, 26B131)

A Release build of T1 (logging only) ran under the daily identity from 18:55;
six Mission Control openings of 1.5 s, 18:56:21-18:58:43 (`mc.log`,
`ice-stream.log`, `watch.log`).

| # | Result | Grade |
|---|---|---|
| R1 | The outage came back at opening 4: 18:57:45.097 a transient pass (`grace: began ... items 3`), 18:57:45.435 `7:0/0/0`, 18:57:46.779 `recovered`, `notVerified(stale:3)`, no panel until 18:58:10.189 (24.8 s). Throughout, the members' slots were listed under their pids and answered the hit test (`watch.log` 18:57:46.208, `covers []`). It ended with a pass that read the members again, the Sidecar bar being the active one from 18:58:06 | MEASURED |
| R2 | The cause: `PreferenceHidingMembership.resolve` gives a member that a read does not list `key: nil` and `.stale(.missingFromRead)` (`PreferenceHidingMembership.swift:278`). A transient pass is not blind, so it does that to every member. The blind passes after it keep the members as they are (`PreferenceHidingRoster.advanced`), so the keys stay `nil` until some pass lists the members. `coverableOwners` takes the pids from `members.compactMap(\.key)`: none, so no candidate. This is H-a's symptom by another mechanism; none of the three as written | MEASURED (the log's `stale:3` with no candidate) + code |
| R3 | D3's line was not written for the outage: its condition counted the members by their keys as well | MEASURED |
| R4 | Mission Control dims the strip to 0.86 (luma 0.306 against 0.352-0.357). A capture fell into four of the six openings (the windows under the strip change), and 1.1.7's own signal replaced it 12 s later each time. So such an opening leaves the panels at 0.86 for 12 s | MEASURED |
| R5 | After an opening the wallpaper is not where it was: the captures before and after are unequal (luma 0.354, 0.357, 0.352), a strip of 18:35 and one of 19:03 share no column (`cmp`), and two strips 15 s apart at rest are identical. The owner's wallpaper moves at events and holds still between them | MEASURED; that this is M4's class: INFERRED |
| R6 | Whether the members are drawn during Mission Control: not measured (T5 takes one screenshot) | TBD |

**D4 as built (T2).** `PreferenceHidingRoster.memberKeys`: each member's key, or
the key it was last read with (`lastKeys`, which the roster already keeps for
G1). `MenuBarItemManager.coverableOwners` and the diagnosis take the members'
pids from it. A member whose process exited is already dropped by `carried`.
The veto by the pass's other items stays as it is. `isOnMenuBarItem` uses the
same `compactMap(\.key)` and is left alone: not this plan's.

**D3 corrected.** The line counts the roster's members (`members 3 keyed 0`),
and is written for a bar without a notch whenever a pass leaves fewer slots
covered than candidates, or no candidate.

**D6 (new, from R4) A pass that leaves a bar no block takes no capture.** The
grant is decided before the read; the pass that first reads Mission Control's
emptiness would capture the dimmed strip. In `CoverController.run` a granted
capture is taken only if that pass's own read left the bar a block; the held
image stays, and the stale flag asks again when the blocks are back. The
budget's session is spent either way.

Tasks: T2 = D4 as built + D3 corrected (tests first: a roster whose members a
non-blind pass did not list still names their keys; `CoverPlan` unchanged). D6
joins T4 (controller test: a granted capture in a pass with no hosted slot is
not taken, and is taken on the next pass with blocks).

### Amendment A, quick review (two exchanges)

| # | Finding | Ruling |
|---|---|---|
| A1 | R2's chain is right (`PreferenceHidingMembership.swift:276-278`, `PreferenceHidingRoster.swift:67-72`, `:95-99`) | confirmed |
| A2 | High: `lastKeys` is pid-only; a reused pid or a member moved visible could become coverable | rejected, and withdrawn by Codex: a blind pass with no transient pass before it carries the same key in `member.key`, alive by `kill(pid, 0)` only, and `coverableOwners` has used it since 1.1.3; the fallback restores that value and adds none. No sequence found in which it covers what the shipped path would not. The limit goes into STATUS as Codex worded it |
| A3 | D6 cannot leave panels without an image or stop captures for good | confirmed |

CONVERGED.

## Amendment B: what the first live run of the whole fix read (run `20261118-cover-2`, 19:13-19:17)

| # | Result | Grade |
|---|---|---|
| S1 | Six openings. In 3 and 6 a transient pass fell (`grace: began`, `stale:3`): the three panels stayed (`watch.log`), where 1.1.7 lost them for 24.8 s. D4 holds | MEASURED |
| S2 | Opening 1: a capture at 19:14:28.216, as Mission Control closed, read `transparent false`; the panels went at 19:14:29.2 and came back with the next capture at 19:14:40.5 (11.3 s, the members drawn). 1.1.7 does the same: `apply` removes the panels on one non-transparent capture | MEASURED |
| S3 | D6's premise is wrong: `MenuBarAgent`'s tree keeps its hosted slots through Mission Control (no `0/0/0` report in any opening without a transient pass). D6 stays as a rule of its own (no block, no capture) and avoids no capture in Mission Control | MEASURED |
| S4 | R6 answered: during Mission Control its own strip of Spaces covers the bar on the Sidecar display, so no member is seen; the three panels show over that strip as boxes of wallpaper for the opening's length (`during-mc.png`). 1.1.7 does the same | MEASURED |
| S5 | The ladder ran as written: `size`, `confirm` 12.5 s later (`equal true step 1`), and after each signal's capture a `confirm` 12-13 s later | MEASURED |

**D7 (new, from S2) One capture that does not show the bar transparent is not
believed while a transparent image is held.** The image, its key and the stale
flag stay, the panels stay, and the same reason asks again 12 s later
(`captureFailed`'s first wait: the budget alone would allow a second session in
the same second). The next capture is believed whatever it shows, so a bar that
has become opaque for good loses its panels 12 s later than in 1.1.7, once.
Test first: `opaqueMomentIsDoubtedOnce`.

Not built, said as a limit (S4): the panels are not taken away while Mission
Control shows. That needs a sign of Mission Control that costs no capture (the
window list during it is not measured), and is a plan of its own.

## Results (2026-11-18)

Built as amended (D1-D4, D6, D7; D5 cut). /simcodex: three rounds, P1 5, 1, 0
from the cleanup reviews; Codex one P2 in each of the first two rounds (a
returning display's diagnosis, an empty roster said uncovered), both fixed, and
none in the third. What the cleanup rounds changed against the text above: the
doubt of D7 is a state of `CoverBackgroundTrust` (`believes`, `doubted`), not
the controller's, and waits 12 s on its own count, not on the failures'; D3's
line is said when what is covered changes, not when a hit answer does.

Acceptance: 1. tests green (IceCore 928, MenuBarCover 41, MenuBarDiscovery 96
and 88, MenuBarCapture 30; the probes package builds with its tests against the
changed IceCore and was not run: over an hour, none of it this code); the new
rule file 100 %, `MenuBarCover` 62 % as a package because its live halves have
no unit test, as before: the 80 % of this plan is not met there and is not
this change's to meet. 2. Debug and Release build. 3. T5 (a) and (c) pass on
the final build (run `-5`); (b) not shown, as the task allowed. 4. The 34
settings: 31 equal as stored, two equal after JSON decoding, one window frame
1 pt off; the export was imported back byte for byte before the daily Ice was
started again.

Deferred, P2: the pixel work of a capture runs on the main thread and decodes a
strip more than once (at most once per 12 s per bar); one per-bar record for
`backgrounds` and `trusts`; one outcome value instead of three flags on
`CoverCaptureFact`; `isOnMenuBarItem` and `LabReport` keep their own reading of
a member's key.

Open: M4 (what dimmed the desktop to 0.50 at 18:23); the panels over Mission
Control's own strip (S4).
