# Ice on macOS 27 — what is actually true

Measured on macOS 27.0 (build 26A428), Xcode 27.0 (27A266a), Apple Silicon,
single 1728x1117 built-in display. Every claim below is tagged with how it was
established. **Treat the tags as load-bearing.** The expensive mistakes in this
investigation all came from an inference being repeated until it read like a
measurement.

---

## The failure

Ice hangs at startup showing "Loading menu bar items…" forever.

That string is not a loading state. `IceBar.swift` renders it whenever the item
cache is empty — no timeout, no error branch. The cache is empty because macOS 27
stopped vending one window per menu bar item: a new system process `MenuBarAgent`
composites the whole bar into a single window at `kCGMainMenuWindowLevel`, and
`Bridging.swift`'s `.itemsOnly` filter discards exactly that window.

**MEASURED.** A probe calling Ice's own private-API path:

```
CGSGetProcessMenuBarWindowList -> err=0 outCount=1
  win=2688 level=24 rect=(0.0, 0.0, 1728.0x33.0) onScreen=true
after Ice's .itemsOnly filter (level != 24): 0 window(s)
```

Consequences reach further than discovery. `MenuBarItem.windowID` is the item's
**handle**, not its identity (corrected 2026-09-23, READ from the code): the
identity Ice compares across passes is `MenuBarItemTag` (namespace + title --
`firstIndex(matching:)`, `address(for:)`, the move timeouts, the temporarily
shown contexts), and nothing third-party is persisted. The window ID is what Ice
*does things with*, and nine places depend on it: `Equatable`, SwiftUI
`ForEach(id:)`, `Bridging.isWindowOnScreen`, `Bridging.getWindowBounds` (three
call sites), `ScreenCapture.captureWindow`, the `uuidCache` keyed by window ID,
and the three `CGEvent` fields the mover writes. On macOS 27 none of them can be
satisfied, and six more callers of `getMenuBarItems` receive `[]` without ever
touching a window ID (plan `2026-09-23-ax-discovery.md`, section 0).

---

## Verified

### Private framework boundary

`MenuBarClientCore` vends four XPC service definitions. Read with
`/usr/bin/dyld_info -exports` (the framework is shared-cache only; there is no
binary or header on disk):

| ServiceDefinition | serviceName | entitlement |
|---|---|---|
| MBHideAttachedAVModule | `com.apple.MenuBarAgent.hide-attached-av-module` | yes |
| MBMenuBarItem | `com.apple.MenuBarAgent.menu-items` | none |
| MBUtilities | `com.apple.MenuBarAgent.utilities` | **`com.apple.private.menubar.utilities`** |
| MBVisibilityRestriction | `com.apple.MenuBarAgent.visibility-restriction` | none |

`entitlement` and `serviceName` are two distinct static properties on the same
struct, so this is not a service name misread as an entitlement. `MenuBarAgent`
imports `MBUtilitiesServiceDefinition.entitlement` as an undefined symbol and its
`__cstring` contains `Connection missing entitlement: %{public}s pid: %d`, so the
server does check. A scan of 356,475 system binaries found zero holders of
`com.apple.private.menubar.utilities`.

**Therefore enumeration through the private framework is closed to third parties,
and Accessibility is the only demonstrated discovery route.** Note the exact
strength of that claim: *demonstrated*, not *provably unique or permanent*.

`MBSystemItemIdentifier` is an `@objc enum : Int` with 9 cases — `init?(rawValue:)`
disassembles to `cmp x0, #8 / cset / ret`. String values: `battery`, `bluetooth`,
`clock`, `displays`, `keyboard`, `primaryBentoBox`, `screenMirroring`, `volume`,
`wifi`. `VisibilityRestrictionAllowList` has a single case,
`.allowing(systemItems: [MBSystemItemIdentifier], bundleIdentifiers: [String])`,
so on that path selection granularity is the **bundle identifier** and two items
from one app cannot be separated.

