# Flash on item change: hidden items shown for a second when any icon comes or goes

2026-11-13 · branch `wip/flash-on-item-change` (from `main` 46a6a13) · the owner's
report the same day. Labels: MEASURED, INFERRED, TBD.

## The owner's report

"Sometimes it shows the hidden apps for a moment, then hides them again." The owner
reproduced it on a screen recording: any icon added to the bar shows the hidden items
once, any icon removed shows them once more.

## What is wrong

| # | Fact | Grade |
|---|---|---|
| F1 | `PreferenceHidingLayoutChange.itemsChanged` is structural: the machine retires the length (`setLength(nil)`) on any change of the third-party item set, then hides again after the next pass (`IceBarHidingMachine.handle`, `isStructural`) | MEASURED (code) |
| F2 | On the owner's bar the daily Ice logged `notVerified(lengthNotApplied)` at 14:40:11.212 and 14:40:16.137, each followed about 1.2 s later by a rest at the length | MEASURED (`~/IceReverse-evidence/20261113-flash/stream.log`) |
| F3 | A sacrificial item (`com.icespike4.target`, no autosave) launched while Ice hid at 738 pt: its AX frame read `x7 w14` at 0.10 s, then `x1222 w14` from 0.16 s on, the same frame before and after the retire; Ice's divider went to standard length at 0.27 s (`x1112 w18`, so the item was right of it: visible, not a member) and back to 738 at 1.55 s. The retire was needless | MEASURED, 1 run (`frames1.log`, same folder) |
| F4 | At the hiding length the divider's own frame reads `x1120..1148 w738`: its right edge is not where it draws the boundary (STATUS line 148). Only a trusted pass (standard length, settled) gives the boundary | MEASURED (F3), STATUS |
| F5 | A removal adds no item, so it needs no classification: nothing new can be hidden by it | INFERRED (logic) |

Why the length is retired today: the roster advances only at standard length, so an
item that appeared left of the divider would be hidden but never listed in the IceBar.
That reason holds for an item that may be left of the divider. It does not hold for a
removed item, or for an item read right of the boundary.

## Design

D1 A soft item change. `itemsChanged` stays structural, except when all of these hold;
then it is a new soft case `visibleItemsChanged` (no retire; with `verifies` on, the
checks are owed again as for any soft change, D-e unchanged):
- same display (a display change is still checked first);
- the member tags are unchanged or a subset of the old ones (at a hiding length the
  roster is frozen, `PreferenceHidingMembership.resolve`; it shrinks there only by
  `carried`, when a member's process has exited);
- no added item tag is a member tag (a returning member retires, as today);
- either nothing was added (a pure removal), or every added item tag reads `.onBar`
  (not parked, stacked or frameless) with a finite frame whose `minX >=
  visibleBoundary` (D2) in the same pass.
Anything else retires as today.

D2 `visibleBoundary`, kept by `PreferenceHidingRoster`, never estimated:
- set on every trusted pass (`DiscoveredCachePlan.evaluate(...).minX != nil`, the
  rule membership already uses) to the hidden divider's `frame.maxX`;
- cleared (`nil`) by any pass that reads an item tag gone since the last pass, by a
  display change, and before the first trusted pass. A removal may move the divider
  (F5 is not relied on): after one, every addition retires until a trusted pass sets
  the boundary again. A removal and an addition in the same pass therefore retire;
- kept unchanged after a soft addition: an item added right of the divider moves the
  divider left, so the kept value is to the right of the real one and errs toward
  retiring.
No widths or frames of removed items are kept.

D2b Rejected: an "anchor" (an added item judged visible when right of an item seen
visible on an earlier pass). Codex REVISE (BLOCKER: AX frames are not drawn-ness,
`ItemPosition.swift` 7-12, FINDINGS 621-624 and 661-663; order not proven to change
only by a drag), then the debate chose dropping it: D2's AX risk is bounded by a
boundary read at standard length; an anchor would claim visibility after that
boundary was deliberately cleared. Limit kept, said to the owner: after an item goes,
the next addition still shows the hidden items once, until a standard-length pass.

D2a The display a boundary belongs to. A pass's display is identified by
`DiscoveryResult.bounds` together with `DiscoveryResult.origin` (the display's origin
in the global Accessibility space, `LiveDisplay.bar()`), which the pass itself read.
`PreferenceHidingRoster.advanced` gains a `display: BarDisplay` parameter, a new
IceCore value (`BarBounds` plus the origin's x and y; `DiscoveryOrigin` lives in
MenuBarDiscovery, which IceCore does not import);
`MenuBarItemManager.updateIceBarRoster` passes them from the `DiscoveryResult` it
already holds. The roster stores the display with the boundary; a pass on another
display clears the boundary before `visibleTags` is computed. The coordinator's
`displayID` in the signature is unchanged and still makes a display change
structural on its own.

D3 Where the facts travel. `PreferenceHidingRoster.advanced` computes, for the pass's
item tags, `visibleTags` (on the bar, finite frame, `minX >= visibleBoundary`; empty
when the boundary is `nil`), after applying D2's clear for this pass.
`LayoutSignature` gets `visibleTags`; `PreferenceHidingLayoutChange.between` classifies
with it and the member tags. The machine, the coordinator and the IceBar are unchanged
otherwise (the coordinator already builds the signature through
`PreferenceHidingRoster.signature`, which carries the new field).

D4 The placeholder frame (F3, `x7` for 0.06 s). It reads left of the boundary, so a
pass that catches it retires as today. No grace period: an item that really landed
left of the divider must not stay unlisted.

Safety argument. An item is hidden and unlisted only if it sits left of the divider
and is not a member. A pure removal adds no item. An addition is soft only when its
own frame, read in that pass, is right of a boundary that was read at standard length
and has seen no removal since (additions since then only move the real divider left).
A change with both a removal and an addition stays structural in the classifier itself
(a title change is one). So a soft addition is right of the real divider, unless its
AX frame lies (R1).

Not done: an item whose title changes reads as a removal plus an addition (tags are titles), so it still retires; membership still changes only at standard length; a member that appears,
or an item read left of the boundary, still shows the hidden items for about a second
(the limit `2026-11-12-hide-at-once.md` already states). The frozen detector and
`Packages/MenuBarCapture` are not touched.

## Tasks (TDD, IceCore)

T1 `PreferenceHidingLayoutChangeTests`: pure removal -> soft; added tag in
`visibleTags` -> soft; added tag not in it -> `itemsChanged`; added tag that is a
member -> `itemsChanged`; members grew -> `itemsChanged`; members shrank by `carried`
with a removal -> soft; display change wins over all.
T2 `PreferenceHidingRosterTests`: boundary set on a trusted pass to the divider's
maxX; kept on an untrusted pass with no removal; cleared by a pass with a removal;
cleared by a display change; `nil` before a trusted pass; removal plus addition in one
pass -> addition not visible; two removals then an addition before a trusted pass ->
not visible; addition after a soft addition still judged against the kept boundary;
an added parked, stacked, frameless or non-finite item not visible; the placeholder
frame (`x7`) not visible; an item with `minX` exactly at the boundary visible, one
point left not.
T3 `IceBarHidingMachineTests`: `structuralChangeRetires` keeps its cases; new: at rest,
a soft item change keeps the length and emits no `setLength`, in both `.standard`
(re-check owed) and `.unverified` (nothing owed); a sequence remove -> add retires on
the add.
T3a Wiring: `updateIceBarRoster` passes the pass's bounds and origin (read in the
diff; the app target has no unit tests); `PreferenceHidingRosterTests`: a pass with
another origin, or other bounds, clears the boundary.
T4 Coverage of the touched IceCore files >= 80%; full `swift test` of IceCore.
T5 App build (`xcodebuild`, Debug, outside `~/Documents`); SwiftLint is CI-only.

