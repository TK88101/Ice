# Member order at length (1.1.5)

## Symptom
MEASURED 2026-11-16, macOS 27.2.1, Ice 1.1.4, a 1920 pt external bar active:
every 5 s the hidden items show for about 1 s on both bars and are pushed off
again. Log per cycle: `notVerified(lengthNotApplied,stale:4)` after a pass at
the hiding length, `notVerified(unchecked:5)` about 1.25 s later.

## Cause
MEASURED (read-only AX probe, `ownextras watch`): at the length the hidden
divider stays listed on the wide bar (own read `.ok`, so `BlindAtLength` does
not hold), the rightmost member is squeezed onto the bar and listed, the other
four are pushed off and unlisted.

`PreferenceHidingMembership.resolve(set:...)` does not trust the boundary
(divider not collapsed) and freezes the roster, but its order leaked: listed
members first, missing ones appended. `[A,B,C,D,E]` became `[E,A,B,C,D]`,
`PreferenceHidingLayoutChange.itemsChangeIsVisible` failed on the order, the
change was `.itemsChanged` (structural), the machine retired the length.

On the built-in bar every member and the divider are pushed off: the pass is
blind (1.1.3) and the order never changed.

## Fix
On an untrusted boundary the members keep the previous members' order (any
other after them, in read order); keys, conditions and blockers are the
pass's. A trusted pass keeps the order of the read, so an owner's reorder is
still structural. Debated with Codex in two rounds (converged); an earlier
proposal (widen `BlindAtLength` to `.ok`) was withdrawn: one member is read, and
calling a partial read blind would carry ghost members.

## Tests
- `PreferenceHidingMembershipTests`: untrusted boundary (three states) keeps
  the previous order with only the last member read; a trusted boundary takes
  the read order.
- `PreferenceHidingRosterBlindTests.wideBarPartialReadIsNotStructural`: the
  measured shape; fails without the fix (order and structural), passes with it.
- IceCore: 889 tests green.

## Live check (MEASURED 2026-11-16, 27.2.1)
- 1.1.4, LG active, 20 s: the length retired 4 times.
- 1.1.5 signed Release under the daily identity, LG active: 45 s with no retire;
  24 screenshots of both bars over 12 s showed no hidden item.
- 1.1.5, built-in bar active, 25 s: divider stays off the bar (blind), stable.

## Open
Codex's remaining concern: on an untrusted pass the members' keys and
conditions, `itemTags` and `visibleTags` still update; none is known to make a
structural change, not proven for every shape.