The visibility-restriction assertion **is** reachable from an unentitled ad-hoc
binary — activated successfully four times, with `MenuBarAgent` logging
`didActivateVisibilityRestriction` and `didInvalidateVisibilityRestriction`. This
works because `MBVisibilityRestrictionServiceDefinition` is the one definition
with no entitlement. That shape reads like an oversight rather than an opening;
do not build core behavior on it.

### Accessibility

Enumeration from zero, no window list required. 18 items, 887 ms cold and
16–21 ms warm. `AXUIElement` is a stable locator inside a process lifetime
(`CFEqual` true across passes). Fingerprints of
`bundleID + AXIdentifier + AXTitle + AXDescription` were identical across three
passes, and every third-party item was distinguishable; the only ambiguity is
among `MenuBarAgent`'s own system items, which share an empty identity. Some apps
expose a real `AXIdentifier` (e.g. `Setapp-MenuBar-Item`).

Attribute surface of a third-party menu bar item, from
`AXUIElementCopyAttributeNames` rather than guessing names:

```
AXRole = AXMenuBarItem        AXSubrole = AXMenuExtra
AXPosition = read-only        AXSize = read-only        AXFrame = not settable
AXWindow = nil                actions: AXPress
```

**AX cannot be written, and third-party items expose no per-item window number.**
Only `MenuBarAgent`'s own items have `AXWindow`. This eliminates both an
AX-native mover and a window-directed event mover.

The menu bar does **not** reorder itself. Sampled once per second for 30 s with no
user input: zero order changes, zero position shifts.

### Discovery through Accessibility, in detail (2026-09-23)

**MEASURED** (read-only census of every running process, several passes 26 min
apart; raw evidence outside the repo, `~/IceReverse-evidence/20260923-105102-axcensus`):

| fact | value |
|---|---|
| extras | 15, from 12 processes; unchanged over three passes |
| `MenuBarAgent`'s children | 4, role `AXGroup`/`AXHostingView`, no identifier, title, description or help -- a frame only |
| app children | 11, all `AXMenuBarItem`/`AXMenuExtra`, one per process |
| identity strings among the 11 | `AXIdentifier` 1, `AXTitle` 1, `AXDescription` 4 (localized), `AXHelp` 2 |
| parked (x 7, y 1105) | 2 of 11 |
| adjacent drawn items at rest | AX frames overlap by **2.0 pt** (every one of 118 pairs in an earlier 59-read run too) |
| element identity | `CFEqual` 15/15 across passes, equal `CFHash` |
| cost | 1 555 ms cold, 20-23 ms warm for the extras reads; a full pass 24-26 ms warm once background-only processes are skipped |
| `AXExtrasMenuBar` errors | `success` 12, `noValue` 87, `cannotComplete` 49 (every one under 50 ms -- an immediate refusal, not a timeout), `attributeUnsupported` 3, `apiDisabled` 1 |

A suspended background-only process (activation policy `.prohibited`) held
every Accessibility request for the full 0.25 s timeout and made every pass
incomplete; none of them owned an item, so discovery skips them (plan
Deviations 2). Checked against per-item labels frozen from a fresh census:
11/11 agree, the negative control fails, the order matches x (plan T6).

**MEASURED on sacrificial helpers** (plan section 6, runs
`20260923-195750-vzdiscover`, `20260923-200220-vzverify`,
`20260923-200409-vzdiscover`, and after the Phase 3 changes
`20260923-210134-vzdiscover`, `20260923-210220-vzverify`, which reproduced
every result below; nothing of the user's was moved, clicked, resized or
written):

- **An `AXIdentifier` set on a status item's button survives an
  `autosaveName`** (plan D9): read back by another process and by the item's
  own process from a background queue while its main thread runs the app, for
  a plain item and for one in Ice's `.noDivider` shown state; two runs.
  About two seconds after launch the autosave name had written no key to
  the helper's own defaults domain.
- **A divider in Ice's `.noDivider` shown state is still in Accessibility**:
  listed, AX frame 2 pt wide on the bar (x 1162.5, y 4.5, 24 pt high), its
  AppKit window 1 pt wide; reached the way Ice reaches it (length 0 from the
  standard length, the width constraint deactivated), one matching
  constraint; two runs. So D10's sections can be computed from the default
  style's collapsed divider; the carry path is not the normal case.