## Live check (after the owner's go for the install)

Build the Release candidate as in `2026-11-13-untested-limits.md` section 5 (same
identity and team), archive the installed app, install. With Ice hiding, sacrificial
helpers only (`com.icespike4.*`), `framepoll` recording Ice's divider and the helpers'
frames throughout, and after every event a 1 s capture of the bar (evidence folder,
not the repository):
- Run 1 (build 54aab32+4de4081, 15:08): E2 3 of 3; E1 1 of 3: the second and third
  additions came after a removal had cleared the boundary and retired at 1.4 s, as D2
  as D2 says (`e12-frames*.log`); D2b, an attempt to remove that, was rejected.
- Run 2 (same build, 15:12-15:15): E3 as designed (retire once, new helper drawn at
  `x1222`); E4 the helper seeded left of the divider read `x1132`, the length retired,
  members 4 to 5, hidden again at 1.5 s; its quit retired nothing (members 5 to 4). E5:
  every helper ended drawn (E1 capture, E3 frames) or a member (E4). The IceBar was not
  opened: membership is read from the status log.
- E1 add a helper right of the divider, 3 times: the divider stays at its length; the
  helper's item is drawn on the bar (the capture), so it is not hidden;
- E2 quit it, 3 times: the divider stays at its length; nothing new is drawn;
- E3 quit one helper and launch another within one pass: the divider goes to standard
  length (D2), the new helper ends drawn or listed;
- E4 a helper whose autosaved position is left of the divider: the divider goes to
  standard length, and after the re-hide the helper is a member: Ice's IceBar opened
  by automation lists it (screenshot of the IceBar);
- E5 after E1-E4, every helper is either drawn on the bar or listed in the IceBar
  (no hidden-and-unlisted item; STATUS's earlier regression of that kind was missed by
  length-only sampling).
Pass: all of E1-E5. Rollback: the archived app, by `ditto`.

## Risks

- R1 A new item's AX frame might read right of the boundary while it is drawn left of
  the divider. Not seen (F3, one run); E1 and E4 check both sides. If seen, the soft
  addition is dropped and only D1's pure removal kept.
- R2 One run of F3. Another app or an autosaved position may read differently; any
  reading left of the boundary falls back to today's retire.
