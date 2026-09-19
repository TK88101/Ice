# Plan — the visibility detector's adapter (macOS 27)

Status: **final (v4)** — after Codex and Opus reviews of v1 and Codex's reviews of v2 and v3; see the appendices. Awaiting the user's go-ahead; nothing is implemented yet.

The decision layer `IceCore/MenuBarItemVisibility` (f5f6954) answers "is this item
drawn on the bar" from plain values. This plan builds what produces those values
from a real capture of the bar, and tests the chain against recorded evidence and
against a sacrificial helper.

Raw evidence for every MEASURED claim dated 2026-09-19 is in
`~/IceReverse-evidence/20260919-winlist-probes/` (outputs, captures, probe sources,
manifest). It is outside the repo on purpose: the captures show installed apps.

---

## 0. The premise this plan had to correct

The task as given: take each item's template from Ice's `MenuBarItemImageCache`,
capture the menu bar strip, compute unique/ambiguous/absent matches and the fold
witness, hand them to the decision layer.

**`MenuBarItemImageCache` is always empty on macOS 27, so it cannot supply a
template.**

- It captures one window per item, by `item.windowID`
  (`Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:112-186`), for the items in
  `itemCache.managedItems` (same file, :222). On macOS 27 the item cache is empty:
  `.itemsOnly` discards the only menu bar window, `MenuBarAgent`'s level-24
  composite (`Shared/Bridging/Bridging.swift:427-431`; MEASURED in FINDINGS "The
  failure").
- **MEASURED 2026-09-19, read-only, two instants** (`winlist.txt`,
  `status-item-shaped.txt`): `CGWindowListCopyWindowInfo(.optionAll)` listed no
  third-party window shaped like a status item (height 20–40 pt, width ≤ 200 pt)
  at any layer. At level 24 it listed three full-width `MenuBarAgent` windows and
  three full-width WindowServer windows. (FINDINGS' window 2688 came from the
  private `CGSGetProcessMenuBarWindowList` on an earlier day; window numbers change
  when `MenuBarAgent` restarts.)
- Reviving the cache would mean replacing window-ID discovery and identity with
  Accessibility and the per-window capture with strip crops — the macOS 27
  discovery port, not an adapter (Codex, round 1).

So the templates come from **the strip itself**: at a settled baseline taken just
before the action, each item is cut from a capture of the bar where Accessibility
says it is, and accepted only if the cut passes the checks of 3.2.

### A candidate this plan does not use

**MEASURED 2026-09-19, read-only, one instant at rest** (`composite-capture.txt`,
`captures/win-*.png`, `captures/stack.png`): each of the three `MenuBarAgent`
windows, captured on its own with `CGWindowListCreateImageFromArray`, is the bar's
glyphs on a transparent background; their status areas are identical and their
app-menu areas differ; overlaid on an on-screen capture, every status item sits at
the same x. The three WindowServer windows capture fully transparent.

Whether that window tracks what is *displayed* when an item is folded behind `«`
or sits in the 656–836 pt no-fold band is unknown, and so is which of the three is
live. Not used; recorded in section 10.

---

## 1. Goal and non-goals

**Goal.** A capture adapter that turns real captures of the bar into the facts the
decision layer consumes, with every rule that turns facts into `ItemSighting` /
`Fold` / `captureStable` in IceCore; the chain replayed against the recorded hard
cases of 2026-09-18, and shown live on a sacrificial helper (drawn → hidden without
a fold → restored).

**Non-goals.**

- Discovery on macOS 27.
- Any change under `Ice/`, `Shared/`, `MenuBarItemService/` or `Ice.xcodeproj`.
  The new package is **not** linked into the app: nothing in Ice can call it until
  discovery exists. This is a decision-core integration tested through probes —
  **not** a production integration of Ice.
- Raising the fold live (needs the spacer expanded; its own approval).
- The composite window as a source; choosing an expansion length (refuted; user
  ruling); the visibility-restriction assertion; running Ice.

---

## 2. Shape

```
                 plain values only                        AppKit / CG / AX
 ┌────────────────────── IceCore ──────────────────────┐  ┌──── MenuBarCapture ────┐
 │ StripImage, BarGeometry (width, height, notch)     │  │ StripCapturing (live:   │
 │ Ink               colours that count as ink        │◀─│   CGWindowList strip)   │
 │ TemplateBaseline  settled baseline → templates     │  │ CGImage → StripImage    │
 │ TemplateMatcher   trimap search → Match            │  │ MenuBarAXReading (r/o)  │
 │ CaptureStability  references → captureStable      │  │ Preflight (permissions, │
 │ FoldWitness       agent frames + pixels → Fold     │  │   bar visible, notch)   │
 │ StripAssessor     samples → StripReading           │  │ Sampler: cap → AX → cap │
 │ MenuBarItemVisibility (exists; +foldAtBaseline)    │  │ VisibilityObserver      │
 └─────────────────────────────────────────────────────┘  └─────────────────────────┘
   docs/macos-27/probes/visibility:  vzreplay (offline, ~/IceReverse-evidence)
                                     vizprobe + vzhelper ×2 (live, sacrificial only)
```

IceCore keeps its rule: no AppKit, ApplicationServices, CoreGraphics, ImageIO,
ScreenCaptureKit (`Packages/IceCore/Package.swift:15-19`). All pixel arithmetic is
in IceCore; the adapter acquires pixels, Accessibility frames and display geometry
and converts them to values.

---

## 3. The rules (IceCore)

Units: pt along the bar's x axis; px = pt × scale.

### 3.0 Pre-registered parameters

Fixed before any replay or run; a change after seeing results is a logged
deviation with its reason.

| parameter | value | source / reason |
|---|---|---|
| channel tolerance | 24 | `swctl` `Calibration.templateTolerance` |
| ink colours | white ±70 on a dark bar, black ±100 on a light one | `swctl` `Calibration.swift:37-38` |
| `maxMismatch` (decision layer) | 0.05 | `swctl` `Instrument.templateMismatch` |
| `foundThreshold` | 0.08 | above `maxMismatch` (invariant 3.3) |
| `inkPresenceMin` | 0.90 | Teams badge redraw measured at 0.956 (Opus review, `20260918-200903-scan-mid` 00003 vs 00143) |
| core-ink invariant | core-ink px ≥ 2 × `foundThreshold` × cared px | an empty slot must fail by a margin (Opus P0-2) |
| core-background minimum | core-background px ≥ max(core-ink px, 0.3 × cared px) | `drawn` must rest on the glyph's surroundings too, not on ink alone (Codex v2, counterexample B) |
| fold-region ink cluster | 8-connected ink px outside every matched template span, ≥ 16 px | defines "unexplained ink" (Codex v2, fold hole 3); checked against the recorded chevrons in T9 |
| template margin | 2 px around the ink bounding box | Opus P0-2 |
| candidate clustering | contiguous runs: offsets ≤ 2 px apart are one cluster, best score represents it | Opus P1-9, amended by deviation 5 |
| minimum template width | 4 pt | radius < half of it |
| samples per observation | ≥ 2, ≥ 0.3 s apart | Opus P0-3, P1-4 |
| baseline | 8 captures over ≥ 3 s, the first 2 dropped | `swctl` `Experiment.swift:172-173, 196-216` |
| region agreement | ≤ 1 % of px differ beyond channel tolerance | bracket rule 3.5 |

### 3.1 Geometry and ink

`BarGeometry { widthPt, heightPt, scale, notch: Span? }` is an input, not a
constant (Opus P1-6: `swctl` hard-codes 960 pt). The notch is excluded from every
search and from ink calibration: it captures as pure black, which counts as ink on
a light bar and would make absence unreachable.

`Ink` is a set of colour matches. Live: the calibrated bar ink (white on a dark
bar, black on a light one, from the median luma of the status area outside the
notch), decided once per baseline and used for every later capture of that
observation. Replay: the calibrated ink plus the recorded helpers' marker colours,
because `probes/safewidth`'s target was drawn in markers, not in ink.

### 3.2 Templates (`TemplateBaseline`)

Input: the baseline captures (3.0) and `ItemFrame { id, minX, minY, width, height }`
from **two** Accessibility reads, each between two agreeing captures, that agree
with each other (Opus P0-1c: Accessibility lags ≈ 0.1 s).

Accepted only if **all** hold, else rejected with the named reason:

1. `foldAtBaseline == .absent` — with `«` up, frames stack on the chevron
   (FINDINGS "Two different kinds of not visible"; Opus P0-1b). Otherwise nothing
   is accepted.
2. Frame finite, inside the strip, `minY` < bar height, width ≥ 4 pt (a parked
   item's frame is at y ≈ 1104: Opus P0-1a).
3. Frame overlaps no other item frame and no `MenuBarAgent` frame.
4. The cut is taken at the **ink bounding box** inside the frame, plus the margin,
   and classified into a **trimap**: core ink (matches an ink colour), core
   background (farther than twice the tolerance from every ink colour), and edge
   (everything else, ignored). Core-ink and core-background counts satisfy both
   invariants of 3.0.
5. Static: its trimap matches every kept baseline capture at offset 0 within
   `maxMismatch`. An item that changes during the baseline is dynamic; dynamic
   items get `.changedSinceBaseline` in every later sighting and are never
   references.
6. Unique: the full search of 3.3 on the first kept capture finds exactly one
   cluster, at its own position; and no two accepted templates' matches overlap.

A rejected id is not sighted later, so the decision layer says `notObserved`.

### 3.3 Matching (`TemplateMatcher`) — two passes over the whole strip

Never narrowed to Accessibility's current x (FINDINGS: it cannot say where an
overflowed item is); the notch is skipped.

1. **Trimap**: at each offset, mismatch = (core-ink px not ink + core-background px
   that are ink) / cared px. Offsets ≤ `foundThreshold` are candidates; non-maximum
   suppression keeps cluster representatives. One → `.unique(x, mismatch)`; two or
   more → `.ambiguous(count)`.
2. Only if pass 1 found nothing: **ink presence** — the fraction of core-ink px that
   are ink. Offsets ≥ `inkPresenceMin`, suppressed the same way. One →
   `.unique(x, mismatch: pass-1 mismatch at x)`; two or more → `.ambiguous`; none →
   `.absent(bestMismatch: pass 1's best)`.

`foundThreshold ≥ maxMismatch` is a precondition, so a pass-2 hit always reads as
`.unverifiable(.weakMatch)`: pass 2 can block an absence, never produce `drawn`.

**Why a trimap and not the full colour crop** (changed from v1):
**MEASURED 2026-09-19** (`t0-bucket-diff.txt`): two captures of the bar about 2 s
apart, with a terminal window under the translucent bar, differ beyond the channel
tolerance in **17–23 %** of the status area's pixels. A colour crop includes that
backdrop, so a present item would routinely fail `maxMismatch` and the detector
would say "unverifiable" whenever the window under the bar changes. The trimap
compares only what the glyph decides — where ink is and where it clearly is not —
so the backdrop changes nothing unless it turns ink-coloured. A uniform blob of ink
over the slot fails on the core-background pixels, an empty slot fails on the
core-ink pixels by at least twice the threshold, and ink appearing around a present
glyph lands in pass 2 as weak.

**What pixels cannot rule out, stated as residuals** (Codex v2, counterexamples A
and C; v2 of this plan wrongly said they were impossible):

- **A — a forged glyph reads as drawn.** If the window under the translucent bar
  shows ink-coloured pixels at exactly the template's core-ink positions and non-ink
  at its core-background positions, pass 1 matches an empty slot. No pixel test can
  tell who drew the pattern. Narrowed, not closed, by the core-background minimum
  and by the Accessibility veto of 3.7.
- **C — a partly dimmed glyph reads as absent.** An item that dims part of its own
  icon after the baseline (a disabled state, a local redraw) can drop below both
  passes. Same class as the icon-swap residual of 3.7.

So `drawn` means "the item's ink pattern, with its surroundings, is at x", and
`notDrawn` means "neither pass finds it anywhere" — the decision layer's
guarantees hold only up to these two residuals, and FINDINGS will say so.

### 3.4 Stability (`CaptureStability`)

Derived, not passed in. Stable iff at least one reference; every reference sighted
exactly once in **every** capture that contributed a sighting, as `.unique` within
`maxMismatch`, within ±1 pt of its baseline x.

References are **our own** static items only (Codex P1; Opus P1-7): live, the
second helper; replay, the recorded protected helper `P`. The clock is not one:
**MEASURED 2026-09-19** (`dot.swift` run): the first capture of a session moved
the clock's Accessibility x from 1592 to 1589 pt, where it stayed for at least
3 s after the last capture. The user's items are read only by the live harness's
safety monitor (6.2), never as a condition of a verdict.

Necessary, not sufficient: it catches a slide (a Space switch), a global ink flip
and a moved reference, not a change under one item (3.3's job).

### 3.5 Fold (`FoldWitness`)

Inputs per sample: the capture before the Accessibility read, the capture after
it, and `MenuBarAgent`'s extras frames — or `nil` if the read failed, which is
never the same as an empty list (Opus P1-5). The **fold region** is from the
notch's right edge to the leftmost reference.

Per sample, `.unreadable` unless all of:

- the read succeeded and returned at least one frame (`MenuBarAgent` always owns
  system items: 4 in every baseline on record, 26/22/26/116 pt);
- the references are stable in both captures and the fold region differs by no
  more than the region-agreement parameter between them (Opus P1-4: the old
  bracket compared only reference x's, which do not move when `«` appears);
- every non-candidate frame matches a baseline frame one to one by x (± 1 pt) and
  width (± 0.5 pt) — deliberately conservative: a system item that moves or
  changes width makes the fold unreadable, and so the hiding unverifiable, never
  wrongly `absent`; how often that happens on real data is measured in T9 (Codex
  v3) — anything that arrives, leaves, moves or is replaced by an
  item of the same width makes the sample unreadable (Codex v2, fold hole 2: a
  multiset of widths alone let an equal-width swap through).

Then: chevron candidates are frames 17.5 ± 0.5 pt wide.

- **0 candidates → `.absent`**, but only if the fold region holds no ink cluster
  (3.0) that the sighted templates do not explain (a `«` drawn before
  Accessibility lists it).
- **1 candidate** with ≥ its core-ink minimum inside its span in the after capture
  → `.present`.
- otherwise `.unreadable`.

Across samples: ≥ 2, ≥ 0.3 s apart, all the same verdict; otherwise unreadable. The
same rule on the baseline gives `foldAtBaseline`. Diagnostics (Codex P2): every
sample records the sorted frames and the difference from the baseline.

Evidence for the width rule, and its limits:

- `«`: 17.5 pt in every chevron reading in the assess records (8 317 by the Opus
  reviewer's count; RESULTS.md says ≈ 8 900).
- The microphone pill: Accessibility frame x = 1035, **16 pt** wide, in the
  baselines of `20260918-194520-c-mid` (flagged "microphone pill present") and
  `20260918-202302-o1` (not flagged; the capture shows the orange capsule at
  ≈ 1025–1061 pt). Absent from the other 18 baselines.
- So an arriving pill is caught by the one-to-one rule **unless it is 17.5 pt
  wide**, in which case it reads as a chevron. Not measured: a pushed-out pill, the
  camera and screen-recording indicators. Width is evidence of identity on this
  machine, not proof of it; `.present` is a residual-bearing verdict for exactly
  that reason, and T9 is the only place it is exercised.

### 3.6 Decision layer change

`StripReading` gains `foldAtBaseline: Fold` — **required, no default** (a default
of `.absent` would claim a fact nobody observed). `hiding(of:in:)` returns
`.unverifiable(.foldAlreadyUp)` when it is `.present`, `.unverifiable(.foldUnreadable)`
when `.unreadable`. Templates are never accepted from a baseline with the fold up
(3.2 rule 1), which closes the path Opus P0-1b used into `restoration`.

`ItemSighting` gains `placement: Placement`, **required, no default**:

- `.consistent` — the item's own Accessibility frame, from the bracketed read, lies
  on this display's bar (inside the display's x range, `minY` < bar height) **and**
  its x span overlaps the matched x span within ± 4 pt;
- `.inconsistent` — a frame was read and fails either condition;
- `.unavailable` — the read succeeded but returned no frame for this item.

(A read that fails as a whole produces no sample at all — 4, `Sampler` — so it
never reaches a sighting.) Placement is computed in IceCore from the frame and the
match, both plain values. It can only veto: `verdict(for:)` returns
`.unverifiable(.contradictsAccessibility)` for a strong unique match whose
placement is not `.consistent`. Absence is never taken from Accessibility — it
keeps laying out items the screen does not draw (FINDINGS, the no-fold band) — so
`.notDrawn` ignores placement. The cost is deliberate: an item whose frame is
stale or missing is `unverifiable`, never `drawn`.

This is the independent evidence Codex v2 asked for against residual A, and it
covers more than y (Codex v3): the vacated slot of a parked item (y ≈ 1104) and a
forged glyph away from the item's own frame both fail it. A forged glyph *at* the
item's own frame still passes — residual A is narrowed, not closed.

### 3.7 Composition (`StripAssessor`)

Baseline + reference ids + target ids + ≥ 2 samples → `StripReading`. A target's
sighting must be the same match kind at the same x (± 0.5 pt) in every sample's
after capture; if any target or reference disagrees across samples, the reading is
unstable (Opus P0-3: mid-animation frames are on record at quarter-point x's).

**Residual, documented:** an item that swaps its icon entirely after the baseline
and before the observation can fail both passes and read as `notDrawn`. Both
passes, the settle rule and pass 2's 0.90 bound narrow this; they do not close it.

---

## 4. The adapter (`Packages/MenuBarCapture`)

Local SwiftPM package, `.macOS(.v14)` (Ice's deployment target), depending on
IceCore by path. Not referenced by `Ice.xcodeproj`.

- **Capture API — decided by T0, MEASURED 2026-09-19** (`t0-capture-api.txt`):
  `CGWindowListCreateImage` of the bar rect, 5–9 ms per capture warm;
  ScreenCaptureKit's `SCScreenshotManager`, 267–412 ms warm and 2.1–2.6 s cold.
  The fold bracket (capture → AX → capture, against a ≈ 0.1 s AX lag) needs the
  fast one. Both return 3456 × 64 at scale 2 here. Whether their pixels agree was
  **not** established: the two captures were ≈ 2 s apart and the backdrop changed
  between them. Risk: `CGWindowListCreateImage` is obsoleted at deployment target
  15 (SDK `CGWindow.h:271-283`); moving Ice's target to 15 means moving this to
  ScreenCaptureKit and re-measuring the bracket.
- `StripImage(cgImage:geometry:)`: sRGB RGBA8, premultiplied last, cut to the bar
  height (`probes/safewidth` Deviation 3).
- `BarGeometry` from `NSScreen` (`frame`, `backingScaleFactor`, the safe-area top
  inset, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` for the notch).
- `MenuBarAXReading`: `AXExtrasMenuBar` children's frames for given pids and for
  `MenuBarAgent`, 0.25 s messaging timeout. A failure of the read as a whole →
  `nil` → no sample; a successful read without a frame for some item → that item's
  placement is `.unavailable`. Read-only.
- `Preflight` (Codex P1): screen capture works (a strip that is not all zero),
  `AXIsProcessTrusted`, `MenuBarAgent`'s extras readable, the bar visible (not
  auto-hidden: Opus P2-14). Any failure → `environmentUnavailable(reason)` before
  anything is launched, never a matcher or fold verdict.
- `Sampler`: capture → AX (`MenuBarAgent` and the target and reference pids) → capture → one sample.
- `VisibilityObserver`: baseline and observe → `StripReading` → verdicts.

---

## 5. Tasks

Shape: a serial chain (each layer consumes the previous one's types); no parallel
implementation agents.

| # | task | DoD |
|---|---|---|
| T0 | **done 2026-09-19** (read-only): capture API and indicator effect | results above and in the evidence directory; strip size = display width × scale by bar height × scale |
| T1 | IceCore `StripImage`, `BarGeometry` | RED first; preconditions, crop bounds, pt↔px, notch exclusion |
| T2 | IceCore `Ink` | dark → white, light → black, notch ignored in calibration, extra colours |
| T3 | IceCore `TemplateBaseline` | one test per acceptance rule (1–6), incl. a parked frame, overlapping frames, fold up at baseline, a thin glyph over its own blank slot rejected by the invariant, a template with too little core background rejected, disagreeing AX reads |
| T4 | IceCore `TemplateMatcher` | unique, shifted, twin glyph → ambiguous, blank → absent, **backdrop change under a present glyph → not absent**, a uniform ink blob over an empty slot → not drawn, pass-2 ambiguous, suppression is non-transitive (two adjacent twins stay two), notch skipped, `foundThreshold < maxMismatch` traps; boundaries at exactly each threshold; **residuals pinned as tests**: a backdrop forging the core-ink pattern over an empty slot reads `.unique` (A), 9 of 16 core-ink px dimmed reads `.absent` (C) — so a later change to either is visible |
| T5 | IceCore `CaptureStability` | zero references, duplicate, missing in one capture, moved > 1 pt, weak → unstable; good → stable |
| T6 | IceCore `FoldWitness` | present, absent, `nil` read, empty read, 16 pt pill arriving, pill at baseline unchanged, an equal-width item moved or swapped, the clock shifted 3 pt (→ unreadable, pinned), 2 candidates, no ink, an unexplained cluster of exactly 15 and 16 px, a cluster inside a matched template span, region changed between brackets, 1 sample, samples too close, samples disagree → as specified |
| T7 | IceCore decision layer: `foldAtBaseline`, `placement` | the 17 existing tests pass both fields explicitly; new tests: `.foldAlreadyUp`, `.foldUnreadable` at baseline, a strong match with placement `.inconsistent` (off the bar; on the bar but x elsewhere) or `.unavailable` → `.contradictsAccessibility`, `.absent` with any placement still `.notDrawn`; placement computed from frame + match at the ± 4 pt boundary |
| T8 | IceCore `StripAssessor` | synthetic strips: drawn → hidden(folded: false) → restored; a target differing across samples → unstable |
| T9 | **Offline replay** `docs/macos-27/probes/visibility/vzreplay` (read-only over `~/IceReverse-evidence`, Opus P1-8) | expected verdicts frozen in a labels file **before** running, taken from an **independent** oracle — `swctl`'s recorded marker search (a different method from this matcher), the attribution records, and the annotations in RESULTS.md and the deviation ledger — never from this matcher's own output (Codex v2); cases: band probes (`204150-m-mid`), chevron captures with 17.5 pt AX, the pill baselines, the Space-slide guard captures (`202525-scan-mid` 00022/00023/00131/00132 → unstable), the Teams badge (→ not absent); every mismatch explained or fixed; **reports the fold rule's unreadable rate** over every recorded sample with agent frames, and it is stated in RESULTS as the price of 3.5's one-to-one rule |
| T10 | `MenuBarCapture` scaffold, `StripImage(cgImage:)`, `BarGeometry` | synthetic `CGImage` at scale 1 and 2, 33 → 32 pt cut, colour round trip |
| T11 | capture and AX protocols, live implementations, `Preflight`, `Sampler` | fakes: order capture → AX → capture; a failed capture or read yields no sample; each preflight failure maps to its reason |
| T12 | `VisibilityObserver` | fakes: baseline → observe → verdicts |
| T13 | Live harness: `vzhelper` (one 12 pt template-image glyph, `isVisible` toggled by lines on **stdin**, exits on EOF, no `autosaveName`, `isVisible = true` at launch), two instances under the existing bundle ids `com.icespike4.target` and `com.icespike4.protected` (no new registrations: Opus P2-13); `vizprobe`; `build.sh` outside `~/Documents` | builds, signs ad hoc; `vizprobe --dry-run` runs preflight and a baseline without launching anything |
| T14 | **Live run** (section 6) | expected verdicts in 5/5 cycles; controls pass; teardown clean |
| T15 | Docs: FINDINGS (the MEASURED facts of 2026-09-19), probes README, deviation ledger | each claim tagged with its source |

---

## 6. Live protocol (T14)

### 6.1 Steps

1. **Preflight** (4). Then, nothing of ours running: a baseline of the bar.
   Abort if `«` or a pill is present, or the free room right of the notch
   (leftmost item's x − notch right edge) is under 30 pt.
2. Delete `com.icespike4.*` defaults. Launch the reference helper, then the target
   (new items appear leftmost, so the target sits left of the reference and hiding
   it moves nobody). Settle ≤ 5 s.
3. **Room check**: abort — helpers quit first — if `«` appeared, the agent set
   changed, or the safety monitor (6.2) reports any user item moved or lost.
4. Baseline (3.0). Both helpers must be accepted.
5. Five cycles: observe → expect `drawn`, stable, fold `.absent`; write `hide` →
   observe → expect `hidden(folded: false)`; write `show` → observe → expect
   `restored`.
6. Controls, once: (a) an id with no template → `notObserved`; (b) with the target
   hidden, a fresh baseline must **reject** the target (parked frame); (c) a third
   instance with the same glyph (launched, observed, quit) → the target reads
   `ambiguous`.
7. Teardown: quit the helpers (EOF), delete their defaults, re-baseline; every
   user item back at its pre-flight x, no `«`.

Any unexpected verdict, `«` at any point, or a safety-monitor event → stop, quit
the helpers, report. No retry within the run.

### 6.2 Safety monitor

Every capture: the user's static items, cut once at the pre-flight baseline, are
searched by the same matcher. Any of them not `.unique` at its x for 2 consecutive
captures → stop. It decides nothing about the helpers and gates no verdict.

Evidence: `~/IceReverse-evidence/<run-id>/` (JSONL, captures at every transition,
manifest with git SHA and binary hashes). Not committed.

---

## 7. Acceptance

| # | check | how |
|---|---|---|
| A1 | IceCore green, line coverage ≥ 80 %, and the boundary tests of T3–T6 present | `swift test --enable-code-coverage --scratch-path <outside ~/Documents>` + `llvm-cov report` |
| A2 | MenuBarCapture green, ≥ 80 % excluding the live capture and AX implementations, which are listed | same |
| A3 | IceCore imports only the standard library (and `Testing` in tests) | `grep -rnE '^\s*(@\w+\s+)*((public|internal|package|private|fileprivate)\s+)?import\s' Packages/IceCore/Sources` |
| A4 | Replay: every case's verdict equals its pre-written expectation | `vzreplay` report |
| A5 | Live: 5/5 cycles and all controls as expected; no `«`; no safety event; teardown equals pre-flight | the run's JSONL, checked by the harness |
| A6 | SafeWidthCore still 277 green | `swift test` in `probes/safewidth` |
| A7 | Ice still builds with the enlarged IceCore (it links IceCore: `project.pbxproj:84,147,211`) | `xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath <outside ~/Documents> build` — builds, does not run |
| A8 | nothing changed in `Ice/`, `Shared/`, `MenuBarItemService/`, `Ice.xcodeproj` | `git diff --stat` |

---

## 8. Risks and rollback

| risk | response |
|---|---|
| The recorded strips were taken by the `screencapture` CLI; live uses `CGWindowListCreateImage` | replay tests the rules, live tests the plumbing; pixel equality between the two is not assumed |
| Whole-strip search collides with app-menu text (false `ambiguous`) | fail-closed; if replay or live shows it, restrict to the status area right of the frontmost app's menus (never to an item's AX x), logged as a deviation |
| Our helpers push a user item out | free-room check before launch, room check after, safety monitor throughout |
| A pill arrives mid-run | fold unreadable (multiset) → stop |
| A coloured or light bar leaves little ink | items rejected, not guessed; the run needs both helpers accepted (template images render in ink) |
| Thresholds fitted to one machine | pre-registered (3.0), recorded with results, claims scoped to this machine |
| `CGWindowListCreateImage` obsoleted at deployment target 15 | recorded (4) |

Rollback: additive (a new package, new IceCore files, a probe directory) except
T7's change to `StripReading` and its test updates; `git revert` undoes it.

## 9. Reminders for the user

- The raw evidence is in `~/IceReverse-evidence/`, not in the repo.
- The appendix of `2026-09-18-safe-width.md` holds five rounds of settled debate;
  nothing here reopens it.
- Codex quota recovers on a 5-hour window.

## 10. Recorded for later

- Does `MenuBarAgent`'s composite window track the display when folded or in the
  no-fold band? If so, templates stop depending on the backdrop.
- Raising the fold live (spacer; approval).
- Pill widths for camera and screen recording; a pushed-out pill's AX frame.
- What makes the clock shift 3 pt on the first capture (the reviewer saw a violet
  dot right of the clock in the old `screencapture` strips; this session's
  `CGWindowListCreateImage` captures show none) — INFERRED to be a capture
  indicator.

---

## Appendix A — debate before v1 (thecure, 2 rounds with Codex)

| # | my position | Codex | outcome |
|---|---|---|---|
| J1 | the cache cannot supply templates on 27 | correct; reviving it = the discovery port | **agreed** |
| J2 | baseline strip crops at AX frames | partly: AX only a cutting hint, settled baseline, whole-strip search, uniqueness | **adopted** |
| J3 | the screen strip is authoritative | correct | **agreed** |
| J4 | pure matcher in IceCore | partly: derive `Fold` in Core from raw facts | **Codex wins** |
| J5 | unit tests + helper E2E | partly: the probe is the adapter's only harness | **adopted** |
| D1 | full crop only; references catch backdrop change | the backdrop can change under one item | **Codex wins** → pass 2 |
| D2 | width 17.5 identifies `«` | pill width unrecorded | **evidence**: pill AX 16 pt; multiset rule |
| D3 | derive `captureStable` in Core | agree, plus duplicates/missing | **adopted** |
| D4 | not linked into Ice | IceCore *is* linked | **fact corrected**, outcome kept |
| D5 | report wording | "no background" is a hypothesis | **partly**: MEASURED for `MenuBarAgent`'s own window at rest; its usefulness is the hypothesis |

## Appendix B — review of v1

Codex: "no fatal omission or contradiction"; no objection left on D1 or D2.
Opus: 15 findings (3 P0). Each checked against its source before ruling.

| source | finding | ruling |
|---|---|---|
| Codex P1 | references should be our own helper, not the user's items | **adopt** → 3.4, 6 |
| Codex P1 | no permission preflight | **adopt** → `Preflight` |
| Codex P2 | T0 DoD hard-codes 3456 × 64 | **adopt** |
| Codex P2 | fold failures not auditable | **adopt** → diagnostics |
| Codex P2 | coverage misses the boundaries | **adopt** → boundary tests in T3–T6 |
| Opus P0-1 | templates can be cut from the wrong pixels (parked frame, fold up, stale AX) | **adopt** → 3.2 rules 1–3, 6 |
| Opus P0-2 | an empty slot matches a thin glyph's own template | **adopt** → ink bounding box + margin, core-ink invariant |
| Opus P0-3 | a post-baseline redraw or a mid-animation frame reads as hidden | **adopt** settle across samples, `inkPresenceMin` pre-registered from the measured badge; icon swap kept as a documented residual |
| Opus P1-4 | fold absence rests on AX alone | **adopt** → fold-region bracket and unexplained-ink rule |
| Opus P1-5 | an empty agent read makes the fold always absent | **adopt** → `nil` ≠ empty; empty → unreadable |
| Opus P1-6 | the notch counts as ink on a light bar | **adopt** → `BarGeometry`, notch excluded |
| Opus P1-7 | the capture pipeline changes the bar; the clock is no reference | **verified** (clock 1592 → 1589 after the first capture) → **adopt** |
| Opus P1-8 | the live E2E cannot tell a right adapter from a wrong one | **adopt** → offline replay (T9) and stronger controls (6.1 step 6) |
| Opus P1-9 | load-bearing thresholds unspecified; transitive clustering | **adopt** → 3.0 |
| Opus P2-10 | "whatever its width" false; o1 not flagged; 8 900 vs 8 317 | **adopt** all three corrections. The optional veto on a saturated capsule colour is **rejected**: on 2026-09-19 the bar itself is red (`captures/stack.png`), so the veto would fire on every sample |
| Opus P2-11 | MEASURED claims without archived source; overstated wording | **adopt** → evidence directory, wording |
| Opus P2-12 | no build check; weak import grep | **adopt** → A7, A3 |
| Opus P2-13 | signals to recycled pids, persisted hidden helper, new bundle ids | **adopt** → stdin, no autosave, reuse `com.icespike4.*` |
| Opus P2-14 | baseline ink, stability over every capture, auto-hidden bar | **adopt** |
| Opus P2-15 | drop `.present` (fold test is a non-goal) | **reject**: replay exercises `.present` on recorded chevron captures at no live cost; dropping it leaves the committed `hidden(folded: true)` unreachable and untested |
| (new) | T0 re-run: the backdrop changed 17–23 % of the status area in ≈ 2 s | **design change** → trimap matching (3.3); v1's "status areas identical across APIs" withdrawn |

## Appendix C — Codex's review of v2

| item | Codex | ruling |
|---|---|---|
| trimap: "both errors land on unverifiable" | **disagree**: a backdrop forging the core-ink pattern over an empty slot reads drawn (A); a template with no core background matches any ink spots (B); partial dimming reads absent (C) | **Codex right**: v2 overclaimed. B closed by the core-background minimum; A and C stated as residuals and pinned as tests; A narrowed by an Accessibility veto on `drawn` (3.6) |
| the change of method itself | agree with the motive (17–23 % backdrop change) | kept |
| rejecting Opus P2-15 (keep `.present`) | agree | kept; `.present` now labelled residual-bearing |
| rejecting the saturated-capsule veto | agree as posed | kept |
| fold: width is not identity | hole 1 | stated in 3.5; not closable without measuring other indicators (section 10) |
| fold: multiset lets an equal-width swap through | hole 2 | **adopt** → one-to-one by x and width |
| fold: "ink cluster" undefined | hole 3 | **adopt** → pre-registered in 3.0, boundary tests in T6 |
| order T0–T15, T9 before the adapter | agree | kept |
| T9's oracle must not be the matcher itself | condition | **adopt** → independent labels, frozen first |
| most likely to fail | T14, most likely by a safe abort | recorded; an abort is reported as an abort, never as a pass |

## Appendix D — Codex's review of v3

Codex: every v2 point "correctly written in". Three further points, all adopted; no
further round was run on them.

| item | ruling |
|---|---|
| `.onBar` from `minY` alone does not show the item is on *this* bar where the glyph matched (an overflowed item also has y < 40) | **adopt** → placement is `.consistent` only on this display's bar **and** overlapping the match within ± 4 pt (3.6) |
| `.unknown` had no input path: a failed read yields no sample | **adopt** → whole-read failure = no sample; read OK without the item's frame = `.unavailable` (3.6, 4) |
| one-to-one frame matching may make the fold unreadable in ordinary use | **adopt** → kept as a deliberate, fail-closed constraint; T6 pins the 3 pt clock shift; T9 measures the unreadable rate on recorded data and RESULTS states it |

---

## Deviations (ledger, written as they happen)

Format: trigger → what changed → reason.

1. Before any code or result (2026-09-19): the bar right of the notch measured a
   median luma of **125** (p25 102, p75 129) — a red bar with white glyphs, 3 levels
   from 3.1's dark/light threshold of 128 → ink is decided by the median only
   outside [118, 138]; inside that band, by which ink colour (white ± 70 or black
   ± 100) matches more pixels inside the items' Accessibility frames, a tie or zero
   rejecting every template → a mid-tone backdrop matches neither ink colour, so
   inside the band only glyphs are counted, while the median rule alone would flip
   on a few levels of wallpaper.
2. Before any code (2026-09-19): 3.5's bracket and 3.0's "region agreement" compare
   the fold region's **ink maps**, not raw colour → the raw-colour comparison
   would fail on the same 17–23 % backdrop change that moved 3.3 to the trimap.
3. Before any code (2026-09-19): the baseline is taken as samples (capture → AX →
   capture): ≥ 4 samples over ≥ 3 s, the first sample (its 2 captures) dropped;
   every kept sample's item read must agree with the others, and `foldAtBaseline`
   comes from the kept samples, with ink inside the items' own frames counted as
   explained (no templates exist yet) → same content as 3.0's "8 captures, first 2
   dropped" and 3.2's "two reads between agreeing captures", in the shape the
   `Sampler` produces.
4. Before any code (2026-09-19): 3.5's "`nil` read" is realised in the adapter —
   a failed read produces no sample (4), and fewer than 2 valid samples is
   unreadable; IceCore's samples carry a non-optional frame list, where empty is
   unreadable → the two stay distinct, as 3.5 requires.
5. During T4 (2026-09-19): non-maximum suppression with a fixed radius reported
   **6 clusters** for one solid patch of ink — every offset across it scores
   equally, so suppression keeps one every radius + 1 px — and a single weak hit
   read as `ambiguous` → candidates are clustered into contiguous runs instead
   (a gap over the radius starts a new cluster), with the best-scoring offset as
   the representative → two real glyphs still cluster separately, because their
   candidate offsets differ by at least a glyph width, which the parameters keep
   above the radius; a test pins twins 11 px apart as `ambiguous(2)`.
6. During T9 (2026-09-19): the recorded helpers `T` and `P` draw a **solid
   two-colour square** (`probes/safewidth/Sources/swhelper/main.swift:36-46`), so
   inside their own ink bounding box there is no background at all and
   `ItemTemplate.cut` rejects them with `.tooLittleBackground` — the invariant
   working as designed, not a defect → the replay can exercise the fold, the
   stability rule, the pill and the Teams badge on recorded pixels, but not the
   recorded target's presence; and **the live helpers of T13 must draw a stroked
   glyph, never a filled block**. A general limitation follows, and is recorded in
   FINDINGS: an item whose glyph fills its own bounding box cannot be templated
   and is reported `notObserved`, never hidden or restored.
7. During T9: `StripAssessor` calibrates ink itself and takes no injected ink, so
   the plan's "replay ink = calibrated ink plus the helpers' marker colours"
   (3.1) cannot be passed in; the replay reassembles the same public rules with
   its own ink instead of modifying IceCore. Kept as it stands: an injection hook
   exists only for replaying colours that no longer matter now that 6 has ruled
   the recorded markers out.
8. During T14, first live attempt (2026-09-19): **capturing the bar summons a
   ≈ 20 pt `MenuBarAgent` indicator** left of the third-party items, which goes
   again a few seconds after the capturing stops (`x ≈ 1143`, ink drawn in the
   fold region). Plan 6.1's "abort if any `MenuBarAgent` frame sits left of the
   leftmost third-party item" therefore aborted every run before it began, and a
   run cannot avoid capturing → the abort now fires only for the chevron's width
   (17.5 ± 0.5) and the microphone pill's (16 ± 0.5); the harness warms up with
   24 captures before the pre-flight baseline so the indicator is already in the
   baseline's agent set; and IceCore counts a **listed** agent item's own span as
   explained ink, so only ink with no frame at all is unexplained. Anything that
   arrives, leaves or moves afterwards is still caught by the one-to-one rule.
9. During T14, third live attempt: pass 2 was "≥ 90 % of the template's core ink
   is still ink", which is **one-sided** — any dense patch of ink on the bar
   satisfies a sparse glyph, so the helper that had just been hidden read
   `weakMatch`, and `notDrawn` was unreachable → pass 2 is now the same trimap
   at a looser threshold (0.12), which requires the glyph's negative space too.
   The threshold sits under the ink share a vacated slot mismatches by
   (`coreInkFactor × foundThreshold` = 0.16), so "gone" stays reachable; the
   invariant is enforced in `DetectorParameters.isValid` and pinned by tests.
   `inkPresenceMin` is retired.
10. During T14: an observation started 0.47 s after `hide` caught one sample
    before the change and one after, and the settle rule correctly called it
    unstable → the harness waits 1 s after every toggle. The rule was not
    touched.
11. **MEASURED during T14:** an item hidden by its own app with
    `NSStatusItem.isVisible = false` leaves `AXExtrasMenuBar` **entirely** on
    macOS 27 — it is not parked at x ≈ 7, y ≈ 1104 as FINDINGS records for other
    ways of hiding → control (b) passes on either outcome, as long as no
    template is cut from a hidden item, and the outcome is recorded.
12. During T14: the pre-flight baseline read `unreadable` about half the time
    (the flickering indicator drawn before Accessibility lists it) → the
    observation is retried up to 5 times, one second apart, instead of the rule
    being weakened; and a pre-flight baseline that accepts **no** user item now
    aborts the run, because a safety monitor watching nothing is not a
    safeguard — the mistake the 2026-09-18 runs shipped twice.
13. During the post-implementation review (2026-09-19): the pre-flight baseline
    and the room check now both warm up with captures before reading, because
    the indicator our own capturing summons fades within a second or two of the
    last capture — the gap while the helpers launch was enough for the agent set
    to differ from the baseline's through the instrument's doing rather than the
    bar's. The rule was not relaxed.

## Deferred, with reasons

- `vzreplay`'s `ManualAssess` still recomposes `StripAssessor.observe` by hand.
  The hook it lacked now exists (`StripAssessor.baseline(…, ink:)` and a public
  `BaselineResult.init`), so the migration is mechanical, but it changes the
  audit harness itself and the run that validates it is the replay — worth doing
  deliberately, not at the end of a session. Until then the duplication is a
  drift risk in the one place whose job is to catch drift.
- `ThirdPartyBaseline.take` and `VisibilityObserver.baseline` accumulate samples
  with the same policy in two places.
- `StripAssessor.observe` indexes before/after captures as `index * 2` and
  `index * 2 + 1` beside a tuple array that already models the pairing.