- Hiding an item with `isVisible = false` makes its process answer `noValue`
  for `AXExtrasMenuBar`; shown again, it comes back under the same key, and
  its element is `CFEqual` to the one read before hiding.
- **A new item does not reliably appear at the left end of the bar**: helpers
  launched into a bar whose leftmost item sat at 1094 pt landed at 1143 and
  1171 pt; one process's two items landed at 1066 and 1191 pt, the second
  created left of the first. When a neighbour hides, the items beside it move
  (a user item's glyph was matched 28 pt further right while the target was
  hidden). A detector baseline that reads only the helpers therefore leaves
  the user's items' ink unexplained and the fold unreadable; observing every
  listed item left of them, as the app's check does (plan D15), makes it
  readable (plan Deviation 8).
- Two items of one process with no identifier become two positional keys;
  the detector feed gives them no frame and the check plan skips both.
- Through discovery and `DiscoveredFrameReader`, the 2026-09-19 protocol gave
  its verdicts again: five cycles drawn → `hidden(folded: false)` → restored,
  control (a) `notObserved`, control (b) the hidden target refused; an item
  with an empty identifier was observed drawn.
- **The app's check composes** (`HidingVerification` on a helper, with a
  stand-in for the divider -- a wiring check, not a proof about Ice's
  divider): prepare → hide → verify gave `hidden(folded: false)`; show → the
  baseline was reused → verify gave `stillDrawn`. The two-item section of
  step 6 was not run: there was not enough room on this bar (see below).
- The capture indicator did not appear left of the items in these runs, so
  every room check carried its 41 pt reserve (plan section 6); this is why
  steps 6 and 7 were skipped once each for room.

**What macOS 27 costs Ice, with the plan's changes** -- INFERRED from the code,
Ice not run: moving, clicking and temporarily showing an item are refused on 27
(typed, logged; a click in the search panel does nothing); the layout pane's
rows cannot show item images; `MenuBarAgent`'s elements (the clock, Control
Centre) are not listed; items of apps that refuse Accessibility are not listed;
before the first time a divider has been collapsed for a second after launch,
every item is filed under the visible section.

### Two different kinds of "not visible"

| state | cause | AX frame |
|---|---|---|
| parked | the owning app hid its own item | `x≈7, y≈1104` — outside the bar |
| overflow | the bar ran out of room | still `y<40`, **stacked at the same x as its neighbours** |

Both remain enumerable with identity intact, so hiding does not blind discovery.
But a validity guard of "`minY` < menu bar height means it is on the bar" is
**wrong** for overflowed items. Detecting overflow needs a third criterion.

macOS 27 shows a `«` chevron, owned by `MenuBarAgent`, whenever anything is
overflowing, and removes it when nothing is. This is the whole explanation for a
system item appearing and disappearing during unrelated experiments.

### Hiding by spacing

Ice hides items by expanding its own `NSStatusItem` to `Lengths.expanded = 10_000`
(`ControlItem.swift`), pushing whatever is to its left out of the bar. Public
AppKit API, no private mechanism anywhere.

Measured with this process's own status items only, AppKit-side frames (object
identity unambiguous) plus screenshots of the strip:

```
length    spacer window          menu bar shows
1pt       [1086..1103]           « 1 0 |      one probe already in overflow
600pt     [479..1095]            «            all four of my items in overflow
5000pt    [479..5495]            (not captured)
10000pt   [479..5495]            2 1 0        everything back, « gone
```

`length` is honored linearly until the status area's left boundary (x≈479 with a
7-menu frontmost app), after which the window only extends off-screen to the
right and stops consuming bar space. **At 10,000 the spacer occupies no visible
bar space at all and gives room back instead of taking it.** 5,000 and 10,000
produce an identical window frame, so ~5016 is a clamp — it is *not* "10,000
divided by two", which was a numeric coincidence that briefly passed for an
explanation.

