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
identity, and nine places depend on it: `Equatable`, SwiftUI `ForEach(id:)`,
`Bridging.isWindowOnScreen`, `Bridging.getWindowBounds` (three call sites),
`ScreenCapture.captureWindow`, the `uuidCache` keyed by window ID, and the three
`CGEvent` fields the mover writes. On macOS 27 none of them can be satisfied.

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

| quantity | bracket |
|---|---|
| smallest length that overflows the target | (16, 20] |
| smallest length at which the spacer stops taking room from the bar | (652, 656] |
| smallest length above that at which the target is visible again | (640, 864] |
| smallest length at which the spacer's AppKit width stops growing (≈5016) | (2000, 5000] |
| smallest length that costs any item right of the spacer its visibility | **not observed up to 10 000** |

So `20 < 640`: the interval exists, about **[20, 640] pt**, with ≈ 620 pt of
margin. It is the same for a frontmost app whose menus end at 72, 440 or 758 pt,
and the same on a jump, an upward sweep and a downward sweep; 300 pt hid the
target on five consecutive toggles of the same items in every config. Hiding
never cost a user item its place: the guard never had to restore anything and
the watchdog never fired. It did stop twice, both times while macOS was sliding
the menu bar through a Space switch, which is the guard refusing to certify a bar
it cannot read rather than anything the spacer did.

Three things bound that interval and they are **not** the same event: the
spacer's left edge never plateaus (it returns to its rest x while its window
grows off-screen right), the AppKit width saturates at 5016, and the room is
given back somewhere in (640, 864]. Between ≈ 672 and ≈ 832 the target is
invisible with **no** chevron — neither overflowed nor visible; that region is
not hiding and is not safe to use.

**At 10 000 — Ice's `Lengths.expanded` — the target is visible.** The constant is
above the point where the spacer gives the room back, so on macOS 27 it hides
nothing. A value inside [20, 640] does.

These numbers are for a spacer resting the way Ice rests its own control item
(`variableLength` plus the chevron image), with a 12 pt target and a 12 pt
protected item beside it. That is as much as the ≈ 115 pt free right of the notch
holds: with 16 pt items, or whenever the microphone pill is in the bar (≈ 37 pt),
the target is already overflowed at rest and the spacer has to rest narrower.

Scope, stated plainly: one display, one set of 15 user items, one afternoon, and
the lengths on the tested grid.

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

---

## Where this leaves the plan

Discovery through Accessibility, hiding through Ice's existing spacer once a safe
width exists, ordering through coordinate-only `CGEvent` drags with atomic target
binding. The private visibility-restriction assertion stays a bundle-level
experimental fallback, never the core.

Geometry remains the source of truth for an item's *current* section once an
overflow detector exists. Persistence, if it happens at all, stores *desired*
section against a stable item identity and never overwrites what the user just
dragged — and only after identity across restarts has been demonstrated.

The safe width now exists as a measured interval rather than a hope, and the
overflow detector has a working shape: **the target is absent from the strip and
a new `MenuBarAgent` item is drawing a glyph**. Both came out of
`probes/safewidth`; both are pixel-based, because AX cannot describe an
overflowed item's position.

Next steps, in the order the evidence argues for:

1. Replace `Lengths.expanded` with a width inside the measured interval, not
   10 000 — at 10 000 nothing hides.
2. Decide what Ice does when the room is smaller than its own rest width, which
   is the case on this machine.
3. Measure what happens when the frontmost app changes while the spacer is
   expanded: the room changes under a fixed width, and nothing here covers it.
