# Blind at length: hiding and the Ice Bar on macOS 27.2

2026-11-15 · branch `wip/blind-at-length` · version 1.1.3. Labels: MEASURED, INFERRED, TBD.

## The owner's report (2026-11-15)

After updating to macOS 27.2 the daily Ice (1.1.2) hides and shows the chosen items in
turn, for ever; another user on 27.2 sees the same and a notice that keeps changing. The
owner approved the direction below on 2026-11-15 ("OK 可以開始了").

## Facts (MEASURED 2026-11-15, macOS 27.2.1 build 26B131, the owner's Mac; evidence `~/IceReverse-evidence/20261115-272-flicker/`)

| # | Fact |
|---|---|
| F1 | Ice 1.1.2 loops with a period of 5 s: a pass at the hiding length logs `hidden(identifiersMissing)` and `blocked(ownReadNotOk)`, the length is retired, the re-read 1.3 s later is ok (`notVerified(unchecked:5)`), the length is applied, the next pass blocks (the owner's recording, `timeline.png`; the logs of two Macs) |
| F2 | Polled every 150 ms (`watch-live.txt`): at the hiding length Ice's own `AXExtrasMenuBar` lists `Ice.ControlItem.Visible` only; at standard length also `Ice.ControlItem.Hidden`. In the same phases the five members (five apps) are absent from their owners' extras bars, and back in the first sample after the divider's collapse (4 cycles of 4) |
| F3 | Sacrificial helpers, a spacer at 736 pt and a target left of it (`hold.txt`): the target's and the spacer's `AXExtrasMenuBar` answer noValue (-25212); an element of the target held from before answers -25201 to `AXRole`, `AXPosition` and `AXPress`, no menu opens; back at rest all are listed in the first sample, the held element answers again, a fresh `AXPress` returns 0 and the helper reports `menu open` |
| F4 | `MenuBarAgent`'s tree has no slot for the pushed-off target or the spacer (`agent.txt`); the slots of items that were not pushed stay |
| F5 | The window list has no window at layer 25 for any process, on screen or not (`probe/layers.swift`): no other source lists a pushed-off item |
| F6 | After Ice retires the length, its divider and the members are listed again within 150-200 ms (`watch-live.txt` beside `stream-watch.log`); after the length is applied they are gone within about 370 ms |
| F7 | For contrast, 27.0.1 (26A434): a press while pushed off opened the menu 5 of 5 (plan `2026-10-03-icebar-build`, T0 result) and the note at rest was `hidden(expanded)`: the divider was listed at length (plan `2026-09-24-ice-first-run`, E3) |

Every item tested behaves so (five items of five apps, Ice's divider, two helpers); 736 pt
is the only length the shipped mode applies (`IceBarHidingParameters.unverified`: `start`
applies `bestEffortLength(after: [])`, which is `defaultStart` without a verified length).

## Cause

On 27.2 a status item pushed off the bar, the lengthened divider included, is not in
Accessibility at all. Ice reads "the own pass has no hidden divider" as an own read that
failed (`ItemCatalog.swift:125`, `PreferenceHidingPreconditions`), retires the length
(`IceBarHidingMachine.handle`), reads well at standard length and hides again. The same
absence leaves `MenuBarItemPresser` nothing to press, turns every member
`stale(.missingFromRead)` (`PreferenceHidingMembership.resolve`) and takes the members' tags
out of `LayoutSignature.items`, itself a structural change that retires the length.

## Goal, and what is not done

Goal: on 27.2 Ice rests hidden without retiring the length, and a hidden item opens from
the Ice Bar. 27.0 and 27.1 keep their behaviour.

Not done: `Packages/MenuBarCapture` and the detector files (frozen); the cover's rules; a
length other than the one the shipped mode applies; verified mode (`verifies == true`,
not shipped) on 27.2.

## Design

### D1 The blind pass (IceCore, decided by what is read, not by a version)

A pass is **blind at length** when all of:

1. Ice's own state holds the length: the hidden control item exists, is visible, and its
   status item has the length the coordinator last wrote (in-process, not Accessibility);
2. the hidden `DividerState` is enabled, not collapsed and did not change during this pass;
3. the pass is `.complete`;
4. the own read lists Ice's icon (`visibleControlItem != nil`) and no hidden divider
   (`ownRead == .identifiersMissing`, `hiddenDivider == nil`);
5. the roster has members.

`BlindAtLength.holds(set:hiddenDividerState:holdsWrittenLength:hasMembers:)` is that rule,
pure. A missing divider at standard length, an incomplete pass, an own read without the
icon: all block as today.

### D2 What a blind pass does to the roster (`PreferenceHidingRoster.advanced`)

A blind pass says nothing of anything left of the divider. So:

- preconditions: `ownReadNotOk` is not a reason (`evaluate(..., isBlindAtLength: true)`);
  the others are evaluated as today (the icon's placement is already the held one at a
  length, `IcePlacementNotice.placement`);
- membership: carried, each member with the condition and key it had, less the members
  whose process exited (`carried`, as today); blockers carried;
- `itemTags`: one set decides it, **the visible tags read gone**: the previous
  `visibleTags` that this pass does not read. The new `itemTags` are the previous tags and
  the tags read now, less that set (an item seen right of the divider and gone is gone;
  anything else unread is left of the divider and presumed there). A non-member left of the
  divider (piled on it by a crowded bar) therefore does not leave the signature;
- the boundary: today's rule with the same set as its `removed` (kept on the same display
  unless a visible tag was read gone; today's expression gives exactly that on these
  `itemTags`, since only that set leaves them). `lastKeys` as carried; `visibleTags` from
  this pass's items against the kept boundary, as today;
- without a boundary (`visibleTags` empty, as after a removal) no tag can be read gone: a
  later removal of a visible item stays in `itemTags` until the next standard-length pass.
  That is today's standing at a length on 27.0 as well (an untrusted pass never sets the
  boundary) and costs nothing: a pure removal is not structural, and an item added then is
  structural (it cannot be placed without a boundary) and retires the length.