So squeeze-out hiding is alive on macOS 27 and Ice's magic constant is the wrong
value for it. **How wrong, measured:** see "The safe width" below.

### The safe width

**MEASURED** (`docs/macos-27/probes/safewidth`, runs of 2026-09-18; raw evidence
in `~/IceReverse-evidence/`). Sacrificial helpers only: a 12 pt target left of the
spacer, a 12 pt protected proxy right of it, and our own frontmost app supplying
the menus. Pixels decide; AX only explains.

With the spacer resting as Ice rests its own control item, on this display, with
these 15 user items:

| quantity | bracket | read from |
|---|---|---|
| smallest length that overflows the target | (16, 20] | pixels, every path |
| smallest length at which the target leaves the fold (not drawn, no chevron) | (652, 656] | pixels, every path |
| smallest length at which the spacer stops taking room from the bar | (652, 656] | **AX, jump path only** |
| smallest length above that at which the target is visible again | (836, 852] up, (848, 864] down | pixels, staircases |
| smallest length at which the spacer's AppKit width stops growing (≈5016) | (2000, 5000] | AppKit |
| smallest length that costs any item right of the spacer its visibility | **not observed up to 10 000** | pixels |

So `20 < 640`: the interval exists, about **[20, 640] pt**, with ≈ 620 pt of
margin on the scan grid (the finer staircases keep the target overflowed up to
652). It is the same for a frontmost app whose menus end at 72, 440 or 758 pt,
and the same on a jump, an upward sweep and a downward sweep; 300 pt hid the
target on five consecutive toggles of the same items in every config. Hiding
never cost a user item its place: the guard never had to restore anything and
the watchdog never fired. It did stop twice, both times while macOS was sliding
the menu bar through a Space switch, which is the guard refusing to certify a bar
it cannot read rather than anything the spacer did — but the build that ran then
honoured neither stop and kept expanding, up to 10 000 pt, with the guard clean
throughout. Every expansion now goes through one latch.

What bounds that interval from above is one transition at 652–656, seen three
ways: in pixels the target leaves the fold (overflowed at 652; at 656 not drawn
and no chevron), on every path; in AX, on a jump, the spacer is back at its rest
x; in AX, on a staircase, its left edge stops at 368 and stays there. The two AX
readings disagree with each other by path, as AX did in `o0`; that they are one
event is INFERRED from the shared length. The AppKit width saturating at 5016 is
a separate thing, much higher up.

### Squeezing an item out *is* macOS 27's own fold

The user's account of `«`, which matches what the probes measured: it is the
system's fold. When the items exceed the room to the right of the notch they
collapse behind it; expanding restores the bar's full length, running past the
notch to the left.

**MEASURED** (attribution check, every scan run): at the first length where the
target went invisible, quitting the target alone made `«` disappear while the
spacer stayed drawn. The chevron was *our hidden item*. Squeeze-out hiding works
by pushing an item past the boundary right of the notch, and crossing that
boundary is exactly what the fold is — so **a working Ice, hiding this way, shows
`«` whenever it hides anything.** Fixing Ice does not make the new affordance go
away; it summons it.

**MEASURED, mechanism INFERRED:** there is a third state where the target is
hidden with no fold. From 656 pt of spacer length — the step after the last
overflowed length — up to 836 (848 coming down), the target is drawn nowhere on
the strip, no `MenuBarAgent` item appears, and AX still carries the target as a
laid-out item, right of the notch, at an x that renders empty. It is drawn again
at 852 going up and 864 coming down; the staircases' 16 pt steps there put the
switch in (848, 852] both ways.

That AX x is **path-dependent and carries no information about the band**:
jumped to, 984; stepped up to, 1008; stepped down to, 1016 — every reading
settled, zero exceptions across 3 150 band captures in four runs. Coming down,
1016 is what AX reports in the overflowed band, in this band and in the visible
band alike. No path's AX marks the boundary the pixels mark.

Why the item is laid out and not drawn is not established. The candidate that
the spacer's oversized window covers that span in the composite is **refuted**:
going up, the window is (361, 852) at 836 where the target is not drawn and
(361, 868) at 852 where it is — both cover the target's slot, so covering cannot
explain the switch.

