# Plan — discovery on macOS 27 through Accessibility, and a caller for the detector

Status: **v5.2** (v5.1 + Codex's review, Appendix H) — v3.1's discovery design (reviewed twice and closed, Appendices
C–E) plus the user's decisions of 2026-09-23 (Appendix F): **D10 by divider**,
**D7 Ice verifies, read-only, whether hiding took effect, built this round with
every caller-side workaround**, T9 verified by build + static checks + IceCore
tests, everything approved including the live run. v4's changed parts were
reviewed by three Opus reviewers (55 findings, Appendix F); v5 adopts them.
Codex's quota returned during implementation; its review of v5.1 is Appendix H.

Raw evidence for every claim dated 2026-09-23 is in
`~/IceReverse-evidence/20260923-105102-axcensus/` (sources, outputs, Jev
requests and responses). It is outside the repo on purpose: it lists installed
apps. Nothing from it is copied into the repo.

---

## 0. What this plan starts from

### The failure, restated

"Loading menu bar items…" is rendered by three views whenever
`itemCache.managedItems` is empty: `IceBar.swift:364-370` (checked **before**
`cacheFailed`), `MenuBarSearchPanel.swift:197-198, 253-265`,
`MenuBarLayoutSettingsPane.swift:12-13, 50-57, 83-89`. The cache is empty
because the pass (`MenuBarItemManager.performSetup` → `cacheItemsRegardless`,
`:46-50, 364-423`) gets its items from `MenuBarItem.getMenuBarItems` →
`getMenuBarItemWindows` → `Bridging.getMenuBarWindowList(option: .itemsOnly)`,
empty on macOS 27 (FINDINGS "The failure"), so `ControlItemPair(items:)` finds
no hidden control item and the pass records a failure (`:391-414`).

### What `windowID` does in Ice today

FINDINGS calls `windowID` the item's identity (`FINDINGS.md:29-33`). Read from
the code it is more exactly a **handle**: the identity Ice's logic compares
across passes is `MenuBarItemTag` (namespace + title) — `firstIndex(matching:)`,
`address(for:)`, `moveOperationTimeouts`, `TemporarilyShownItemContext`
(`Extensions.swift:359-361, 693-696`; `MenuBarItemManager.swift:37, 180-189,
1333-1368, 1592-1599`). `windowID` is what Ice *does things with*: bounds
(`Bridging.getWindowBounds`, 4 item sites: `IceBar.swift:147`,
`MenuBarItemImageCache.swift:123`, `MenuBarItemManager.swift:268, 567`),
liveness (`Bridging.isWindowOnScreen`, `IceBar.swift:416, 433`,
`MenuBarSearchPanel.swift:380, 418`), capture (read at
`MenuBarItemImageCache.swift:120, 176`, captured at `:134`), event targeting
(`MenuBarItemManager.swift:1810, 1870-1878`), a `ForEach` id
(`IceBar.swift:377`), `Equatable`/`Hashable` (`MenuBarItem.swift:281-304`), the
`uuidCache` (`:333, 366-370`) and the cache-pass change signal
(`MenuBarItemManager.swift:389, 432`). T10 records this distinction in FINDINGS.

- **Nothing third-party is persisted.** No `Codable` or `Defaults` key on a tag
  or a window ID; the only identity that survives a launch is Ice's own control
  items' `autosaveName` (`ControlItem.swift:15-21, 70`).
- **Six other callers of `getMenuBarItems`** use its result without a window
  ID; on 27 each gets `[]`: `MenuBarItemManager.swift:1432` (temporarily show),
  `:1534` (rehide), `MenuBarManager.swift:185` (hide the app menus when a
  section is shown → `activate(withPolicy: .regular)`, `:299-306`),
  `MenuBarItemSpacingManager.swift:161` (its per-app quit-and-relaunch,
  `:84-97, 166-196`, is inert with `[]`; it still writes the spacing defaults and
  signals Control Center, `:151-157, 200-207`), `LayoutBarPaddingView.swift:81`
  (drag), and the cache pass (`:376`).
- The existing AX code reads *known* items: `LiveMenuBarAXReader.read(items:)`
  keeps only the **first** extra of each pid (`LiveMenuBarAXReader.swift:50`),
  and every existing walk sets the messaging timeout on the application element
  only, which the SDK says does not carry over (`AXUIElement.h:389-390`). The
  walk exists four times already.
- **Ice's own items.** The hidden and always-hidden control items are Ice's
  section dividers; Ice hides by their length (`ControlItem.swift:36-56`,
  `expanded = 10_000`), and the idle state is `.hideSection`, i.e. expanded
  (`:115`). With the default style `.noDivider` a *shown* divider is shrunk to
  length 0 with a 1 pt window, its width constraint deactivated, no image
  (`:337-339, 369-374, 408-428`). The visible control item's image **changes
  with the state** (`:349-352`). Default preferred positions put Ice's icon
  (0) next to the hidden divider (1) (`:646-651`). `@Published var state`
  emits on every assignment, and hiding assigns all three items in order
  visible, hidden, always-hidden (`MenuBarSection.swift:196-205, 219-223`;
  `MenuBarManager.swift:54-57`); in IceBar mode the dividers are re-assigned
  `.hideSection` on every show (`MenuBarSection.swift:164-175`).
- **The detector as it is** (it does not change): a baseline rejects every id
  whose frame overlaps another read id's or an agent frame (strict,
  `StripAssessor.swift:135-139`, `StripImage.swift:66`), and rejects *all* ids
  when the fold at baseline is not `.absent` (`:128-131`), which happens when
  ink with no read frame lies between the notch and the leftmost read frame
  (`:107, 115`; `FoldWitness.swift:119-129`). An observation's fold region runs
  from the notch to the leftmost reference (`:226`), and only matched templates
  explain ink there (`:228-233`). `.stillDrawn` ignores the fold; `.hidden`
  needs it `.absent` (`MenuBarItemVisibility.swift:66-83`). At least one
  reference, templated and stable within ±1 pt in every capture, or everything
  is `captureUnstable` (`CaptureStability.swift:20-28`). A baseline is ≥ 4
  samples over ≥ 3 s (`DetectorParameters.swift:70-74`); `VisibilityObserver`
  is synchronous and sleeps with `Thread.sleep` (`VisibilityObserver.swift:22-58`).
  The `Hiding` and `Unverifiable` enums are part of the frozen detector.

### MEASURED 2026-09-23 — Accessibility on the real bar (read-only)

`axcensus.swift` and `axerrors.swift`: every running app, `AXExtrasMenuBar`, its
children's attributes and frames, the error of every read and its duration;
several passes, 26 minutes apart (148 and 152 processes). No attribute written,
no action performed, **no capture taken**.

| fact | value |
|---|---|
| extras | 15, from 12 processes; unchanged over three passes |
| `MenuBarAgent`'s children | 4, role `AXGroup` / `AXHostingView`; **no** identifier, title, description or help — only a frame (26, 22, 26, 116 pt; the last is the clock) |
| app children | 11, all `AXMenuBarItem` / `AXMenuExtra`, **one per process** |
| identity strings among the 11 | `AXIdentifier` 1 (on a parked item), `AXTitle` 1, `AXDescription` 4 (localized; one names the current input source), `AXHelp` 2 |
| parked (x = 7, y = 1105) | 2 of 11 |
| **neighbours at rest overlap** | adjacent drawn items' AX frames overlap by **2.0 pt** (≈ 6 % of the narrower frame; also every one of 118 overlapping pairs in 59 reads of `20260918-190735-b0`); no item overlaps a `MenuBarAgent` frame at rest |
| element identity across passes | `CFEqual` 15/15 each pass, `CFHash` equal, 0 collisions |
| cost | 1 555 ms cold, 20–23 ms warm **for the extras and children reads only** |
| `AXExtrasMenuBar` errors per process | `success` 12 (children `success`) · `noValue` 87 · **`cannotComplete` 49, every one under 50 ms** · `attributeUnsupported` 3 · `apiDisabled` 1 (while trusted) |

`cannotComplete` is **not** a timeout here but an immediate refusal.

### MEASURED 2026-09-18 and 2026-09-19, re-read for this plan

| state | AX frames and pixels | source |
|---|---|---|
| overflowed behind `«` | overlaps the chevron by 54.3–67.9 % of the narrower frame; two overflowed probes with **identical** frames | `20260918-195745-o0`; `-2000xx/-2015xx/-202525-scan-mid` len 24; `-204150-m-mid` len 20 |
| a status item at 10 000 pt, jump path | AX `x` = its rest x (1012), `w` = **5002**; its `AXIdentifier` (set with `setAccessibilityIdentifier`, no `autosaveName`) read back throughout, by its own process | `20260918-202525-scan-mid`; `swctl` `Spacer.swift:93-94`, `AXReader.swift:61` |
| **the item left of it, same jump** | AX `x` 984 → **1016** once settled (w 14), i.e. right of the expanded item's `minX`; pixels 987.5–995.5 → 1019.5–1027.5, **still drawn**, 32 pt to the right; the same in `-205131-scan-narrow`, `-210852-scan-wide`; `-200028/-201552-scan-mid`: 1012 w 16 against 1014 | same runs |
| the item right of it | AX `x` 1044 and pixels 1047.5–1055.5 at rest, 2 000, 5 000 and 10 000 pt | `-202525-scan-mid` |
| settle after a jump | expand 0.66 s, collapse 0.77 s | same run |
| the capture indicator | ≈ 20 pt `MenuBarAgent` item left of the third-party items; 09-19: at x ≈ 1143 with the leftmost user item at 1184 — **41 pt** of bar consumed | FINDINGS "detector run"; `20260919-132726-vzlive` |
| baselines with the indicator flickering | about half read the fold `unreadable`; the harness retries 5 × 1 s and warms up with 24 captures × 0.25 s | 2026-09-19 Deviations 12, 13; `PreflightCheck.swift:99-106` |

**Not measured:** the AX frame of a status item in Ice's exact `.noDivider`
shown state; the jump path for Ice's own control item; whether AX reports a
button's `setAccessibilityIdentifier` when the item also has an `autosaveName`;
Ice reading its own process over AX from a background queue.

Scope: one machine, one display.

---

## 1. Goal and non-goals

**Goal.**

1. On macOS 27, Ice's item cache is filled from Accessibility, so the three
   views stop saying "Loading…" once a pass has completed; items are placed in
   Ice's three sections relative to Ice's dividers, **computed only while a
   divider is collapsed** and carried while it is expanded (D10).
2. Every status item of every process that answers Accessibility is enumerated
   with a key unique within a pass and — unless marked positional — stable for
   its process's lifetime. `MenuBarItem.windowID` is replaced by a typed source,
   so no window-only operation can be handed an item without a window.