The roster publishes `isBlindAtLength` (the last pass was blind): D4 and the pane's limits
read it. `DiscoveredCachePlan` is unchanged: at a length the boundary was never usable
(`expanded` before, `identifiersMissing` now), and `start` reads `boundaryUsable` only from
`.quiet`.

### D3 The click: show, press, hide again (`IceBarHold`, the coordinator, the presser)

- `MenuBarItemPresser` answers `.notListed` (no extras bar, or no child the key names)
  apart from `.pressed(PressOutcome)`. The direct press stays first: where a pushed-off
  item is listed (27.0, 27.1) nothing changes.
- On `.notListed` the coordinator takes a **hold**: `IceBarHold` (IceCore, pure) has at most
  one current hold with a token, a purpose (`press(tag)` or `reread`), and a phase.
  `release(token, ending)` is the one operation every ending passes through and changes
  nothing for a stale token. `begin` is refused while a press hold is `pressing` or
  `showing` (its menu may be open); otherwise it replaces the current hold.
- The machine reads a new sample flag `isHeld` and stays at standard length while it is
  set (`handle`: quiet, as for a drag, by its own flag). The coordinator stays the one
  writer of the length, through the machine.
- A press hold's phases:
  - `waiting(deadline)`: the presser is asked again every 50 ms until it does not answer
    `.notListed` (lookup and press are one call: no gap between them). The deadline (2 s;
    F6: listed within 0.2 s of the retire) bounds only this wait.
  - `pressing`: a press is dispatched; lasts until that call returns. No deadline ends it.
  - `showing`: the call returned (a menu's press returns when the menu closes; a popover's
    at once; a menu open past the presser's 60 s returns as a timeout) and the pressed app
    still shows what the press opened. Upstream's rule for an item it shows for a click
    (`TemporarilyShownItemContext.isShowingInterface`, `MenuBarItemManager.swift`), as a pure
    rule in IceCore (`OpenedInterfaceRule`): at a menu, status or main-menu layer a window
    shows while on screen, at any other while on screen and its app is active. Which
    window: the on-screen windows are listed before the press is dispatched, and while the
    call is outstanding (every 0.25 s) and once more 0.25 s after it returns the first
    window of that pid that is not in that list is taken: bound to the press's own
    interval, not to whatever that app shows later. No such window, or it no longer shows
    (looked at every 0.5 s): the hold ends.
- The release: one pass is taken and awaited first (the bar as it is now), the token is
  checked again after it, then the release, then a tick: the machine hides by a roster no
  older than that pass. (A long
  hold has had trusted passes every 5 s; `hiddenBoundaryUsable` is reset whenever the
  divider's state changes, `MenuBarItemManager.recordDividerState`, so a pass from before
  the retire never counts.)
- Endings: finished; the wait deadline; a drag begins; IceBar mode off; a newer hold; the
  pressed member left the roster. (The direction agreed with Codex said "a structural roster
  difference"; narrowed here, because a trusted pass during the hold may add a member that
  arrived, and that must not cancel the owner's click.)
- A press that ends by the deadline disables the cell as a failed press does today; one
  ended by a drag, mode off or a newer hold does not.

Owner-visible: while what a hidden item opened is showing, the hidden items are on the bar.

### D4 Arrivals: a re-read before the Ice Bar opens, when one is owed

On 27.2 an item that appears left of the lengthened divider is read by nothing (F2-F5): a
new app's item, or a member's app that restarted. Any show-press cycle includes a trusted
pass and lists it; so does this:

- the coordinator keeps the uptime of the last app launch (`NSWorkspace.didLaunchApplication`)
  and the manager the uptime at which the last trusted standard-length pass began;
- `ArrivalRule.isRereadOwed(lastLaunchAt:trustedPassBeganAt:grace:)`: owed until a trusted
  pass has begun 3 s or more after the last launch (an app sets its item up after it
  starts). A pass begun sooner does not pay the debt: the opening it served may miss that
  app's item, and the next opening reads again. The opening is not made to wait for the
  grace;
- `MenuBarSection.show()` asks the coordinator before its `isIceBarOffered` guard. When the
  last pass was blind and a re-read is owed, the request becomes one `reread` hold (one
  token, used once): `waiting(deadline 4 s)` for a trusted pass that began after the hold
  did; then the release (as D3's) and `reapplying(deadline 2 s)` for the length. Outcomes:
  the length is applied in time: the token is spent and `show()` is called with the
  question skipped, so the panel never opens at standard length and the call cannot ask
  again; either deadline, or a stale token: the request is dropped and logged, the bar is
  left to the machine, and the owner's next click asks anew. Otherwise (no debt, or the
  last pass not blind) the panel opens at once as today.

Owner-visible: after an app was started, the next opening of the Ice Bar shows the hidden
items on the bar for about 1.5 s first.

### D5 What Ice says

With every line that carries the limits, when the last pass was blind, one more sentence
(`IceBarHidingStatus.blindLimits`, in `OwnerMessage.allTemplates`, zh-Hant in the catalog):
"On this macOS version a hidden item's menu opens with the hidden items back on the menu
bar, and an item that appears while they are hidden is listed the next time the Ice Bar
opens."

## Tasks (serial: each builds on the one before; no agents)

| # | Task | DoD |
|---|---|---|
| T1 | IceCore `BlindAtLength`, `PreferenceHidingPreconditions.evaluate(..., isBlindAtLength:)` | tests first: the five conditions each alone false; a missing divider at standard length blocks; red, then green |
| T2 | IceCore roster carry (D2), `isBlindAtLength` | tests first: members, conditions, keys, blockers carried; exited member leaves; `itemTags` by D2 (member, piled non-member, visible gone, visible new); on a blind pass the boundary and `visibleTags` are kept when nothing visible went and cleared when one did, `lastKeys` equal the previous; without a boundary a visible removal stays in `itemTags`; the signatures of a trusted pass and the blind pass after it are equal (`between` gives `nil`); a non-blind missing divider stale and blocked as today |
| T3 | IceCore machine: `IceBarHidingSample.isHeld` | tests first: held retires the length and stays quiet; after the hold a sample with a usable boundary hides; the 27.2 sequence (rest, blind samples for 60 s) gives no command |
| T4 | IceCore `IceBarHold` (both purposes, every phase) | tests first: a stale token changes nothing in any phase; the deadline ends `waiting` and `reapplying`, never `pressing` or `showing`; `begin` refused while `pressing` or `showing`, replacing otherwise; each ending; `isHeld` per phase (not in `reapplying`); a `reread` hold accepts only a trusted pass begun after it; its token opens once |
| T5 | IceCore `ArrivalRule`, `OpenedInterfaceRule`, `blindLimits` (D5), catalog | tests first (a pass within the grace leaves the debt; the layers and the active-app case of upstream's rule); `check-zh-hant.sh` passes |
| T6 | App: D1's inputs into `updateIceBarRoster`; the trusted pass's start | builds; R1 |
| T7 | App: presser `.notListed`, the coordinator driving `IceBarHold`, the press fallback | builds; R2-R5 |
| T8 | App: the launch time, `show()`'s question, the deferred opening | builds; R6, R7 |
| T9 | The probe into `docs/macos-27/probes/ownextras.swift` with its README row; STATUS and FINDINGS (27.2.1 rows, the spike B row marked 27.0.1 only); version 1.1.3 | `check-settings.sh`, `check-zh-hant.sh` pass |
| T10 | Rehearsal on 27.2.1: a `blind` command in the lab rig (`docs/macos-27/probes/dualband`, as `cover` is) with `run-blind.sh`; a lab-identity copy, sacrificial helpers (one with a menu, one with a popover), the daily Ice quit (it is; left as found) | R1-R8 below, each MEASURED into STATUS |
| T11 | /simcodex, all package tests, the Debug and Release builds | green |

## Acceptance

| # | Check | How |
|---|---|---|
| A1 | IceCore tests pass; each new or changed rule file at 80 % line coverage or more | `swift test --enable-code-coverage`, `llvm-cov report` |
| A2 | The app builds, Debug and Release | `xcodebuild` |
| R1 | At rest for 60 s: no `blocked(` line and no retire; the own extras list the icon only throughout | the copy's log; `ownextras watch` |
| R2 | A press on a helper member with a menu: the helper reports `menu open`; after `closemenu` the length is applied again within 5 s and the helper is unlisted | the lab `press` command; the helper's output; the log |
| R3 | The wait deadline: a member whose item its helper has hidden (`hide`) is pressed: the cell is disabled, the length is applied again within 5 s | as R2 |
| R4 | A menu left open 65 s (past the presser's timeout): the length stays retired until it closes. A popover helper pressed: the length stays retired while the popover shows, and is applied within 5 s of its close | as R2 |
| R5 | A drag begins during a hold: the hold ends, the bar stays shown for the drag (unit-tested; live only if a drag can be injected on helpers alone, else stated as not run) | `dragown` on the two helpers |
| R6 | A helper launched while hidden, then the Ice Bar asked for 5 s later: listed in the cells after the deferred opening. The same asked for at once (within the grace): the panel opens after one re-read, and a second asking reads again and lists it | the lab report's cells |
| R7 | A member helper quit and started again while hidden, then the Ice Bar asked for: listed again | as R6 |
| R8 | 408 pt and 1000 pt by the lab's length override: the same absence (a limit statement, not a gate) | `ownextras hold` |

27.0 and 27.1 cannot be rehearsed (this Mac is on 27.2.1, there is no other): their
unchanged behaviour stands on the unit tests (the blind rule needs `identifiersMissing`;
the direct press is tried first). Stated in STATUS as INFERRED.

## Tests

TDD in IceCore (Swift Testing, the existing suites' style). The app target has no unit
tests; its wiring is covered by the rehearsal (the integration and end-to-end part). The
probes package (`docs/macos-27/probes/visibility`) is not touched and its hour-long suite
is not run; `ownextras.swift` is a one-file probe outside it.

## Impact

IceCore: `BlindAtLength.swift` (new), `IceBarHold.swift` (new), `ArrivalRule.swift` (new),
`OpenedInterfaceRule.swift` (new),
`PreferenceHidingPreconditions.swift`, `PreferenceHidingRoster.swift`,
`PreferenceHidingMembership.swift` (a carry helper), `IceBarHidingMachine.swift`,
`IceBarHidingStatus.swift`, `OwnerMessage.swift`. App: `MenuBarItemManager.swift`,
`MenuBarItemManager+IceBar27.swift`, `IceBarHidingCoordinator.swift`,
`MenuBarItemPresser.swift`, `MenuBarSection.swift`, `Localizable.xcstrings`, the project
file (version). Docs and one probe.

## Risks and the way back

- The hold's release racing a late press (Codex's first worry): one token-checked release,
  unit-tested, and R2-R5.
- A blind pass that hides a real fault of Ice's divider: D1 needs Ice's own in-process
  state of it, and any pass at standard length judges as today.
- The deferred opening lost between a launch and a pass: the rule compares times, not a
  flag; R6, R7.
- Way back: 1.1.2 stays released; on 27.2 it loops, so the way back there is to quit Ice.

## Appendix A: the direction's debate with Codex (2026-11-15, three rounds; `~/IceReverse-evidence/20261115-272-flicker/codex/`)

| # | Point | By | Ruling |
|---|---|---|---|
| 1 | "every status item" overstates the evidence | Codex | adopted: "every item tested" |
| 2 | rule out a timing race over several lengths | Codex | rejected with evidence (absent for whole phases; one length in the shipped mode); Codex agreed; 408 and 1000 pt measured as a limit (R8) |
| 3 | a fourth blocker, `hiddenBoundaryUsable` | Codex | rejected with evidence (`start` only from `.quiet`; never usable at a length before either); Codex agreed |
| 4 | the blind gate too broad | Codex | adopted: D1's five conditions, Ice's own in-process state among them |
| 4a | no display or layout change since the trusted pass, as a gate condition | Codex | rejected (the machine owns both; plan `2026-11-15-cover` D5); Codex agreed |
| 5 | the hold through the drag flag | Codex | adopted: its own flag, token, one release |
| 5a | panel close cancels the hold | Codex | rejected (the hold itself closes the panel); Codex agreed |
| 6 | arrivals: a lazy re-read when the Ice Bar is asked for | both | adopted; only when a launch followed the last trusted pass (mine, Codex agreed) |
| 7 | the deadline must not end a hold after the press is dispatched | Codex | adopted (D3) |
| 8 | `show()` returns before the panel when no length is applied: the opening must be deferred from before that guard | Codex | adopted (D4) |
| 9 | a launch during the settled pass must not be forgotten | Codex | adopted: times compared, a pass that began after the launch (D4) |

Codex's first worry: the hold's restore race.

## Appendix B: the plan's review by Codex (2026-11-15/16)

Round 1: five P1, three P2.

| # | Finding | Ruling |
|---|---|---|
| B1 (P1) | D2: carried tags would read as removed and clear the boundary; one shared "read-gone visible tag" set must decide both | the claim rejected (only that set leaves `itemTags`, so today's `removed` expression is that set already); the suggestion adopted: D2 names the set, T2 tests the boundary on both sides |
| B2 (P1) | D3: `rereadSoon` runs at the retire, not at the release; gate `start` on a pass newer than the release | partly: one pass is taken before the release (D3); a new gate in the machine rejected (`hiddenBoundaryUsable` is reset by every change of the divider's state, so only passes at this standard length count, and a long hold has one every 5 s) |
| B3 (P1) | D3: a press that times out at 60 s is accepted while the menu may still be open; the hold would hide under it | adopted, and wider: a popover's press returns at once. The `showing` phase with upstream's own rule (D3), R4 |
| B4 (P1) | D4: the grace is backwards; an opening right after a launch can miss the item and lose it | partly: the debt is not paid by a pass within the grace, so the item is not lost (stated, tested, R6); making the opening wait for the grace rejected |
| B5 (P1) | D4: `show()` again can open at standard length, lose the request, or recurse | adopted: one token used once, outcomes spelled out (D4) |
| B6 (P2) | D2: a visible removal clears the boundary and nothing rebuilds it at a length | as today on 27.0; stated and tested (D2, T2) |
| B7 (P2) | T2, T6-T8 DoDs not judgeable | adopted: T2's blind-pass values; the hold's and the deferred opening's logic in `IceBarHold` (pure, T4); T6-T8 name their rehearsal cases |
| B8 (P2) | `begin` replacing a pressing hold hides under the first menu | adopted: refused while `pressing` or `showing` |

Round 2: my rulings on B1, B2, B4 and B6 judged right; D3's release order and D4's
one-token opening sound. One P1 more, adopted: the window a press opened must be found
against a list taken before the dispatch and while the call is outstanding, not only after
it returns (D3, `showing`). Two wordings adopted: the release's pass is awaited and the
token checked again after it; the opening waits for the length to be applied. Codex names
the `showing` phase's window attribution as the step most likely to fail: R4 measures it
on a menu and on a popover. Plan final, 2026-11-16.