That region is the only measured way to hide an item on macOS 27 without raising
the system's fold, so it is worth understanding before any of it is built on:
whether the item is still clickable, whether it survives an app switch, whether
it comes back reliably, and whether the region moves with the number of user
items. Nothing here says it is safe — only that it exists.

**At 10 000 — Ice's `Lengths.expanded` — the target is visible.** The constant is
above the point where the spacer gives the room back, so our spacer at that
length hides nothing, and one inside [20, 640] does. That this holds for Ice
itself is INFERRED: its control item is the same kind of `NSStatusItem`, rested
and expanded the same way, but Ice was not run and its hidden items are the
user's, not a 12 pt helper.

These numbers are for a spacer resting the way Ice rests its own control item
(`variableLength` plus the chevron image), with a 12 pt target and a 12 pt
protected item beside it. That is as much as the ≈ 115 pt free right of the notch
holds: with 16 pt items, or whenever the microphone pill is in the bar (≈ 37 pt),
the target is already overflowed at rest and the spacer has to rest narrower.

Scope, stated plainly: one display, one set of 15 user items, one afternoon, and
the lengths on the tested grid.

### What the screen can be read with (2026-09-19)

All read-only, with nothing of ours in the bar. Raw output, probe sources and
captures: `~/IceReverse-evidence/20260919-winlist-probes/`.

**MEASURED — there are no per-item windows left at all.**
`CGWindowListCopyWindowInfo(.optionAll)` listed 182 and 199 windows at two
instants, and at no layer was there a third-party window shaped like a status
item (height 20–40 pt, width ≤ 200 pt). At level 24 it listed three full-width
`MenuBarAgent` windows and three full-width Window Server windows. So Ice's
image cache is not merely filtered out on macOS 27: the windows it captured are
gone, and `MenuBarItemImageCache` can supply no template here.

**MEASURED — `MenuBarAgent`'s own window captures without a backdrop.** Each of
the three, captured alone with `CGWindowListCreateImageFromArray`, is the bar's
glyphs on a transparent background; the status areas of the three are identical
and their app-menu areas differ; laid over an on-screen capture, every status
item sits at the same x. Whether it tracks the display when an item is folded
behind `«`, or in the 656–836 pt band, is **unmeasured**, and so is which of the
three is live.

**MEASURED — the two capture APIs are not interchangeable in cost.**
`CGWindowListCreateImage` of the bar rect: 5–9 ms warm. ScreenCaptureKit's
`SCScreenshotManager`: 267–412 ms warm, 2.1–2.6 s cold. Both return 3456 × 64 at
scale 2 here. Whether their **pixels** agree is **not established**: the two
captures were ≈ 2 s apart and the backdrop changed between them.
`CGWindowListCreateImage` is deprecated at deployment target 14 and obsoleted at
15, so raising Ice's target means moving to ScreenCaptureKit and re-measuring.

**MEASURED — the bar's backdrop moves under the glyphs.** Two captures ≈ 2 s
apart, with a terminal window under the translucent bar, differed beyond a
24-per-channel tolerance in **17–23 %** of the status area's pixels. A template
that compares backdrop colour is therefore unusable for deciding presence; only
the glyph's own ink and its clear surroundings can carry that.

**MEASURED — capturing the bar changes it.** The first capture of a session moved
the clock's Accessibility x from 1592 to 1589 pt, where it stayed for at least
3 s after the last capture. A violet dot right of the clock appears in the
`screencapture` strips of 2026-09-18 from the second capture onward. The cause is
**INFERRED** to be the screen-capture indicator. The clock is therefore not a
reference for any comparison.

**MEASURED — the microphone pill is 16 pt wide in Accessibility, `«` is 17.5.**
In the baselines of `20260918-194520-c-mid` and `20260918-202302-o1` the pill's
frame is x = 1035, w = 16, while the capture shows it drawn as an orange capsule
≈ 37 pt wide; every chevron reading on record is 17.5 pt. So the two do not
collide by width **on this machine, for this indicator**. A pushed-out pill, the
camera indicator and the screen-recording indicator are unmeasured.