3. **Ice calls the visibility detector** (D7): around a section being shown
   and then hidden on 27, Ice checks, read-only, whether that section's items
   stopped being drawn, logs the result and shows it in the layout pane. It
   changes nothing about hiding. The composition is proven live on sacrificial
   helpers.

**What the user will see on 27, and what it costs.** All INFERRED from the
code: Ice is not run.

- **The check captures the menu bar.** After a section is shown: about 1 s
  settle, 6 s of warm-up captures, ≥ 3 s of baseline, up to 5 retries 1 s apart
  — typically 10–15 s, at worst ≈ 30 s; after it is hidden: 1 s, 6 s warm-up,
  ≥ 0.3 s, retries — typically 7–8 s, at worst ≈ 14 s. A baseline is reused for up to 10 minutes while the frames it was cut
  from are unchanged (D16), so most shows capture nothing. While capturing, a
  ≈ 20 pt `MenuBarAgent` indicator appears left of the third-party items and
  the clock may shift 3 pt (FINDINGS). The check is skipped when the bar has
  under 41 pt free right of the notch, so the indicator is not what pushes an
  item behind `«` (INFERRED — the indicator's placement is from one run).
- **The check will usually not reach a verdict in the default layout.** It
  needs a static reference right of the section and left of Ice's own icon; with
  the default layout (only Ice's icon right of the hidden divider) it reports
  "no reference". Where it does reach a verdict, the likely one on 27 is
  "still drawn" (FINDINGS: at 10 000 pt the spacer hides nothing; INFERRED for
  Ice's divider).
- Hiding, showing, moving, clicking *behaviour* on 27: unchanged where it is
  window-free (the dividers still expand and collapse), refused, typed, where it
  needs a window (`move`, `click`, `temporarilyShow`). **Clicking an item in the
  search panel does nothing** (logged).
- Images on 27: the layout pane's rows say "Unable to display menu bar items";
  the search panel lists items with their apps' icons.
- `MenuBarAgent`'s elements are not listed on 27 — a regression, stated in
  FINDINGS. Items of processes that refuse Accessibility are invisible.
- Sections before the first time a divider is collapsed after launch: every
  item in `visible`.
- A possible system prompt: macOS 15 introduced a periodic re-authorisation for
  apps using legacy screen capture; whether 27 shows it for Ice's check is
  unverified.

**Non-goals.** Any change to the detector — IceCore's `DetectorParameters`,
`Ink`, `StripImage`, `Template`, `TemplateMatcher`, `CaptureStability`,
`FoldWitness`, `StripAssessor`, `MenuBarItemVisibility` — or to **any** file of
`Packages/MenuBarCapture`; `MenuBarItemCacheState` unchanged. Behaviour on
macOS 14–26 (every change is behind `#available(macOS 27, *)`, a rename the
compiler forces, or equal by construction; unverifiable here). `Shared/`,
`MenuBarItemService/`. Running Ice; multiple and non-notched displays (the check
skips them: `BarGeometry` needs a notch, `ScreenGeometrySource.swift:36-41`);
the no-fold band usability test and the composite-window test (separate
approval); expanding any spacer in an experiment; FINDINGS' duplicated Refuted
rows.

---

## 2. Concepts

Competency questions: **CQ1** which status items are on the bar, owned by which
process; **CQ2** is this the item I saw last pass; **CQ3** which section is it
in; **CQ4** can Ice act on it; **CQ5** where is item X now, for the detector;
**CQ6** did hiding a section actually stop its items being drawn.

| concept | definition | identity criterion | boundary |
|---|---|---|---|
| **extra** | one child of a process's `AXExtrasMenuBar` | — | raw material |
| **status item** | an extra with role `AXMenuBarItem`, not owned by `MenuBarAgent` | its **key** | Ice lists it — except Ice's own items other than the visible control item |
| **divider** | Ice's hidden / always-hidden control item, recognised by its `AXIdentifier` (D9) | its identifier | *usable* only with a frame whose `minY` is inside the bar and `minX` in `[bar.minX, bar.maxX)`; never listed |
| **system element** | an extra of `com.apple.MenuBarAgent` | none | never listed; an obstacle in the position rule; the detector's agent frame |
| **key** | namespace + identifier + **pid, always** (+ child index only when one process has two equal identifiers) | namespace = bundle id → localized name → executable name → `pid:<n>` (resolved in IceCore); identifier = trimmed `AXIdentifier` or `""` | depends only on its own process |
| **basis** | how far the key can be trusted | `.declared` · `.unnamed` · `.positional` | `.positional` never names a detector target |
| **tag** (`MenuBarItemTag`) | Ice's existing type | namespace; title = identifier + `/p<pid>` (+ `c<index>`), suffix always present, parsed from the end; Ice's own items: the identifier alone (equal to today's control-item tags) | not persisted |
| **source** | how Ice reaches an item | `.window(CGWindowID)` (≤ 26) · `.accessibility(pid:)` (27) | a handle |
| **position** | what the frame claims | `.onBar` · `.parked` · `.stacked` · `.noFrame` | diagnostic except `.parked` (not listed); never drawn-ness |
| **section (27)** | which side of a *collapsed* divider an item's `midX` lies on | the divider's AX `minX`, read only while Ice's own state says it is collapsed | carried by tag while expanded; arrangement, **not** what is hidden |
| **check result** | one item's result of one verification | `SectionItemCheck` (D17) | never acts |

Constraint enforcement, by tier:

| axiom | tier |
|---|---|
| a window-only operation never receives an AX item | **type** for the `CGWindowID`; **runtime**, first statement, for `move` (item and target), `click`, `temporarilyShow` |
| `.positional` never names a detector target | **runtime + test** |
| system elements are never listed | **type** — a separate array |
| a failed read is not "no items" | **type** for the values; the mapping is a pure, tested function |
| AX never claims drawn-ness | **runtime** — `MenuBarItem.isOnScreen == false` for every 27 item |
| the check never acts | **type** — `HidingVerifier` is constructed from publishers and closures only (no `AppState`, `MenuBarItemManager`, `MenuBarManager`, `MenuBarSection` or writable `ControlItem`); the packages contain no AX write, AX action or event post (A8b) |

---

## 3. Decisions

Two-way doors unless marked. Jev: Appendix B. Reviews: Appendices C–F.

| # | question | chosen | rejected, and why |
|---|---|---|---|
| D1 | how `MenuBarItem` names its handle | **`source: Source`** + `id: ID` (`.window(CGWindowID)` / `.accessibility(encodedKey)`) | a synthetic `CGWindowID`; an optional `windowID` plus a side field |
| D2 | when the AX path runs | **`#available(macOS 27, *)`** | "window list empty" |
| D3 | the key | **always pid-qualified**; child index only for equal identifiers in one process | localized strings; pid only on collision; an element serial |
| D4 | `MenuBarAgent`'s elements | **never listed** | geometry as identity |
| D5 | where the code lives | **`Packages/MenuBarDiscovery`**: `MenuBarDiscovery` (the AX walk) and `MenuBarDetectorFeed` (reader, verification; depends on MenuBarCapture); **Ice links both**; rules in IceCore | inside MenuBarCapture; inside Ice |
| D6 | window-only actions on 27 | **refuse as the first statement** | refusing late |
| **D7** | the detector's caller — **user's decision** | **Ice's `HidingVerifier`**, read-only, with every caller-side workaround of D14–D19 | deferring it to its own plan (recommended by review and Jev; the user chose to build it now) |
| D8 | positions | **parked → not listed**; stacked and no-frame → listed | invalidating on stacked |
| D9 | recognising Ice's dividers | **`setAccessibilityIdentifier(controlItem.identifier.rawValue)`** behind `#available(macOS 27, *)`; discovery reads Ice's own process; the identifiers are passed into IceCore from `ControlItem.Identifier.allCases`, not hard-coded | `autosaveName`; AppKit frames |
| **D10** | sections on 27 — **user's decision: by divider** | each boundary is decided on its own. The **hidden boundary** is known only when Ice's own state has reported the hidden divider collapsed for ≥ 1 s before the pass began, the state is unchanged when the pass ends (a generation counter), and its frame is usable; then an item is `visible` iff `midX ≥ hidden.minX`. The **always-hidden boundary** likewise from the always-hidden divider; then an item left of the hidden boundary (or, if that is unknown, any item) with `midX < alwaysHidden.minX` is `alwaysHidden`. An item left of a known hidden boundary is never `visible` (without a known always-hidden boundary it is `hidden`, or `alwaysHidden` if it was before); an item right of a known always-hidden boundary is never `alwaysHidden`; an item neither boundary decides — or one without a frame — keeps its previous section by tag, and a new one goes to `visible`; with the always-hidden section **disabled** there is no `alwaysHidden` section and such items become `hidden`. Each undecided case is noted with its reason (expanded, settling, missing, unusable, own read failed, identifiers missing). | `midX` against an **expanded** or still-animating divider: refuted by the recorded jump (the item left of it lands at 1016 against 1012, section 0); `findSection`'s edges |
| D11 | what switches to AX | **only the cache pass**; `getMenuBarItems` unchanged | swapping `getMenuBarItems` |
| D12 | the change signal on 27 | **none: the pass runs every tick**; only a changed cache is published | a signature costs the same walk |
| **D14** | references | from the check's own fresh discovery at prepare time — including the divider's `minX`; a divider missing or unusable there → `skipped(.dividerUnavailable)`. Candidates are static items whose **`midX` is right of the divider's `minX`** and left of Ice's icon (no bound when Ice's icon is absent), excluding Ice's icon, dividers and positional items; a caller may pass explicit candidates instead (the harness does); up to two, pairwise non-overlapping after trimming, overlapping no target; a candidate the baseline rejects is dropped; none left → `skipped(.noReference)`, decided from frames **before any capture** when there are no candidates | Ice's icon (changes image with the state); the clock (moves on capture) |
| **D15** | adjacent items and the fold region | **one group**: every item frame handed to the detector is **trimmed by 1 pt on each side** (the measured 2 pt AX padding overlap; agent frames untouched, so the 17.5 pt chevron rule is unaffected); the observed ids are **every listed item left of the leftmost reference** (the verified section's items plus anything else there), so their ink is explained; verdicts reported only for the verified section; stacked items are left out with `skipped(.stacked)`; observed items that the baseline marks dynamic are dropped from the observed set, so one animated item cannot make every target unsettled (their ink then stays unexplained: `.hidden` unreachable, `.stillDrawn` unaffected) | alternating groups (a later group's baseline is refused for the earlier group's ink); one item at a time |
| **D16** | when and how long the check captures | only around a transition: prepare 1 s after a section is shown — warm-up 24 × 0.25 s, then the baseline, retried up to 5 × 1 s while its fold reads unreadable; verify 1 s after it is hidden — warm-up, then the observation, retried likewise; **a baseline is reused** (no capture at the next show) for up to **10 minutes** while the capture geometry is identical (display, point size, scale, notch, origin) and a fresh AX read gives the same frames (± 0.5 pt) for its items, and a verify whose baseline is older than 10 minutes reports `baselineStale`; **skipped** when free room right of the notch — from the leftmost *listed* item, so items of apps that refuse Accessibility make it optimistic — is under **41 pt** (section 0, counted whether or not the indicator is already up), when `Preflight` fails, without a notch, when the bar is hidden by the system, and in IceBar mode (each producing its skip reason in the status line); one session at a time, jobs queued in order, a newer job for the same section replacing a queued or running one; captures stay in memory and are never logged or written | periodic baselines; no reuse (captures on every show) |
| **D17** | the result type | a new IceCore type `SectionItemCheck { checked(Hiding), refusedAtBaseline(Rejection), skipped(CheckSkipReason) }`, `CheckSkipReason` = `noReference, dividerUnavailable, noBaseline(shownSeconds:), baselineStale, noRoom, noGeometry, preflight, iceBarMode, barHiddenBySystem, stacked, positional, notInSection, ownReadFailed, cancelled, captureFailed` (the last added by Deviation 6); sections are IceCore's own `ItemSection` enum, never Ice's `MenuBarSection.Name` | new cases in `Unverifiable` (frozen); collapsing every baseline refusal into `notObserved` |
| **D18** | which transitions trigger a check | a pure reducer over one combined, de-duplicated stream of (hidden state, always-hidden state, always-hidden enabled, IceBar mode, bar hidden by system), initial value handled explicitly: a section entering "shown" → prepare it; leaving → verify it; both dividers in one run-loop turn → one job for the union; IceBar mode or a bar hidden by the system → a `skip` job with that reason; every change supersedes the previous job **of the same section**; the run-loop coalescing is done by the reducer over timestamped snapshots, not by untested glue | one work slot cancelled by every emission (the always-hidden item's redundant emission would cancel every hidden-section check) |
| **D19** | where the check runs | a dedicated serial queue, never the main thread or the cooperative pool; a cancellation-aware capturer and reader wrap the live ones and return `nil` once cancelled, so the observer stops within one sample; a generation token so a cancelled result is never stored; screen, geometry and display origin resolved on the main actor before the hop | `async` over the blocking observer on the pool |

---

## 4. Design

### 4.1 IceCore — rules on plain values (TDD)

New files only; standard library only (pid as `Int32`; trimming by
`Character.isWhitespace`).

**4.1.1 Inputs.** `ProcessInfoRecord { pid: Int32, bundleID?, localizedName?,
executableName?, launchTime: Double?, isSelf: Bool }`. `AttributeRead<T> {
value: T?, error: String }`. `ExtrasRecord { childIndex, role, identifier,
title, description, help, frame: AttributeRead<BarRect> }`. `RawRead { process,
extrasError, extrasElapsed, childrenError?, childrenElapsed?, records }`.
`BarBounds { minX, maxX, minY, barHeight }` (display-local).

**4.1.2 Read outcome** — `ReadClassifier.outcome(raw, timeout)` (timeout 0.25 s;
"slow" = elapsed ≥ 0.8 × timeout):

| read | answer | outcome |
|---|---|---|
| extras bar | `noValue`, `attributeUnsupported`, `invalidUIElement`, `apiDisabled` | `.none` |
| extras bar | `cannotComplete`, fast | `.none` (declines Accessibility) |
| extras bar | `cannotComplete`, slow | `.failed` |
| children | `success` (any count), or `noValue` | `.items` (possibly empty) |
| children | `cannotComplete` fast → `.items([])`; slow → `.failed` | |
| any child's `role`, `identifier` or `frame` | an error other than `noValue` / `attributeUnsupported` | `.failed` |
| anything else | | `.failed` |

`permissionDenied` comes from `AXIsProcessTrusted()` passed to the catalog.

**4.1.3 Keys and tags.** Within one process: identifiers unique → `.declared`
/ `.unnamed`; equal → `.positional`, `c<childIndex>`. `ItemKey.encoded` =
`<len>:<namespace><len>:<identifier>/p<pid>[c<index>]`. Tag title =
`<identifier>/p<pid>[c<index>]`; for the reader's own process the identifier
alone. Uniqueness re-checked on (namespace, tag title) after carry-over; a
residual collision → `identityCollision`.

**4.1.4 Position (diagnostic).** `.noFrame`; `.parked` (below the bar or outside
`[minX, maxX)`, judged by `minX`); `.stacked` (overlaps an on-bar extra — never
one of Ice's own — by more than 25 % of the narrower frame); else `.onBar`.

**4.1.5 Catalog and pass.** `ItemCatalog.build(reads, agentPID, bounds,
isTrusted, ownIdentifiers)` → `DiscoveredItemSet { items (by minX, pid, child;
no-frame last), dividers (hidden?, alwaysHidden?, each with a usability
verdict), visibleControlItem?, ownRead (ok / failed / identifiersMissing),
systemElements, unrecognized, dropped, completeness }`. `carryOver` keeps a
previous item while its process was not conclusively read this pass (a
`.failed` read of any kind, including the discoverer's deadline, which reports
`notAttempted`), its bundle id and launch time are unchanged, and it was last
confirmed by a successful read **at most 30 s ago** (then dropped as `stale`);
it leaves at once when its process is read successfully without it, or is gone
or relaunched; Ice's own records are never carried.

**4.1.6 The 27 cache verdict** — `DiscoveredCachePlan.make(set, dividerStates,
previous)` → `.publish(visible:, hidden:, alwaysHidden:, sectionMap:, notes:)`
or `.keepPrevious(.permissionDenied)`. D10's rule; `dividerStates` carries, per divider, whether it is enabled, whether it is collapsed (`.showSection`), for how long, and whether its state changed during the pass — all from Ice's `ControlItem`; `previous` is the last
published `sectionMap` (tag → section). Parked and dropped left out; each
section ordered by `minX`.

**4.1.7 Verification rules** — pure, in IceCore:
- `CheckFrames.trim(_ frame, by: 1.0)` (D15).
- `CheckPlan.make(sections:, set:, sectionMap:, iceIcon:, explicitCandidates:)` →
  `.skip(reason)` or `.observe(targets: [key], alsoObserved: [key],
  referenceCandidates: [key], skipped: [key: CheckSkipReason])` — D14 and D15
  decided from frames; the divider's `minX` taken from `set`.
- `RoomGuard.hasRoom(set:, notchMaxX:)` (≥ 41 pt).
- `CheckPlan.references(from candidates:, accepted:)` — pairwise
  non-overlapping, none overlapping a target.
- `VerificationTrigger.reduce(previous:, current:)` → jobs (D18).
- `BaselineReuse.isReusable(baselineFrames:, freshFrames:, baselineGeometry:, freshGeometry:, age:)` (D16).
- `SectionItemCheck`, `CheckSkipReason`, and `VerificationSummary.make`
  (counts per case).

### 4.2 `MenuBarDiscovery` target (AX + AppKit; `.macOS(.v14)`)

- `RunningAppsProviding` seam; `ExtrasReading` (one pid → `RawRead`);
  `AXErrorNames` (tested); `LiveExtrasReader`: 0.25 s timeout on the application
  element, the bar element and every child; each call timed with
  `ContinuousClock`; stops a process at its first slow or failed call;
  read-only; no `AXUIElement` leaves it.
- `MenuBarDiscoverer`: every running process **including its own**, starting each
  pass where the previous one's deadline stopped, so a truncation never falls on
  the same processes twice running; processes not reached are reported
  `notAttempted`; a dedicated serial queue; cancellation bridged and checked between processes, the
  deadline between reads; deadline 2 s (+ one call in flight); `nil` when
  cancelled; otherwise the set after `carryOver`, and the duration.
- `mbdiscover` (read-only): the set; `--plan` (4.1.6, dividers taken as
  collapsed only when `--collapsed` is given); `--check <labels>` (T6); the
  comparator in the library, tested.

### 4.3 `MenuBarDetectorFeed` target (depends on MenuBarCapture, MenuBarDiscovery)

- `DiscoveredFrameReader: MenuBarAXReading` — decodes `ItemKey.encoded`;
  matches inside that pid; trims identifiers with IceCore's function and
  **item frames by 1 pt per side** (D15); absent if zero or several match, or
  positional; display origin subtracted; `nil` exactly when the agent cannot be
  read.
- `DiscoveredTargets`: set → `[String: pid_t]`, positional left out, once per
  run.
- `CancellableCapturer` / `CancellableReader`: wrap `StripCapturing` /
  `MenuBarAXReading`; `nil` once a shared flag is set.
- **`HidingVerification`**, seams: capturer, reader, discoverer, geometry
  provider, preflight, sleep, clock, queue. `prepare(sections:, sectionMap:,
  iceIconKey:, explicitCandidates:) -> Prepared` — fresh discovery; `CheckPlan`;
  reuse or: `Preflight.run`, warm-up, baseline with retries (D16); references
  from what the baseline accepted. `verify(_ prepared:) -> [key:
  SectionItemCheck]` — warm-up, observation with retries,
  `MenuBarItemVisibility.hiding(of:in:)` for the section's targets only,
  rejections kept as `refusedAtBaseline`. Everything on its queue (D19). A
  factory `HidingVerification.live(screen:)` builds the live composition, so
  Ice imports `MenuBarDiscovery`, `MenuBarDetectorFeed` and `IceCore` only.
- Stated limits (detector unchanged): `.hidden` cannot be reached when the
  capture indicator's frame differs between baseline and observation, or when
  ink that is not observed lies left of the leftmost reference — a dynamic,
  positional or stacked item, a rejected candidate, an item of an app that
  refuses Accessibility, or a `.chevron`-style divider drawn while shown; every
  target reads `captureUnstable` when Ice's icon changes width between states
  (the icon sets differ, `ControlItemImageSet.swift:59-61`); a solid-block glyph is
  never templated; an item overlapping an agent frame is refused
  (`overlapsAgentItem`).
- Test support: a copy of MenuBarCapture's synthetic-bar fixtures in this
  package's tests (the originals are in a frozen package's test target).

### 4.4 Ice

| site | on 27 |
|---|---|
| `MenuBarItem.windowID` (`MenuBarItem.swift:14`) | → `source` and `id` (D1); on ≤ 26 `id` is `.window(windowID)` |
| new `init(discovered:)` | tag per 4.1.3; `ownerPID = sourcePID = pid`; `bounds` = the AX frame in **global** coordinates (as `getWindowBounds` gave on ≤ 26), `.zero` without one; `title` = first non-empty of title, description, help; **`isOnScreen = false`** |
| new `static func discoverItems(dividerStates:, previous:) async -> DiscoveryResult?` | `MenuBarDiscoverer` → `DiscoveredCachePlan`; `nil` when cancelled; called only by the cache pass |
| `getMenuBarItems` and its six callers | **unchanged** (D11) |
| `Equatable` / `Hashable` / `uuidCache` / `logString` | `source` for `windowID`; window path as today |
| `ItemCache` | `isLoaded: Bool`, set only by the 27 branch; gates read `isLoaded \|\| !managedItems.isEmpty` |
| `cacheItemsRegardless` (`MenuBarItemManager.swift:364-423`) | 27 branch first: reads the two dividers' `state` (main actor), `discoverItems`; `nil` / `Task.isCancelled` → return; `.publish` → an `ItemCache` with the three sections and `isLoaded`, assigned only if it differs, then `commitCachedItemWindowIDs([])`; the `sectionMap` kept and **published read-only** for the verifier; `.keepPrevious` → `recordCacheFailure()`. No `ControlItemPair`, no `enforceControlItemOrder`. The window path is not edited. |
| `cacheItemsIfNeeded` (`:431-436`) | 27 → `cacheItemsRegardless()` (D12) |
| `bestBounds`, `getCurrentBounds` | `switch source`; accessibility → `bounds` / throw `unsupportedSource` |
| `move` / `click` / `temporarilyShow` | first-statement guard (item and, for `move`, target); `click` does not retry; no "file a bug" suggestion |
| `EventError` | `unsupportedSource(MenuBarItem)` |
| `CGEvent.menuBarItemEvent` | takes `windowID: CGWindowID` |
| `IceBar` (`:142-152`, `:364`, `:377`, `:416`, `:433`) | control-item bounds via `source`, **`nil` for an AX item without a frame** (so the bar falls back as today); loading gate; `ForEach(id: \.id)`; on-screen helper `item.source.windowID.map(Bridging.isWindowOnScreen) ?? false` |
| `MenuBarSearchPanel` (`:197-198`, `:253-265`, `:380`, `:418`) | loading gate; loaded and empty → "No menu bar items"; on-screen helper |
| `MenuBarLayoutSettingsPane` (`:12-13`, `:50-57`, `:83-89`) | loading gate; loaded and empty → "No menu bar items"; **on 27 a status line** from `AppState`'s published verification summary ("Hiding did not take effect for N items", "Not checked: <reason>") |
| `MenuBarItemImageCache` (`:189`, `:259-261`) | accessibility items dropped first; nothing left → no capture; the warning at `debug` for accessibility-only sections |
| `ControlItem` (`:70-72`) | behind `#available(macOS 27, *)`: `statusItem.button?.setAccessibilityIdentifier(controlItem.identifier.rawValue)` inside the existing `if let button`. Nothing else changes (A10). |
| new `Ice/MenuBar/Verification/HidingVerifier.swift` | `@MainActor`; initialised from publishers and closures only (section map, timestamped divider inputs, Ice's icon key, a `HidingVerification` (which reads the dividers itself at prepare time)); feeds `VerificationTrigger`, runs the jobs through `HidingVerification`, publishes `lastSummary`; logs per-item results with keys `.private`. |
| `AppState` (`:71-74`) | on 27 builds the inputs from `menuBarManager`, `settings` and `itemManager`, creates the verifier after `itemManager.performSetup`, and publishes its summary for the pane |
| `Ice.xcodeproj` | one `XCLocalSwiftPackageReference` (`Packages/MenuBarDiscovery`), two product dependencies (`MenuBarDiscovery`, `MenuBarDetectorFeed`) on the Ice target |

Untouched and inert on 27 as today: `HIDEventManager`, `MenuBarOverlayPanel`
(`:559`), `SourcePIDCache`, the `MenuBarItemService` connection, the six
`getMenuBarItems` callers, `IceBar.show`.

---

## 5. Tasks

Shape: a serial chain; one implementation worker at a time. Base commit for
every diff check: `af4baf1`. Checkpoint commits on a local `wip/` branch only
(global §1).

| # | task | DoD |
|---|---|---|
| T0 | **done 2026-09-23**, read-only census and error survey | section 0 |
| T1 | IceCore inputs, `ReadClassifier` | every row of 4.1.2; 0.199 / 0.200 s; failed child `identifier` / `role` / `frame` → `.failed`; children `noValue` → `.items([])` |
| T2 | IceCore namespace, keys, tags | byte-identical keys for a survivor across three events; positional within a process; `"x/p12"` vs `"x"`@12; residual collision; own process → identifier-only titles; namespace fallback |
| T3 | IceCore position | census frames; the 2026-09-18 overflow frames; position ≠ drawn-ness pinned; 25 % boundary; Ice's own items never obstacles; parked judged by `minX` (an expanded divider is not parked); origin; no frame |
| T4 | IceCore catalog, `carryOver`, `DiscoveredCachePlan` | ordering; carry while not conclusively read and confirmed ≤ 30 s ago (ten failed or deadline-truncated passes within 30 s still carry; 30.0 s carried, 30.1 s `stale`), removal after a successful read without the item, pid reuse; complete-but-empty; untrusted; own read failed / identifiers missing; divider usability cases; **D10**: collapsed chevron-size divider → split by `midX`; **the recorded jump** (item 984 → 1016 w 14, divider 1012 w 5002, state expanded) → previous sections kept; collapsed for < 1 s, or state changed during the pass → carried; `midX` equal to `minX`; both dividers missing; hidden boundary unknown with the always-hidden one known; always-hidden disabled (previous always-hidden items → `hidden`); new item and no-frame item, with and without a previous section; a previous map from a carried pass |
| T4b | IceCore verification rules | `trim` (2 pt census pairs no longer overlap; agent frames untouched); `CheckPlan`: default layout (only Ice's icon right of the divider) → `.skip(.noReference)`; references pairwise non-overlapping; everything left of the reference observed; stacked → skipped; `VerificationTrigger`: hide assigns all three (always-hidden redundant) → the hidden section verified; show always-hidden → both prepared, one job; IceBar re-assignments → a `skip(.iceBarMode)`; drag start (the disabled always-hidden item set shown); emissions while always-hidden is disabled; initial state; rapid toggling; `CheckPlan` with **step 5's geometry** (divider `minX` = the target's `maxX`, the reference's raw `minX` = that − 2) → the reference is a candidate by `midX`; `RoomGuard` at 40.9 / 41 pt; `BaselineReuse` (± 0.5 pt, 10 min, and each geometry field changed → not reusable); `VerificationSummary` |
| T5 | `MenuBarDiscovery` | fakes: own process read; cancellation → `nil`, previous set kept; deadline; never on the main thread; comparator fails on a wrong label |
| T6 | **E2E, read-only** | fresh census → per-item labels hashed first → `mbdiscover --check` → negative control → census again (void and repeat on drift, ≤ 3) → `--plan` sections, ascending x → full pass timed (> 50 ms warm → deviation, D12 revisited) |
| T7 | `MenuBarDetectorFeed` | reader as v3.1 plus trimming; `HidingVerification` over fake capturer / reader / discoverer on the copied fixtures: two adjacent inked targets (2 pt overlap) → both checked; a reference rejected at baseline → the other used, none → `noReference`; a rejected candidate nearer than the accepted one → a hidden target reads `checked(.unverifiable(.foldUnreadable))`, pre-registered; a dynamic observed item dropped and the targets still settled; a `foldNotAbsentAtBaseline` target → `refusedAtBaseline(.foldNotAbsentAtBaseline)`; an inked non-observed item left of the reference → `.hidden` not reported; a target moved 32 pt with its AX frame → `.stillDrawn`; an indicator frame that moved → `.stillDrawn` kept, `notDrawn` → `unverifiable(.foldUnreadable)`; baseline retries; reuse; cancellation stops captures within one sample; never on the main thread; one session at a time; a cancelled result never stored |
| T8a | live stage built: `vzhelper` options (`--items N`, `--identifiers`, `--glyphs` incl. `alt`, `--mimic-nodivider` reproducing `ControlItem.swift:337-339, 369-374, 408-428` exactly, recording its own AppKit frame), `vizprobe discover` and `vizprobe verify` stages, the probe package's dependency on MenuBarDiscovery, a raw AX read for `CFEqual` | builds; dry runs; glyphs pairwise distinct |
| T8b | **live run** (section 6) | every expectation, or a pre-registered skip or recorded outcome with its reason; helper domains empty; safety monitor quiet |
| T9 | Ice changes of 4.4 | `xcodebuild` succeeds; A8, A8b, A10 |
| T10 | Docs: FINDINGS (section 0's MEASURED facts; handle vs identity; the 27 regressions; the `.noDivider` result; the verifier's live results; MenuBarCapture's "not referenced by Ice.xcodeproj" comment is now stale, left unedited by A3), probes README, this plan's ledger | tagged; no evidence row copied |

---

## 6. Live protocol (T8b)

Existing bundle ids only (`com.icespike4.target`, `com.icespike4.protected`);
never an `autosaveName` except in step 10; `defaults delete` of a helper's
domain before every launch. Glyphs `target`, `reference`, `alt`, pairwise distinct. **Room**,
measured live before each launch: ≥ 30 pt × items about to be launched +
17.5 pt, + 41 pt if the capture indicator is not already present; short → the
step is skipped and reported. Any `«`, unexpected verdict or safety-monitor
event → quit every helper, stop, report; no retry — except outcomes
pre-registered below as *recorded*. **No spacer is expanded; no mouse event is
injected.**

1. Preflight and baseline: the 2026-09-19 plan, 6.1 step 1 only; free room;
   `MenuBarAgent`'s defaults snapshot (read-only).
2. Launch reference (`reference`), then target (`target`). Discovery: both
   `.declared`, owned by the pids just launched.
3. Targets fixed once; the 2026-09-19 five-cycle protocol (6.1 steps 4–6
   without control (c)) through `DiscoveredFrameReader`. Verdicts as then.
4. `hide` / `show` the target: raw `AXError`s recorded; absent, then back under
   the same key; `CFEqual` recorded (MEASURED).
5. **Verification wiring** (composition only — not a proxy for a divider
   expansion): `HidingVerification` with the target as the section and the
   reference as the only candidate, the helper's own `isVisible` as the "hide",
   passed as explicit candidates, with the target's `maxX` standing in for the
   divider's `minX`, 1 s settle: `prepare` → `hide` →
   `verify` → **`.hidden(folded: false)`**; `show` → reuse → no hide → `verify`
   → **`.stillDrawn`**. Recorded, not a stop: `refusedAtBaseline(.foldNotAbsentAtBaseline)`
   after all retries, or `unverifiable(.foldUnreadable)`.
6. Quit the target; the reference stays. One helper under the target's id,
   `--items 2 --identifiers vz-a,vz-b --glyphs target,alt`: two `.declared`
   items of one pid. **(a)** The non-first child observed `drawn` at its own x
   (pre-registered skips: the frames still overlap after trimming, or the old
   first-extra reader's frame equals the non-first child's). **(b)** The two
   items as one section, adjacent, trimmed, the reference as the only
   candidate, the right item's `maxX` standing in for the divider's `minX`:
   `prepare` → quit the helper (both gone) → `verify` → both
   **`.hidden(folded: false)`**; the same with no quit → both **`.stillDrawn`**
   (relaunched, same ids). Recorded, not a stop: the fold outcomes of step 5.
7. Same helper with `--identifiers none`: two `.positional`; child order
   against x recorded; the feed returns no frame; `CheckPlan` → `skipped(.positional)`.
   Quit it.
8. One helper, `--items 1 --identifiers none --glyphs target`: `.unnamed`;
   observed `drawn`. Quit it.
9. **`.noDivider` (MEASURED, no expectation):** one helper with
   `--mimic-nodivider --identifiers vz-zero`: whether discovery lists it, its
   AX frame, and its own AppKit frame. Quit it. Pre-registered skip: the helper
   cannot find the width constraint to deactivate. This decides whether D10's
   carry path is the normal one for the default style.
10. **Identifier with `autosaveName`, read by the helper itself (MEASURED;
    decides D9):** one helper whose item has **both** an `autosaveName` (`vz-autosave`, written only to the
    helper's own domain, deleted before and after) and
    `setAccessibilityIdentifier("vz-ident")`, as Ice's control items will:
    whether `AXIdentifier` reads back `vz-ident` — once from the harness, once
    **by the helper itself, in-process, from a background queue** while its
    main thread runs the app (Ice must read its own dividers that way); then the
    same with
    `--mimic-nodivider`. If it does not read back, D9 fails and the cache path
    falls to D10's carry case permanently — reported as a blocker for the
    sections, not worked around. Quit it.
11. Teardown: quit the reference; `defaults delete` for both domains; the
    emptied plist files left in place; `MenuBarAgent`'s defaults compared with
    step 1 (evidence for that one domain only).

---

## 7. Acceptance

| # | check | how |
|---|---|---|
| A1 | IceCore green; line coverage ≥ 80 %; only the standard library | `swift test --enable-code-coverage --scratch-path <outside ~/Documents>`, `llvm-cov report`; the 2026-09-19 import grep |
| A2 | `MenuBarDiscovery` green; ≥ 80 % excluding `LiveExtrasReader` and `main.swift` | same |
| A2b | `MenuBarDetectorFeed` green; ≥ 80 % excluding the `live` factory | same |
| A3 | MenuBarCapture byte-identical | `git diff --exit-code af4baf1 -- Packages/MenuBarCapture` |
| A4 | the detector's IceCore files and `MenuBarItemCacheState` unchanged | `git diff --exit-code af4baf1 -- <those files>` |
| A5 | discovery agrees with frozen labels | T6 |
| A6 | live run | the run's JSONL |
| A7 | Ice builds | `xcodebuild … build` outside `~/Documents` — builds, does not run |
| A8 | no window-only operation can receive an AX item | the expected-hit table of `grep -rnE 'getWindowBounds\|isWindowOnScreen\|captureWindow\|setWindowID\|windowID' Ice/`, written before T9, matched exactly after; no stored `windowID` on `MenuBarItem`; the guards are first statements |
| A8b | the check cannot act | each of these must **exit 1** (no match): `grep -rqE 'AppState\|MenuBarItemManager\|MenuBarManager\|MenuBarSection' Ice/MenuBar/Verification`; `grep -rn 'ControlItem' Ice/MenuBar/Verification \| grep -v 'ControlItem\.HidingState'` (checked for empty output); `grep -rqE 'AXUIElementSetAttributeValue\|AXUIElementPerformAction\|CGEvent\|\.post\(\|\.isVisible *= *[^=]\|\.length *= *[^=]' Packages/MenuBarDiscovery/Sources/MenuBarDiscovery Packages/MenuBarDiscovery/Sources/MenuBarDetectorFeed Packages/MenuBarDiscovery/Sources/mbdiscover Ice/MenuBar/Verification` — the package's every target directory, listed so a new target cannot slip past |
| A9 | probes build; SafeWidthCore 277 green | `build.sh`; `swift test` in `probes/safewidth` |
| A10 | nothing under `Shared/` or `MenuBarItemService/` changed; `ControlItem.swift`, `AppState.swift` and the layout pane changed exactly as pre-written | `git diff --exit-code af4baf1 -- Shared MenuBarItemService`; `git diff -U0 af4baf1 -- <file> \| grep -E '^[+-][^+-]'` equals the expected-lines file written before T9 |

Not observable by any check here: what Ice on 27 renders and what its check
reports on the user's bar. `mbdiscover --plan --collapsed` and T8b steps 5–6
are the closest proxies. The rest is INFERRED until the user runs Ice.

---

## 8. Risks and rollback

| risk | response |
|---|---|
| a hung app | reads bounded per element; the pass by 2 s + one call; its items carried ≤ 30 s since last confirmed, then dropped as `stale`; the rotating walk reaches every healthy process at least every other pass |
| the first pass (≈ 1.5 s cold) | "Loading…" for about that long — INFERRED |
| `IceBar.show` awaits a pass | ≤ ≈ 2.25 s worst case |
| polling ≈ 100 processes per tick may wake napping apps | unmeasured; T6 times a full pass |
| **the check captures the user's bar** | section 1 states the durations; reuse, the room guard and one-session-at-a-time bound it |
| **the check rarely reaches a verdict** (no reference in the default layout; fold unreadable when the indicator moves) | reported per reason in the status line; never shown as hidden |
| Ice's divider behaves unlike the recorded helper spacer | sections are computed only while collapsed; the check reports what is drawn regardless |
| a `.noDivider` shown divider is absent from AX | D10's carry path; T8b step 9 measures it |
| AX drops the button identifier when an `autosaveName` exists | `ownRead = identifiersMissing` → carry path, logged and shown |
| the legacy screen-capture re-authorisation prompt | unverified on 27; stated in section 1 |
| Ice's deployment target | shipping `CGWindowListCreateImage` through the feed keeps Ice at 14; raising it to 15 needs a new capture path (`LiveStripCapturer.swift:20-25`) |
| positional keys | never detector targets |

Rollback: additive except the Ice changes of 4.4 (one commit) and the pbxproj
reference; `git revert` undoes each.

## 9. For the user

**Decided on 2026-09-23:** D10 by divider; D7 Ice verifies, read-only, whether
hiding took effect, built now with every workaround; T9 verified by build +
static checks + IceCore tests; everything approved, including T8b.

**What that implies:** section 1 lists it — capture durations and the
indicator, "no reference" in the default layout, sections only from collapsed
dividers, the unverified re-authorisation prompt. `ControlItem.swift` gains the
identifier lines (27 only).

**Before any push:** `docs/macos-27/probes/visibility/labels.json` (commit
`30ab8b0`, local only) contains installed apps' bundle ids — your call.

**Not done unless asked:** FINDINGS' Refuted table repeats three rows.

Reminders: the raw evidence is in `~/IceReverse-evidence/`, not in the repo;
the appendix of `2026-09-18-safe-width.md` holds five rounds of settled debate,
not reopened here; Codex's weekly quota is exhausted — Opus and Jev, not Codex.

## 10. Recorded for later

- Images on 27: display images and templates cut from the strip at AX frames.
- A coordinate-only mover with atomic target binding (FINDINGS "Open").
- A hiding mechanism that works on 27; the check is how it will be judged.
- A reference that exists in the default layout (the detector's rules would
  have to accept one; separate decision).
- Identity of `MenuBarAgent`'s elements, if a string ever appears.
- Four copies of the AX walk.

---

## Appendix A — the map this plan was built from

Six read-only readers and a completeness critic (workflow `wf_356fbec8-861`):
159 raw `windowID` hits; the critic added ten sites. A map built from
`windowID` hits could not see callers that consume `getMenuBarItems`' result;
review found them (section 0), and D11 leaves all six as they are.

## Appendix B — Jev's judgments

`jev-1.13.0`; requests and responses in the evidence directory; checked to
contain no app names or bundle ids. Options described neutrally.

| # | Jev's choice | p | = plan |
|---|---|---|---|
| D1 | enum source | 0.84 | yes |
| D2 | OS-version gate | 0.64 (empty window list 0.35) | yes |
| D3 | identifier only | 0.98 | yes (v3 always adds the pid — review, not Jev) |
| D4 | exclude system elements | 0.99 | yes |
| D5 | new package, rules in core | 0.98 | yes |
| D6 | typed refusal | 1.00 | yes |
| D7 | discovery-backed reader + harness | 1.00 | **no** — the user chose a caller in Ice (Appendix F) |
| D8 | skip non-on-bar | 0.98 | revised by review (only parked) |
| D9 | set own identifier | 0.99 | yes (needed again under D10 by divider) |
| D10 | flat visible | 0.98 (by divider 0.01, last rest 0.01) | **no** — the user chose by divider; v5 computes it only from collapsed dividers (Appendix F) |

Per-requirement conflict checks (96 nouls; near 0.5 = undecided). Above 0.7:
**D6 × "fill the list" 0.81** — refusing actions does not affect filling the
list, but it names a real consequence (a click in the search panel does
nothing on 27), now in section 1; **D10 by-divider × "geometry is not
identity" 0.81** — agrees with the recommendation. The combined "breaks any
requirement?" form (0.26–0.74) was replaced by one question per requirement,
the indirection Jev is documented to handle poorly.

## Appendix C — review of v1 (four Opus reviewers, 62 findings)

| issue | ruling |
|---|---|
| `.stacked` at 0.5 pt would stack 5 of 9 drawn items (all four, P0) | **adopt** → threshold from recorded frames |
| Ice's idle state is expanded; v1 would keep "Loading…" (all four, P0) | **adopt** → D10 |
| swapping `getMenuBarItems` wakes the app-menu handler and the spacing manager (three) | **adopt** → D11 |
| order and display filter unspecified; parked items leak in | **adopt** |
| `findSection`'s strict edges | moot under D10 flat; **under by-divider (v4+) replaced by `midX` against a collapsed divider's `minX`** |
| an incomplete pass empties the cache | **adopt** → carry-over (bounded in v3) |
| `cannotComplete` as failure | **adopt, measured** → duration decides |
| discovery on main; self-read | **adopt** → own queue, own pid skipped; **reversed in v4**: by-divider needs Ice's own dividers, so discovery reads its own process (from a dedicated queue; a failed own read degrades to carrying sections, D10) |
| D9 unmeasured | **evidence found** (swctl's spacer) |
| `AXUIElement` exposure | **adopt** → none leaves the reader |
| generic cache state; signature churn | **adopt** → D12 |
| `isOnScreen` as drawn-ness | **adopt** → false on 27 |
| late refusal; `enforceControlItemOrder` | **adopt** → D6; no `ControlItemPair` on 27 |
| capture with no windows | **adopt** |
| anchor errors | **adopt** |
| tag encoding | **adopt** (completed in v3) |
| Ice-side rules untested | **adopt** → `DiscoveredCachePlan` |
| live room and `«` | **adopt** (completed in v3) |
| ordinals across processes | **adopt** (completed in v3: always pid) |
| `.soleItem` defined twice | **adopt** |
| display origin | **adopt** |
| namespace in untested code | **adopt** |
| MenuBarCapture's `Package.swift` | **adopt** → the feed moved out |
| deleting FINDINGS rows | **adopt** → not done |
| E2E oracle | **adopt** (completed in v3) |
| live run not discriminating | **adopt** (completed in v3) |
| A8 and `git diff` base | **adopt** (completed in v3) |
| "ship T0–T8 only" | **reject** — re-raised narrowly in round 2, see D |
| element serial by `CFEqual` | **reject** — accepted by all three round-2 reviewers |

## Appendix D — review of v2 (three Opus reviewers, 45 findings)

Rejected items fed back first. **Element serial**: not re-raised by anyone —
the rejection stands. **"Ship T0–T8 only"**: re-raised with a new argument —
T9 can only ever be verified by a build (no test target, Ice not run), which
the user's DoD §9 does not count as done, and T9 forks on the still-open D10.
**The reviewer wins on that narrowed point**: T9 stays, waits for D10, and
section 9 asks the user to accept its verification (item 3).

| issue (reviewers) | ruling |
|---|---|
| keys still flip: pid added only on collision (identity F1, scope R1, both P1) | **adopt** → always pid (D3, 4.1.3); T2 pins byte-identical keys across three events |
| the feed cannot recompute cross-process uniqueness (identity F2) | **adopt** → decode and match inside the pid |
| timeout only on the first call; the rest use the global default (code F2, identity F3) | **adopt** → per element, monotonic timing, 2 s pass deadline |
| children and attribute errors unclassified (identity F4) | **adopt** → 4.1.2 rows; hidden helper's errors recorded in section 6 step 4 |
| cancelled pass committed; previous set overwritten (code F3) | **adopt** → `nil`, `Task.isCancelled`, previous set kept |
| the 27 branch republishes every tick (code F4) | **adopt** → assign only when changed |
| complete but empty still "Loading…" (code F1, identity F13) | **adopt** → `ItemCache.isLoaded`, three gates, "No menu bar items"; `MenuBarLayoutSettingsPane` joins 4.4 |
| carry-over unbounded, after the re-check, pid reuse (identity F5, code F7) | **adopt** → ≤ 3 passes, launch time, re-check after carry |
| Ice's tag not injective (code F7, identity F10) | **adopt** → always-present suffix parsed from the end; re-check on (namespace, title) |
| live steps 5–7 have no reference; twin glyphs; child order assumed (identity F6–F7, scope R2) | **adopt** → reference kept, per-item glyphs, target chosen at run time, discriminating condition |
| room checks unsized; control (c) overflows (identity F8) | **adopt** → per-step room formula; control (c) dropped |
| T6 labels are stale counts; the verdict could be excused (identity F9, scope R8) | **adopt** → per-item labels from a fresh census, hashed, void-and-repeat, negative control, labels outside the repo |
| `permissionDenied` from `apiDisabled` counts (identity F11) | **adopt** → `AXIsProcessTrusted` |
| `.stacked` has no consumer (identity F12) | **adopt** → diagnostic; obstacles on the bar only; position ≠ drawn-ness pinned |
| feed coverage row; error-name mapping untested (identity F15) | **adopt** → A2b, `AXErrorNames` |
| `pid:` namespace reuse; ties (identity F16) | **adopt** → launch time in carry-over; tie case in T4 |
| `CFEqual` needs a raw read (identity F17) | **adopt** → the harness's own read (T8a) |
| plist deletion (identity F14, scope R6) | **adopt, the other option** → domains emptied, files left |
| A8 cannot pass as written (code F6, scope) | **adopt** → the expected-hit table |
| `pid_t` and trimming need Darwin / Foundation (code F8) | **adopt** → `Int32`, stdlib trimming |
| `move`'s target item refused late; "file a bug" text (code F9) | **adopt** |
| a capture path bypasses `updateCache` (code F10) | **adopt** → filter in `captureImages(of:)` |
| wording (code F11) | **adopt** |
| cost only of the first two reads; napping apps (code F12) | **adopt** → full pass timed in T6 with a threshold; wake-up cost recorded as unmeasured |
| `ForEach` id changes identity on ≤ 26 (code F13) | **adopt** → `id` keeps the window number there |
| log-once never re-arms (code F14, scope R9) | **adopt** → commit on success |
| `IceBar.show` waits for a pass (code F5) | **adopt, the stated-risk option** → §8; `IceBar.show` untouched |
| D10's reasons partly wrong; strongest reason missing (scope R3) | **adopt** → D10 and section 9 rewritten |
| verification of T9 not put to the user; T9 not gated on D10 (scope R4) | **adopt** → section 9 item 3; T9 after D10 |
| behaviour changes missing from the approval list (scope R5) | **adopt** → listed; T8 split into build and run |
| honesty slips (scope R7) | **adopt** → INFERRED tags; Goal narrowed; FINDINGS 29-33 in T10 |
| D7 omits the capture cost (scope R10) | **adopt** |
| `labels.json` in `30ab8b0` lists installed apps (scope R8) | **raised to the user** (section 9) |

## Appendix E — closing check of v3 (one Opus reviewer)

No P0. Two P1, both text fixes, adopted: step 5 would have drawn the reference
glyph twice (the running reference and the helper's second item), so both would
be rejected as not unique and the run would stop — a third glyph `alt` added;
and `isLoaded` had no site on the window path, where setting it after the
equality guard would republish every pass — it is now set only on 27 and the
gates read `isLoaded || !managedItems.isEmpty`, equal to today on ≤ 26 by
construction. Also adopted: the reader stops a process at its first slow call
and the worst-case bound is restated; trust and zero-read cases moved from T1 to
T4; targets fixed once per run; the feed's dead child-index match removed and
its trimming shared with IceCore; dangling "6.1" references fixed; the
image-cache log site named; room measured live, with the indicator counted only
when absent; `defaults delete` before every launch; the `MenuBarAgent` defaults
comparison stated as one-domain evidence only.

## Appendix F — the user's decisions of 2026-09-23 and the review of v4

**Decisions.** Against the plan's recommendations the user chose **D10 by
divider** and **D7 a caller inside Ice**, for **read-only verification of
whether hiding took effect**. T9's verification by build and static checks was
accepted and every approval item granted, including the live run. After the
review below showed that, with the detector unchanged, the check would mostly
answer "cannot be checked" in the default layout and captures the bar for
seconds per transition, the user was asked again and chose to **build it this
round with every caller-side workaround** (recommended: defer; Jev: defer 1.00,
but deferring breaks the user's request 0.71). Jev on D13–D16 of v4: keep
previous sections by tag 0.94, visible-section static references 1.00,
non-overlapping groups 0.90, captures only around transitions 0.93.

**Review of v4** (three Opus reviewers, 55 findings; workflow
`wf_6092772a-39e`). The user's decisions were not re-argued. Rulings:

| issue | ruling |
|---|---|
| `midX` against an **expanded** divider misfiles the item beside it — the recorded jump moves it from 984 to 1016 against 1012 and it stays drawn (V1, P0) | **adopt** → D10: sections only from dividers Ice reports collapsed; carried while expanded; T4 pins the recorded frames |
| the outcome type cannot hold `noReference`, `noBaseline` or baseline refusals without changing frozen `Unverifiable` (V4, F1, F5) | **adopt** → D17 `SectionItemCheck`, a new IceCore file |
| alternating groups: a later group's baseline is refused for the earlier group's ink (V2, F2) | **adopt** → D15: one group, frames trimmed 1 pt per side, everything left of the reference observed |
| the fold region holds other sections' and Ice's icon's ink (V3, F2) | **adopt** → D14 (references left of Ice's icon), D15 (observe everything left of the reference), stated limits in 4.3 |
| references: adjacent candidates reject each other; circular acceptance; no source for the divider's `minX`; the default layout has only Ice's icon (V5, F3, F4) | **adopt** → D14: fresh discovery at prepare, pairwise non-overlapping after trimming, per-baseline acceptance, `noReference` decided from frames before capturing; default-layout outcome stated in section 1 |
| one work slot cancelled by the always-hidden item's redundant emissions (V6, F2 sections, F1 scope) | **adopt** → D18, a tested reducer |
| the indicator flickers; no retry; `.hidden` unreachable if it moves; it may fold an item (V7, F6 scope) | **adopt** → D16 retries, room guard (41 pt, measured), limits stated |
| unbounded prepare; `noBaseline` likely; baseline age (V8, F6) | **adopt** → D16 reuse ≤ 10 min, `noBaseline(shownSeconds:)`, `baselineStale` |
| T8b step 5 is wiring only; the moved-but-drawn path is not exercised live (V9) | **adopt** → labelled; step 6(b) exercises two adjacent targets live; the moved path pinned in T7 and INFERRED live |
| T7 cannot tell a right composition from a wrong one (V10) | **adopt** → T7's case list |
| 1 s settle (V11) | **kept** — recorded 0.66 / 0.77 s; the warm-up adds more |
| type name `CGWindowListStripCapturer`; no notch → no geometry (V12, F12 scope) | **adopt** → `noGeometry`, display scope stated |
| synchronous observer, cancellation, threads (V13, F5, F7 scope) | **adopt** → D19 |
| divider usability and the missing / failed cases (F7 sections, F9 scope) | **adopt** → D10 cases, T4 |
| the verifier's inputs and "acts" guarantees (F8 sections, F4 scope, F14 scope) | **adopt** → publishers and closures only; A8b as an allowlist plus a package grep; `Preflight` before capturing |
| IceBar positioning with a frameless AX item; coordinate space (F9 sections) | **adopt** → `nil` bounds; global coordinates stated |
| only the hidden divider missing (F10 sections) | **adopt** → each boundary independent |
| identical frames and greedy grouping (F11 sections) | **moot** with one group; stacked items skipped |
| spec slips: type name, `HidingPlan` home, snippet variable, hard-coded identifiers, imports, pane redraw (F12 sections) | **adopt** |
| capture cost understated; no room guard; no rate limit (F3 scope) | **adopt** → section 1, D16 |
| `--length 0` does not reproduce Ice's `.noDivider` state (F8 scope) | **adopt** → `--mimic-nodivider` mirroring `ControlItem.swift` exactly |
| A10 is not a check (F10 scope) | **adopt** → expected-lines files |
| linking MenuBarCapture: stale comment, deployment target (F11 scope) | **adopt** → T10 records the comment; section 8 row |
| stale appendix rows; the own-pid reversal unrecorded (F12 scope) | **adopt** → Appendices B and C updated |
| test seams and fixture copies (F13 scope) | **adopt** → 4.3 seams; fixtures copied |
| 41 pt unsourced (F15 scope) | **adopt** → sourced in section 0 |
| per-item logs name installed apps | **adopt** → `.private` |
| the legacy screen-capture re-authorisation prompt (scope risk) | **recorded** — section 1 and 8, unverified |

## Appendix G — closing check of v5 (one Opus reviewer)

No P0; **D15 is feasible on the frozen detector** (the reviewer traced two
adjacent helper items with a reference to their right through the overlap,
cut, fold and placement rules). All findings adopted as text fixes: the
divider's `minX` taken from the prepare-time discovery, with
`dividerUnavailable` when it is missing there; "right of the divider" judged by
`midX`, pinned with step 5's geometry; a settle and generation guard on D10
(collapsed ≥ 1 s before the pass, unchanged at its end), after the reviewer
showed a pass landing within the recorded 0.66–0.77 s animation would misfile
exactly as the recorded jump does; A8b fixed (it lacked `-r`, so it passed
without scanning, and scanned the wrong folder for AX writes); each D10
boundary independent, the disabled always-hidden section, no-frame items;
`baselineStale` produced; worst-case durations; the icon-width limit; explicit
candidates for the harness; `iceBarMode` / `barHiddenBySystem` / `noRoom`
producers and a `RoomGuard`; per-item skips in `CheckPlan`; union jobs and
queueing; a rejected nearer candidate pre-registered; dynamic observed items
dropped; the limits' wording; IceCore's own section enum.

## Appendix H — Codex's review of v5.1

Codex (codex-cli 0.154.0), after its quota returned; 4 findings.

| finding | ruling |
|---|---|
| P1 — the 2 s serial deadline can keep omitting healthy processes, and the 3-pass carry cap then drops their items | **adopt** → carry for as long as the process is alive and not conclusively read; deadline reported as `notAttempted`; the walk resumes where the last deadline stopped; T4 cases |
| P1 — D9 depends on an AX identifier surviving an `autosaveName`, unmeasured, and the protocol forbids `autosaveName` | **adopt** → T8b step 10 measures exactly that on a helper (its own domain, deleted before and after); failure is reported as a blocker |
| P1 — A8b does not scan the feed's sources | **reject**: `MenuBarDetectorFeed` is a target of `Packages/MenuBarDiscovery` (D5), so its sources are under the scanned directory; the directories are now listed one by one. Fed back to Codex (below). |
| P2 — baseline reuse ignores capture geometry | **adopt** → geometry identity in the reuse rule |

**Round 2.** Codex confirmed the three adopted fixes, **did not re-raise** the A8b
finding (the rejection stands), and raised a new P1: carrying for as long as a
process keeps failing leaves ghost items. **Codex wins** → a 30 s freshness
bound since the last successful read, then `stale`; the §8 row it flagged as
contradictory is corrected.

## Deviations (ledger, written as they happen)

Format: trigger → what changed → reason.

1. During T4 review (2026-09-23): the worker's `DiscoveredCachePlan` filed a
   *new* item left of a known, collapsed hidden divider as `visible` (it fell
   through to "no previous → visible"), and its test pinned an item between
   two known boundaries as `visible` → fixed test-first (5 cases red, then
   green); D10's wording made explicit: left of a known hidden boundary is
   never `visible`, right of a known always-hidden boundary is never
   `alwaysHidden`, and a frameless item keeps its previous section → the
   first reading of "an item neither boundary decides" was ambiguous enough to
   let the bug through.
2. During T6 (2026-09-23): the first attempt failed its labels check only
   because one process was never conclusively read — a WebKit content process,
   activation policy `.prohibited`, suspended: it held every Accessibility
   request for the full 0.25 s (so the warm pass cost ≈ 300 ms and every pass
   was incomplete), and answered `noValue` in 19 ms minutes later → discovery
   now skips `.prohibited` processes → none owned an item in the census, every
   earlier probe that found the whole bar skipped them, and reading them wakes
   suspended background processes every tick. Second attempt: 11/11 labels
   agree (same label hash), the negative control fails, no census drift, the
   plan lists the 9 on-bar items in ascending x, and warm passes take
   24–26 ms (cold 970 ms, second 54 ms).
3. During T6: `mbdiscover` is a command-line process with no `NSApplication`,
   so reading its own pid can only time out → it leaves itself out. Whether an
   AppKit app (Ice) can read its **own** extras from a background queue is
   still unmeasured → added to T8b step 10: the helper reads its own
   `AXIdentifier` in-process, from a background queue, while its main thread
   runs the app.
4. During T6: the comparator accepted extra, unlabelled items and ignored
   completeness, and `--check` never compared the plan order → all three
   fixed test-first (2 cases red, then green); `--time N` added, since every
   other mode is a fresh, cold process.
5. During T7 (2026-09-23): `PreparedVerification` is a struct whose `State`
   is `.skip(reason)` or `.ready(Ready)`, `targets` being the section's whole
   roster (so positional / stacked items also get a result) → one accounting
   for every skip path. A target refused `.foldNotAbsentAtBaseline` while a
   reference in the same baseline is accepted cannot occur through `prepare`
   (that refusal is whole-baseline), so tests 4–7 drive `verify` from a
   hand-built `Ready` around a real `StripAssessor.baseline`. A reused
   baseline keeps its original `createdAt` (the 10 minutes run from the
   capture, not from the last reuse). **Open for the next session:** a
   baseline or observation that never produced a sample is reported as
   `.skip(.cancelled)` — it needs its own `CheckSkipReason` (e.g.
   `captureFailed`) in IceCore's `CheckSupport.swift`; a reused baseline
   carries its original `checkableTargets` while `targets` is recomputed, so
   a membership change within the reuse tolerance would diverge (untested).
   **Both closed by Deviation 6.**
6. Closing Deviation 5 (2026-09-23, next session): **(a)** a baseline or
   observation with no sample while nothing cancelled the job now reports
   `CheckSkipReason.captureFailed` (IceCore `CheckSupport.swift`), not
   `.cancelled`; **(b)** a baseline is reused only when
   `BaselineReuse.sameRoster` holds (the fresh plan's targets as a set and its
   per-item skips equal the baseline's) and `isReusable` now requires the
   fresh plan's framed keys to be **exactly** the baseline's (a new observed
   item left of the reference is ink the baseline cannot explain), the fresh
   frames taken from the fresh plan instead of the old baseline's keys →
   test-first: 6 IceCore cases and 5 feed cases red, then green (IceCore 329,
   MenuBarDiscovery 19, MenuBarDetectorFeed 29) → reason: a reused baseline
   must account for exactly the roster `verify` reports on, and "no sample"
   and "cancelled" call for different responses (retry later vs. nothing).
7. T8a and its pre-live review (2026-09-23; three Opus reviewers, 29
   findings, and Codex, 6; rulings in the session record) → **(a)** the live
   protocol runs as two stages, `vizprobe discover` (steps 1, 2, 4, the
   target quits, 9, 10a, 10b, 7, 8, 11) and `vizprobe verify` (1, 2, 3, 5,
   6, 11), each preceded by a bundle-id check (step 0), so steps 9 and 10,
   which decide D10's carry path and D9 and carry no expectation, run before
   any step that can stop a run on a verdict; **(b)** section 6's room rule
   is read with the capture indicator: when it is up, free room is measured
   from the indicator's own `minX` (its width is not free), +41 pt only when
   it is absent; **(c)** a `«` or a privacy pill left of the items is checked
   before and after every launch and at every safety check and stops the run;
   a changed MenuBarAgent set is recorded, not a stop (the indicator comes
   and goes); **(d)** the pre-registered
   `refusedAtBaseline(.foldNotAbsentAtBaseline)` of steps 5 and 6(b) cannot
   come out of `HidingVerification` (that refusal is whole-baseline, so no
   reference is accepted and prepare returns `.skip(.noReference)`): on that
   skip the harness takes its own baseline over the same ids and records
   the step when its fold reads `.unreadable`, and stops on `.present` or
   `.absent`; `foldUnreadable` is recorded only for the hidden halves, never
   for a `.stillDrawn` expectation; **(e)** step 5's reuse after `show` is
   recorded, not required (the target may come back at another frame);
   **(f)** `--mimic-nodivider` reaches Ice's state the way Ice does without
   an expansion: created at 0, then the standard length with the constraint
   active (the `.chevron` style's shown state), then the `.noDivider`
   sequence on the next main-queue turn, the button's target and action set
   as Ice sets them; the helper reports whether it ended in that state
   (length 0, constraint inactive, 1 pt window) and how many constraints
   matched, and a mismatch is reported as "not reproduced", never as a D10
   result; **(g)** step 10 answers yes / no / inconclusive per reader, so a
   failed read is never reported as D9 failing → reason: the reviewers showed
   the split did not protect steps 9-10, the room rule was short by the
   indicator's width in the usual case, and no `«` check ran after a launch.
8. During T8b (2026-09-23): the first `discover` run stopped at step 8 --
   its baseline read the fold `unreadable` on all 5 attempts -- because on
   macOS 27 a new helper item did **not** appear at the left end of the bar
   (step 2: the user's leftmost item at 1094 pt, the reference and target
   at 1171 and 1143 pt; step 7: one process's two items at 1066 and 1191 pt),
   so the user's items left of the helpers were ink no read frame explained
   → the harness's own baselines (steps 3, 6(a), 8) now observe every listed,
   named item left of the leftmost helper, read-only, exactly as D15 has the
   app's check do; `HidingVerification` (steps 5, 6(b)) already did → Jev
   (`jev-1.13.0`, request and response in the run's evidence directory):
   this over stopping 0.97; stopping breaks "show the detector's verdicts"
   0.82; rerunning against "no retry" 0.57, undecided, stated here: the
   stopped run is reported as it happened, and the new runs use a changed
   method, not the same one again. Room: the capture indicator never
   appeared left of the items on this machine in these runs, so every room
   check carried the 41 pt reserve and step 6 (verify) and step 7 (second
   `discover` run) were skipped for room, as section 6 pre-registers.
9. During T9 (2026-09-23; implemented by a worker from a written spec, then
   reviewed here) → **(a)** the A8 table written before T9 had lost that
   `postMoveEvents` sends its `mouseUp` to the *destination* item's window
   (af4baf1); matching it literally would have changed a move on macOS 26
   and earlier → the table is corrected (one line added, one changed:
   `guard let targetWindowID = destination.targetItem.source.windowID`,
   `windowID: targetWindowID,`), 71 hits; **(b)** `HidingVerifier` runs its
   jobs from an ordered queue -- a new job cancels only queued or running
   jobs whose sections overlap -- instead of one slot and one generation,
   which dropped a job's result whenever any other job started; **(c)** a
   redundant `state` assignment bumps a divider's generation but does not
   restart its 1 s settle; **(d)** the reducer's run-loop coalescing is a
   50 ms debounce on the combined input stream before
   `VerificationTrigger.reduce` (the reducer's inputs carry no timestamp);
   the "no baseline" and whole-section skip statuses are summarised from
   placeholder keys, since `VerificationSummary` shows case names only →
   reason: A8 exists to catch drift and caught the table's own error; the
   verifier must follow D16's "jobs queued in order".
10. Phase 3, /simcodex (2026-09-23; three rounds over `af4baf1..HEAD`, Codex
   plus four cleanup lenses, then Opus re-checks; rounds 2 and 3 Codex-clean,
   round 3 without P0/P1 from either) → **(a)** discovery, the cache's
   display and the check's captures now describe one screen: `LiveDisplay`
   takes a screen provider, Ice passes the active menu bar's screen and
   `HidingVerification.live` its own (Codex P1, multi-display); **(b)** the
   feed matches a key only against `AXMenuBarItem` records, as `ItemCatalog`
   keys them (an empty-identifier child of another role made an `.unnamed`
   target absent), test-first; **(c)** the feed's readers skip `AXTitle`,
   `AXDescription`, `AXHelp` (`LiveExtrasReader(readsLabels: false)`), three
   of six calls per child per sample; **(d)** a divider's enabled state is
   read when the pass ends -- turning the always-hidden section on or off
   never changes a control item's `state`, so the snapshot's copy went
   stale -- and the tracking holds no strong reference to `AppState`;
   **(e)** a nil discovery that was not cancelled reports `noGeometry`, not
   `cancelled`, test-first; a skip decided before any roster exists names
   its reason in the status line; **(f)** behaviour-preserving cleanups:
   one generic tag-collision rule, `evaluate`'s derivable `known` removed,
   the discoverer's zero-process branch folded in, the verifier's unused
   `shownAt` (so `noBaseline`'s `shownSeconds` is always 0 -- the status line
   shows reason names only) and `sections` removed. Deferred, stated in the
   evidence package: `PreparedVerification.generation` (unread), the Ice
   icon key threaded through four layers although the fresh set holds it,
   section membership decided twice, and the P2 lists.

## Progress (for a resumed session)

- Branch `wip/ax-discovery` (local, not pushed); checkpoints per task.
- Done and green: T1–T4b (IceCore, 323 tests), T5 (MenuBarDiscovery, 19
  tests), T6 (E2E on the real bar, evidence
  `~/IceReverse-evidence/20260923-171206-t6/attempt2/`), T7
  (MenuBarDetectorFeed, 24 tests, 90.1 % lines excluding the live factory).
  Detector files and `Packages/MenuBarCapture` byte-identical to `af4baf1`;
  A8b's grep empty.
- Done (this session): Deviation 5's items (Deviation 6); T8a (probe
  stages, reviewed by three Opus reviewers and Codex twice, Deviation 7);
  T8b, three runs: `20260923-195750-vzdiscover` (stopped at step 8,
  Deviation 8), `20260923-200220-vzverify` (steps 3 and 5 as expected, step 6
  skipped for room), `20260923-200409-vzdiscover` (every step as expected
  except step 7, skipped for room); D9 holds and the `.noDivider` divider is
  in Accessibility (2 pt frame on the bar), both in two runs.
- Done (this session, continued): T9 (Deviation 9), T10 (FINDINGS, probes
  README, this ledger), Phase 3 /simcodex (Deviation 10), the full test run
  (IceCore 329, 97.3 % lines; MenuBarDiscovery 19 + MenuBarDetectorFeed 31,
  91.9 % excluding the live adapters and the CLI; MenuBarCapture 30;
  SafeWidthCore 277; probes and Ice build; A3, A4, A8 (71), A8b, A10), and
  post-change E2E runs `20260923-210134-vzdiscover`, `20260923-210220-vzverify`.
  T6's frozen labels no longer match the bar (an app that owned a parked
  item has quit): census drift, which T6's protocol voids rather than fails.
- Earlier plan for this session: the two open items of Deviation 5; T8a / T8b (live, sacrificial
  helpers; steps 9 and 10 decide D10's carry path and D9); T9 (Ice — write
  the A8 / A10 expected tables first); T10 (docs); then /simcodex and the
  full test run; then the evidence package. Commit, merge and push wait for
  the user.

### Start command for the next session (as given to the user, 2026-09-23)

```
/fatboyslim 继续 Ice 的 macOS 27 移植（discovery ＋ Ice 内只读隐藏核验）。

【整体最终目标】Ice 在 macOS 27 上不再卡「Loading menu bar items…」：用 Accessibility 枚举菜单栏项与身份，替掉 MenuBarItem.windowID 这条身份链；按 Ice 自己的分隔条分三块（只在分隔条收起 ≥1s 且本轮状态没变时计算，展开时沿用上次）；Ice 在收起某区后调用视觉检测器，只读核验该区是否真的没画出来，结果记日志并在布局设置里显示。检测器本身不改，不接线到任何隐藏行为。真正能在 27 上生效的隐藏机制不在本计划内，以后用这个核验来判定。

【本 session 目标】按 docs/plans/2026-09-23-ax-discovery.md（v5.2）做完剩余任务并收官：
0. 先修 Deviation 5 的两个遗留项（TDD）：没拿到任何截图时给出独立原因（如 captureFailed，加在 IceCore 的 CheckSupport.swift）；复用基线时可检项名单与重算的 targets 可能不一致。
1. T8a：扩展 probe（vzhelper 支持 --items/--identifiers/--glyphs 含 alt/--mimic-nodivider/自读 AXIdentifier；vizprobe 加 discover、verify 两个阶段），build.sh 构建到 /private/tmp，dry run 通过。
2. T8b：按 plan 第 6 节 1–11 步做活体跑，只用牺牲 helper。第 9 步（.noDivider 状态在 AX 里是否还在）决定 D10 的沿用路径；第 10 步（autosaveName ＋ identifier 并存，且 helper 在自己进程内、从后台队列读自己的 AXIdentifier）决定 D9。读不回来就按阻塞项上报，不绕过。
3. T9：按 4.4 改 Ice。动手前先写好 A8 的预期命中表和 A10 的预期改动行文件；只 xcodebuild 构建，不运行 Ice。
4. T10：更新 FINDINGS（第 0 节的 MEASURED 事实；windowID 是「句柄」而非身份；27 上的回退项；第 9、10 步和核验的活体结果）、probes README、plan 偏差台账。
5. Phase 3：/simcodex（Codex 额度已恢复），然后全量测试；交付证据包。commit、合并、push 都等我拍板。

先读：plan 全文，重点是第 0–9 节、附录 F（我的决定）、附录 H（Codex 评审）、Deviations 1–5 与 Progress；docs/macos-27/FINDINGS.md 的 Refuted 一节。

【当前状态】分支 wip/ax-discovery（本地 checkpoint，未 push；macos-27-fix 仍在 af4baf1）。测试：IceCore 323、MenuBarDiscovery 19、MenuBarDetectorFeed 24，全绿。swift test 用 --scratch-path 指向 ~/Documents 之外（例：/private/tmp/claude-501/icecore-build、/private/tmp/claude-501/mbdiscovery-build），否则 iCloud 让 codesign 拒签。mbdiscover 可做只读核对（--check、--plan、--time N）。T6 证据：~/IceReverse-evidence/20260923-171206-t6/attempt2。

【已定、不重议】
- D10 按分隔条分区（仅收起时计算）；D7 在 Ice 内做只读核验，带全部调用方规避手段：帧两侧各裁 1pt、参照项左边的项全部一起观测、参照项取分隔条右侧 Ice 图标左侧的静态项、基线 10 分钟内且几何不变才复用、空位 <41pt 跳过、重试、合并状态流、专用队列加可取消截图。
- 键永远带 pid；沿用项以最近一次成功读取起 30s 为限；遍历起点每轮轮换；跳过 .prohibited 进程；getMenuBarItems 不改（只切缓存 pass）。
- 挤出式隐藏已叫停；三种选展开长度的办法已证伪；MenuBarItemImageCache 在 27 上给不出模板；实心块图标一律 notObserved。

【约束】
- 实验只用自建牺牲 helper（仅限现有 bundle id com.icespike4.target / .protected），绝不碰我已有的菜单栏项。
- 除第 10 步外不设 autosaveName；不撑开任何 spacer；不注入鼠标事件。
- 不经我明说不运行真的 Ice；不做系统级副作用（新 bundle id 也算）。
- IceCore 只用标准库；检测器文件与 Packages/MenuBarCapture 必须与 af4baf1 逐字节一致（A3/A4）。
- 只在 wip/ 分支做 checkpoint，不 push、不合并。

【要我另外放行才能做】无折叠带（656–836pt）能否使用（要注入第一次鼠标事件）；MenuBarAgent 合成窗口在折叠/无折叠态是否与显示一致（要撑开 spacer 造出折叠）。

【需要时提醒我】~/IceReverse-evidence/ 里的原始证据不在仓库；docs/plans/2026-09-18-safe-width.md 附录有 5 轮评审辩论记录，别重开已裁决的争论；已提交的 probes/visibility/labels.json（30ab8b0）含已装 app 的 bundle id，push 前要我决定；FINDINGS 的 Refuted 表有三行重复，不要自行删。

判断决策时用 typesafe 技能（Jev，按逐条要求的 noul 问，做法见项目 memory）；评审用 Codex。用中文和我交流。
```