### The detector, run against the real bar (2026-09-19)

**MEASURED**, run `~/IceReverse-evidence/20260919-132726-vzlive`: with two
sacrificial helpers of our own on the bar, the chain — capture, Accessibility,
template, decision — read the target `drawn(x: 1081.5)`, then `notDrawn` with the
fold absent when the helper hid itself, then `drawn` again, five times over, every
reading stable. A third helper drawing the same glyph made the target read
`ambiguous`, an unknown id read `notObserved`, a baseline taken while the target
was hidden cut no template from it, and the five of the user's own items the
monitor watched never moved. Teardown left the bar as it was found.

Three things the bar did to the run, each of which had aborted an earlier attempt:

- **Capturing the bar summons an indicator.** A ≈ 20 pt `MenuBarAgent` item
  appears left of the third-party items while captures are being taken (x ≈ 1143
  here), draws a glyph, and goes again seconds after the capturing stops. Any
  rule of the form "a `MenuBarAgent` item left of the items means `«` or a pill"
  therefore fires on our own instrument. It also flickers: about half of
  consecutive fold readings came back unreadable because it was drawn before
  Accessibility listed it.
- **`NSStatusItem.isVisible = false` removes the item from Accessibility
  entirely.** It is not parked at x ≈ 7, y ≈ 1104, which is what the earlier
  "parked" row of this document describes; there is simply no frame for it.
- **A toggle needs about a second.** An observation started 0.47 s after the
  toggle caught one capture before the change and one after, and was correctly
  refused as unstable.

### What a pixel detector can and cannot template

**MEASURED 2026-09-19** (replay of the 2026-09-18 runs through IceCore's rules,
`docs/macos-27/probes/visibility`): an item whose glyph **fills its own bounding
box** cannot be templated. The rule that decides presence compares where the
glyph's ink is *and* where it clearly is not, and it refuses a cut with too
little clear background, because such a cut matches any patch of ink — including
the item's own vacated slot once the backdrop happens to be ink-coloured. The
sacrificial helpers of 2026-09-18 draw exactly that: a solid two-colour square
(`probes/safewidth/Sources/swhelper/main.swift:36-46`). They are therefore
reported `notObserved`, never hidden and never restored, and the recorded runs
can only exercise the fold, the stability rule and real app icons.

Consequence for Ice: an item drawn as a solid block is outside what this detector
can decide. That is a refusal, not a wrong answer — but it is a real gap, and a
shipped version has to say so rather than report such an item as hidden.

### The move primitive

**Positive control:** a human Command-drag swaps two helper items and the swap
persists. Confirmed by the user.

**Synthetic:** a coordinate-only event stream moves *another process's* item.
Two helper apps with separate bundle identifiers and PIDs, an injector as a third
process, no IPC between them:

```
Command down (flagsChanged) -> leftMouseDown -> 40 x leftMouseDragged -> leftMouseUp -> Command up
every mouse event carries .maskCommand
CGEventSource(.combinedSessionState), posted to .cgSessionEventTap
```

Four rounds, three succeeded: identity unchanged, both items still in the strip,
relative order actually swapped, stable across five samples, reversible. The one
failure aimed only 7pt past the anchor's right edge with other items in between,
and the target advanced one slot without crossing — a drop-point calculation
error, not a missing capability.

**No window ID, no private event fields, no AX writes.**

---

## Open

- **The safe width is characterized on this machine only.** The interval above
  holds for three frontmost menu widths and both sweep directions on one display
  with one set of user items. Untested: other displays and notch geometries,
  multiple monitors, a different number of user items (which is what sets the
  room), the no-divider control-item style, two spacers expanded at once, and app
  switching while the spacer is expanded — the last is the likeliest way a shipped
  version would meet a room it did not measure.
- **AX frames cannot carry this.** They lag a jump by ≈ 0.1 s and, once items are
  overflowed, describe the same visual state differently depending on the path
  taken to it (see Refuted). Anything Ice decides from geometry has to come from
  somewhere else, or be confirmed against pixels.
- **No atomic target binding.** Between reading a frame and pressing the mouse,
  a relayout, a frontmost-menu change, an overflow change or a display switch can
  put a different real icon under that coordinate. Production needs: re-read
  identity and frame immediately before `mouseDown`, verify the hit point is
  unique, verify the layout version is unchanged, cancel on any mismatch, and
  keep a `mouseUp` watchdog and a verifiable inverse.
- **No overflow detector.** See the two-kinds-of-invisible table.
- **Stale comment, deliberately left:** `Packages/MenuBarCapture/Package.swift`
  says the package is "not referenced by Ice.xcodeproj". Since the 2026-09-23
  plan, Ice links it through `MenuBarDetectorFeed`; the package is frozen
  byte for byte (its acceptance check A3), so the comment is corrected here
  instead.
- **Identity across restarts is untested** — app relaunch and `MenuBarAgent`
  relaunch were not exercised. If no identity survives a restart *and*
  distinguishes two items of one app, persistence is unsafe rather than helpful:
  there would be no reliable way to know which item a stored record belongs to.
- **Old paths cannot be verified here.** Only macOS 27 and its SDK are available.
  36 `if #available(macOS 26` sites across 19 files all take the 26 branch on this
  machine, so macOS 26 is as unverifiable as 14 and 15.

---

## Refuted

Kept deliberately. Each of these was stated as a conclusion before it was tested,
and each cost a round of work.

| claim | what actually happened |
|---|---|
| Ice hides items through a private API | It uses `NSStatusItem.length`. The hiding layer was never read before designing its replacement. |
| `MenuBarAgent` reorders items by itself | 30 s of sampling: zero reorders. This false premise was fed into an adversarial review and contaminated its answer. |
| 5016 ≈ 10000/2, so it is the same path | 5,000 also yields 5016. It is a clamp. |
| An out-of-range allowlist caused a system item to vanish | The vanishing item is the `«` overflow chevron. A control run with the old input reproduced nothing. |
| A real third-party item must be moved to test the mover | Two helpers with separate bundles and PIDs answer it without touching the user's menu bar. |
| `persistenceID` / `accessibilityToken` / drag handlers solve identity and movement | They belong to Control Center's own implementation, behind entitlements. |
| Enumeration is closed forever | Closed *today*, for *this* interface. Not a permanence proof. |
| Expanding the spacer is order-dependent: 600pt hid everything from 1pt and nothing when set directly | The run that "hid nothing" saved a screenshot of itself: `«` and no probes — it *had* hidden everything. The claim came from AX and AppKit frames that had not caught up. A replication of that exact topology (`o0`, N=3 per path) finds the pixels identical on both paths at every hold from 0.25 s to 8 s, while AX still describes the two paths differently. |
| An item's AX frame says where it is | For overflowed items it does not. Same pixels, two AX stories; one capture caught the spacer reported at its old x with its new width. |
| The spacer's own window frame tells it whether an expansion hid anything | Only when it was jumped there from rest. Stepped up in place, its x stops moving at the fold and stays there while the target comes *back*: at 852, 868 and 912 the AX x is the same 368 it had at 652, and the target is visible. A length-picking loop that adjusts in place and reads its own frame would call that success. Proposed as the fix for `Lengths.expanded`, refuted before any code was written. |
| `MenuBarItemImageCache` can supply the visual detector's templates | It is always empty on macOS 27, and the per-item windows it captured do not exist at any layer. Stated as the plan for a whole round before the window list was read. |
| Two captures of the same bar differ only where something moved | With a terminal under the translucent bar, two captures 2 s apart differed in 17–23 % of the status area's pixels. A matcher that compares backdrop colour was designed on that assumption and had to be replaced before it ran. |
| Two capture APIs that return the same size return the same pixels | Claimed after one comparison whose two captures were 2 s apart; the difference was the backdrop, not the API. Withdrawn; equivalence remains unmeasured. |
| `MenuBarItemImageCache` can supply the visual detector's templates | It is always empty on macOS 27, and the per-item windows it captured do not exist at any layer. It was the plan for a whole round before the window list was read. |
| Two captures of the same bar differ only where something moved | With a terminal under the translucent bar, two captures 2 s apart differed in 17–23 % of the status area's pixels. A matcher that compared backdrop colour was designed on that assumption and had to be replaced before it ran. |
| Two capture APIs returning the same size return the same pixels | Claimed after one comparison whose captures were 2 s apart; what differed was the backdrop, not the API. Withdrawn — equivalence is unmeasured. |
| A thread of ours can release a system assertion if we crash | It cannot: a thread dies with its process. The spacer survives a crash only because the status item dies with the process too. An assertion held against another process has no such property, and nothing here has tested what happens to one. |

---

## Where this leaves the plan

**The user has stopped the squeeze-out path** (2026-09-19), on the finding above:
hiding this way *is* the system fold, so a working Ice would show `«` for as long
as anything is hidden, and it costs 17.5 pt of the scarce room right of the notch.
That is the opposite of what the feature is for.

Where that leaves the two remaining candidates, stated at the strength the
evidence supports:

- **The no-fold band (656–836 here)** is real but positional, and its boundaries
  were measured at one spacer position. Picking a length inside it on Ice's
  control item needs the same transfer proof that killed the squeeze-out path —
  or a runtime signal that reads, from pixels, whether the item is actually
  drawn. It also cannot be probed for usability without injecting the first
  mouse event this instrument has ever sent.
- **The private visibility-restriction assertion** can be activated from an
  unentitled binary, and that is *all* that has been shown. Its selection
  semantics (the allowlist reads as "only the listed items may appear", so an
  allowlist naming our helper alone would hide the user's items, not ours),
  its behaviour towards items that appear while it is held (the microphone pill,
  a meeting indicator), whether invalidating it restores the bar visually, and
  what happens to it if the holding process dies — none of these is measured.

So the honest statement is **not** "macOS 27 offers no way to hide without the
fold". It is: the public spacer path necessarily raises the fold, and the private
path is callable but unverified on every property that would make it safe for a
bar with the user's own items in it. Establishing those properties belongs in an
isolated account with nothing important in the menu bar, not here.

Common to both candidates, and the reason neither can move yet: **a detector that
decides from pixels whether a given item is drawn**. Discovery through
Accessibility and ordering through coordinate-only `CGEvent` drags with atomic
target binding are unaffected by any of this.

Geometry remains the source of truth for an item's *current* section once an
overflow detector exists. Persistence, if it happens at all, stores *desired*
section against a stable item identity and never overwrites what the user just
dragged — and only after identity across restarts has been demonstrated.

The safe width now exists as a measured interval rather than a hope, and the
overflow detector has a working shape: **the target is absent from the strip and
a new `MenuBarAgent` item is drawing a glyph**. Both came out of
`probes/safewidth`; both are decided by pixels — the detector uses AX only to
say where to look — because AX cannot describe an overflowed item's position.

Next steps, in the order the evidence argues for:

1. **Build the overflow detector first.** Replacing `Lengths.expanded` with a
   number is not enough, and three ways of choosing that number have now been
   refuted in review before any of them was written: a fixed constant (the
   interval was measured at one spacer position and one 12 pt target, and no
   experiment that fits in this machine's ≈ 88 pt of status-item room can show
   it transfers), a formula from the control item's own geometry (fitted to a
   single rest frame; the runs with a different rest frame contradict it), and a
   back-off loop reading the control item's own window frame (refuted by the
   in-place path, see Refuted). Every one of them needs the same missing piece:
   a way for Ice to verify, after expanding, that the items it meant to hide are
   actually not drawn. That detector is item four of this list's older form and
   it is now the prerequisite, not a follow-up.
2. Decide what Ice does when the room is smaller than its own rest width, which
   is the case on this machine.
3. Measure what happens when the frontmost app changes while the spacer is
   expanded: the room changes under a fixed width, and nothing here covers it.
