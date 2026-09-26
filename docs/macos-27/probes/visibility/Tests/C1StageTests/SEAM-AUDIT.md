# SEAM-AUDIT -- rework #7a (G1, G7), amended by rework #8 (parked items, placement gate, teardown fold rule) and rework #8a (placement by the helpers' own preferred position)

For every field `C1StageEnvironment` declares (`Sources/C1Stage/C1StageEnvironment.swift`):
the live composition (`Sources/vizprobe/StageC1Live.swift`, `C1LiveWiring.make()`)
against the fake composition (`Tests/C1StageTests/FakeC1Environment.swift`,
`FakeC1EnvironmentFactory.make`), and where they differ, why that is
acceptable or was fixed by this rework. No third-party app name appears
below -- only file:line and counts, per the brief's hard rule.

## `capturer`

- **Live**: `CGWindowListStripCapturer()` -- a real screen capture of the
  owner's own bar (about 1728x33 pt, scale 2), `nil` on a capture failure
  (e.g. screen-recording permission revoked, no display).
- **Fake**: `FakeStripCapturer(world:caffeinate:)` -> `world.image()` -- a
  synthesized 320x12 pt (scale 2) bitmap, real ink at real (if smaller)
  positions, so `Ink`/`TemplateMatcher`/`StripAssessor` (IceCore, frozen)
  run unmodified against it. `nil` only via the `.captureFailure` knob.
- **Difference, acceptable**: absolute strip size and true pixel content
  differ; every position/frame the fake reports is internally consistent
  with what it draws, which is what the detector code actually depends on.
  Rework #7a also has it record `caffeinate.recordCapture()` before every
  capture (G5 audit, new).

## `discoverer` (the raw, pre-`C1Discoverer` pass)

- **Live**: `MenuBarDiscoverer(apps: HarnessProcesses(base: LiveRunningApps()), reader: LiveExtrasReader(), display: LiveDisplay(), isTrusted: { AXIsProcessTrusted() }, ownIdentifiers: StageRun.ownIdentifiers, now:...)`.
  `HarnessProcesses.processes()` (`Sources/vizprobe/StageRun.swift:32`)
  drops every `isSelf` process before `ItemCatalog.build` ever sees it, so
  `ownRead` (`Packages/IceCore/Sources/IceCore/ItemCatalog.swift:86`) stays
  at its initial `.notRead` forever -- neither the `.failed` branch (:99)
  nor the `.ok`/`.identifiersMissing` branch (:119) can run for a pid that
  was filtered out before the loop. `completeness` is
  `.incomplete(failedPIDs:)` whenever any real AX read timed out (:167).
- **Fake (before this rework)**: `FakeDiscoverer(world:)` ->
  `world.discoveryResult()` hard-coded `ownRead: .ok, completeness: .complete`.
- **G1 -- fixed by rework #7a (honest fake) and rework #7b (the source
  fix)**: `discoveryResult()` returns `ownRead: .notRead`, matching the
  live harness exactly. `C1Discoverer.discover`
  (`Sources/C1Live/C1Discoverer.swift`) used to copy `ownRead: set.ownRead`
  unchanged into the set it composes, so a live run's composed set also
  carried `.notRead`, and `HidingVerification.prepare`'s own `CheckPlan.make`
  (whose first guard is `set.ownRead == .ok`,
  `Packages/IceCore/Sources/IceCore/CheckPlan.swift:25`) always returned
  `.skip(.dividerUnavailable)` -- step 3 could never reach `.ready` on a
  live run. Rework #7b's fix: `C1Discoverer` now composes `ownRead: .ok`
  unconditionally (it supplies its own divider from the spacer's `minX`,
  so the raw harness's self-filtered read is irrelevant to whether the
  composed set can be checked at all), pinned by
  `C1LiveTests.C1DiscovererTests.ownReadNotReadStillPassesCheckPlan` (now
  green) and every I7 scenario (which now reaches step 3's own cycles
  instead of aborting there on every run).
- **Difference, acceptable, not fixed**: `completeness` is always
  `.complete` in the fake (no per-pid AX-read timeout is modelled at the
  `ItemCatalog` layer -- capture/AX-read failures are modelled separately,
  at the `Sampler`/`StripCapturer`/`MenuBarAXReading` layer, via the
  `.captureFailure`/`.discoveryHang` knobs). `staleProcesses`/`dropped`/
  `systemElements` are always empty. Every fake item is still `.declared`
  (never `.positional`) and every drawn item is `.onBar` (never
  `.stacked`) -- those two remain I1's own scope (`C1CoreTests`, already
  100% covered pure logic), not I7's.
- **G0 (Amendment v8) -- fixed, was wrong**: this section used to say every
  fake item was `.parked`-free too, "those states are I1's own scope, not
  I7's." That was wrong: `C1Discoverer` and `StageC1Baseline` (both
  `C1Live`/`C1Stage`, not I1) read `.parked` directly, and the owner's own
  bar always lists 2-3 parked items (frames below the bar) in every
  recorded census -- a live seam I7 must model, not I1's pure-logic scope.
  `C1Discoverer.discover` counted a parked item as "left of the divider"
  (its own count, not a position filter), which rejected every real
  composed set on the owner's bar (crosscheck-rework7.json finding #0).
  `FakeBarWorld` now lists 3 fixed parked items (`FakeBarWorldLayout.
  parkedMinXs`/`parkedMinYs`, matching the recorded frames -- numbers
  only, per the hard rule) in every scenario's discovery and AX reads,
  always present, never drawn (a parked item's frame sits below the bar,
  so it contributes no ink); `C1DiscovererTests` and `C1CoreTests.
  PlacementGateTests` cover the pure decision, and every I7 scenario now
  exercises `C1Discoverer`'s parked-item filter and `StageC1Baseline`'s
  parked exclusion from `ownerItemIDs`/the untemplated candidates on every
  run, not only a dedicated case.

## Amendment v8's placement gate and teardown fold rule (new, rework #8)

- **Live premise, was false**: section 2 says "each new item lands at the
  left end"; a fourth cross-check (crosscheck-rework7.json finding #1)
  found 1-3 owner items drawn left of the helpers in every recorded run
  on the owner's bar instead. `StageC1.step2bPlacementGate()` (new,
  `Sources/C1Stage/StageC1Placement.swift`) now runs right after the
  launches, before `step3Baseline` and before any `length`: one discovery
  pass, `C1Core.PlacementGate.check(helperMinXs:onBarOwnerMinXs:)` (pure,
  100% covered by `C1CoreTests.PlacementGateTests`) decides whether every
  on-bar owner item sits right of every helper. A failure reaps all three
  helpers, records `placement.notLeftmost` (count only), and ends
  INCONCLUSIVE ("helpers not leftmost: N owner items left") through the
  ordinary `.abort` -> `runTeardownAndDecide` path -- never a safety stop,
  since no trip ever fires.
- **Fake**: `FakeBarWorld(ownerItemsLeftOfHelpersCount:)` (0...3, default
  0) draws that many owner items well left of every helper, always
  visible, never gated by a fault knob (`FakeBarWorldLayout.
  ownerLeftOfHelpersBaseX`/`ownerLeftKey`/`ownerLeftX`) -- the recorded
  live placement. The default (`0`) keeps every existing scenario's own
  "helpers land leftmost" layout as Amendment v8's own *post-placement*
  case (scenario 1 etc.); `I7AmendmentV7Tests.
  helpersRightOfOwnersEndsInconclusiveBeforeAnyLength` exercises the new
  layout.
- **Teardown fold rule**: the staged teardown's Protected-only fold read
  (F2, Amendment v6) assumed nothing is ever left of Protected once Target
  and the spacer are gone -- true once the placement gate has passed, but
  not proof against everything (e.g. a fold appearing at rest for reasons
  unrelated to C1). `StageC1Teardown.runTeardownAndDecide` now records a
  failing read (`teardown.protectedFold.mismatch`, with `lengthEverSent`)
  but only escalates it to a teardown mismatch once `StageC1.lengthEverSent`
  is `true` -- tracked in `withExpansionWindow`, mirroring
  `C1ExpansionDriver.expand(to:)`'s own `!dry` guard exactly. Modelled by
  `FakeBarWorld(injectPrepareRejection: true, unreadableFoldAfterAbort:
  true)`: the fold ghost only starts appearing once the (harmless,
  G2-style) prepare rejection has already fired, i.e. after the rest
  baseline's own capture loop finished clean and before any `length` --
  see `I7AmendmentV7Tests.unreadableFoldBeforeAnyLengthIsNotATeardownMismatch`.
- **Split**: `FakeBarWorld.swift` was at 796 lines before this rework;
  split into `FakeBarWorld.swift` (state, command handling, capture/AX/
  discovery), `FakeBarWorldSupport.swift` (`FakeSpacerState`, `FaultKnob`,
  `VirtualClock`, `SimulatedLatency`) and `FakeBarWorldLayout.swift`
  (every fixed position/identity/shape, as a `static` extension of
  `FakeBarWorld` -- not a new type) to stay under the 800-line cap with
  room for the additions above.

## `ownerAXReaderFactory` / `verificationAXReaderFactory`

- **Live**: two different concrete adapters -- `LiveMenuBarAXReader`
  (owner) and `DiscoveredFrameReader` (verification), each with its own
  per-call/per-sample timeout behaviour.
- **Fake**: the same `FakeAXReader(world:)` for both factories.
- **Difference, acceptable**: I7 tests stage-level orchestration and
  timing, not either live reader's own internal walk/timeout mechanics
  (covered by their own frozen unit tests, or -- per Codex round 7b's own
  refutation of the "C1AXExecutor bound" finding -- not a live risk at all
  on the measured owner-bar data).

## `geometryProvider`

- **Live**: `NSScreen.main.flatMap { BarGeometry(screen: $0) }` -- a real
  screen, which may carry a camera notch.
- **Fake**: a fixed `FakeBarWorld.geometry` (320x12 pt, scale 2, `notch: nil`).
- **Difference, acceptable, not exercised**: no notch is modelled, so
  `RoomGuard.hasRoom`'s own notch-adjacent branch is untested by I7 (it is
  I1/IceCore's own scope). Noted as a gap, not fixed.

## `extrasScanner`

- **Live**: `BarScan.items()`, a real Accessibility scan of every
  extras-menu-bar item.
- **Fake**: a fixed one-element array, one `com.apple.MenuBarAgent`-bundled
  item at `(FakeBarWorld.indicatorX, width: FakeBarWorld.indicatorWidth)`
  -- matching `detectIndicatorFrame()`'s own real selection rule (the
  leftmost 14-30 pt-wide `MenuBarAgent` item; Codex round 7b's own
  refutation of the "detectIndicatorFrame is not StageRun's rule" finding
  confirms this rule, not `StageRun`'s, is what the stage actually uses).
- **Difference, acceptable, not exercised**: no scenario models the
  indicator moving or disappearing entirely (an absent indicator, or one
  outside the 14-30 pt band). Noted as a gap, not fixed.

## `helperLauncher` / `helperDefaults`

- **Live**: `LiveHelperLauncher` (real bundle validation, `NSWorkspace`,
  real `Process` spawn) / `LiveHelperDefaults` (`defaults` domain
  read/write; rework #8a adds `write(_:key:value:)` -> `HelperDefaults.write`,
  `defaults write <bundleID> <key> -float <value>`).
- **Fake**: `FakeHelperLauncher` (every bundle validates, nothing is ever
  already running) / `FakeHelperDefaults` (rework #8a: now forwards
  `forget`/`keys`/`write` to `FakeBarWorld`'s own `defaultsDomains` model
  instead of a stateless "every domain reads back empty" stub, so a
  "honoured" scenario can read back exactly what `StageC1` wrote, and
  `world.defaultsLog` records every write/forget call in order).
- **Difference, acceptable, not exercised**: no scenario models a
  non-empty or unreadable helper preference domain (Amendment v4 P1's own
  teardown-failure path). Noted as a gap, not fixed.

## Amendment v8a -- placement by the helpers' own preferred position (rework #8a)

- **Live premise, unverified**: Ice writes `NSStatusItem Preferred Position
  <autosaveName>` (a `CGFloat`) into its own domain before creating a
  control item, with `0`/`1` for its own visible/hidden items
  (`Ice/MenuBar/ControlItem/ControlItem.swift:645-660`, "added before
  existing items"). Whether -- and how -- macOS 27 actually honours this
  key for a freshly created third-party `NSStatusItem` is **unverified**;
  this rework models it as "the value is points from the bar's own right
  edge, larger = further left" (the brief's own INFERRED assumption) --
  never confirmed against a real run. Only a placement-only dry rehearsal
  on the owner's own bar decides; until then this whole mechanism is
  modelled, not proven.
- **C1Core (pure, 100% covered)**: `PlacementPlan.plan(onBarOwnerMinXs:barRightEdge:notchRightEdge:targetWidthPt:spacerWidthPt:protectedWidthPt:)`
  (`Sources/C1Core/PlacementPlan.swift`) -- Target/spacer/Protected laid
  out contiguously, left to right, `marginPt` (6.0) left of the nearest
  on-bar owner item (or the bar's own right edge, when there is none),
  refusing (`nil`) when that would not clear `notchRightEdge`.
  `PreferredPositionKey.stringKey(autosaveName:)` (`PreferredPositionKey.swift`)
  restates Ice's own key format (this package cannot import the `Ice`
  target). `PlacementGateTests`/`PlacementPlanTests`/`PreferredPositionKeyTests`
  cover both, including edges (no owner items, exactly-enough room, one
  point short, a notch consuming the whole bar, non-positive widths).
- **StageC1 (new pre-launch step)**: `step1bPlacementPlan()`
  (`Sources/C1Stage/StageC1Placement.swift`), inserted into `run()`'s
  first step loop (before any helper exists) -- one discovery pass (the
  same bounded executor every other post-launch read uses), `.onBar`-only
  filtering (parked already excluded, no helper yet to filter out
  either), then `PlacementPlan.plan` with `C1HelperWidth.plainItemPt`
  (12.0, restated from `vzhelper`'s own `itemLengthPt`) for Target/Protected
  and `parameters.chevronWidthPt` (17.5, IceCore's own measured constant)
  for the spacer. A refusal ends the run INCONCLUSIVE here, before any
  process ever launches (`"no room for the helpers left of N owner
  item(s)"`, `run()`'s own generic first-loop `.abort` handling already
  promotes this to the top-level verdict, prefixed `"setup:
  step1b.placementPlan: "`) -- nothing to reap yet.
- **`launchAndDiscover` (`StageC1Setup.swift`)**: each of the three
  launches now writes that helper's own key
  (`C1AutosaveName.target`/`.spacer`/`.protected`, all unique; Protected
  and the spacer share `C1HelperRole.protected`'s domain, kept apart only
  by name) into that helper's own domain -- never the owner's -- before
  the process launches, then passes `--autosave <name>` so `vzhelper` sets
  `NSStatusItem.autosaveName` the same way
  `Ice/MenuBar/ControlItem/ControlItem.swift` does, in the same order
  (name before the AX identifier). `vzhelper --role target|reference|spacer`
  did not accept `--autosave` at all before this rework (only the older,
  unrelated `--items` form did); it does now.
- **Bug found and fixed while implementing this (own reasoning, not a
  cross-check)**: `launchAndDiscover`'s old, pre-write `forget(bundleID)`
  step ran unconditionally before every launch (its own comment: "neither
  role ever sets `--autosave`, so this never has data to lose" -- true
  before this rework, false now). Protected and the spacer share one
  domain and launch in that order (Protected, then the spacer,
  `step2Launch`), so the spacer's own launch was about to `forget()` that
  *same* domain again, wiping Protected's just-written key before
  teardown was ever meant to. Harmless to the *live* item itself (a real
  `NSStatusItem` only reads its stored preferred position once, at its own
  creation -- Protected's is already resolved, synchronously, before the
  spacer's process even starts, since launches are sequential and
  confirmed), but it breaks two things this rework needs: the "forgotten
  ... at teardown" invariant (a key must not vanish mid-run), and the
  fake's own honoured-position model, which re-reads the domain on every
  capture rather than caching a value at "creation." Fixed with a new
  `forgetDomainFirst` parameter (default `true`; the spacer's own call
  passes `false`, since Protected's launch, always first, already forgot
  and verified that shared domain empty this run) -- `launchAndDiscover`
  now only *adds* the spacer's key alongside Protected's, never wiping it.
  Caught before any test ran, by tracing the shared-domain write order;
  confirmed by first reproducing the failure live (the honoured-PASS
  scenario below came back INCONCLUSIVE "helpers not leftmost" on the
  unfixed code, exactly as this trace predicted) and then green after the
  fix.
- **Top-level reason (Amendment v8a's own fix)**: `step2bPlacementGate()`'s
  own "not leftmost" abort used to reach `runTeardownAndDecide` ->
  `RunAccounting.decide` with no way to carry its own reason string --
  the top-level verdict fell through to the generic "preflight never
  passed or captures stayed unreadable," and only step evidence
  (`placement.notLeftmost`) ever saw the real count. `StageC1.placementGateFailureReason`
  is now threaded into `RunAccounting.Input`, and `decide` returns
  `.inconclusive(placementGateFailureReason)` verbatim when set (still
  overridden by a safety stop, itself checked first) -- pinned by two new
  `RunAccountingTests` cases and `I7AmendmentV7Tests.helpersRightOfOwnersEndsInconclusiveBeforeAnyLength`'s
  own strengthened exact-string assertion.
- **Fake**: `FakeBarWorld(honoursPreferredPosition:noRoomOwnerMinX:)`
  models both outcomes. "Honoured": `resolvedXLocked(bundleID:autosaveName:fallback:)`
  reads back the exact value this run's own `launchAndDiscover` wrote
  (`Self.geometry.widthPt - value`, the inverse of `PlacementPlan`'s own
  conversion) and renders the helper there instead of its old fixed
  position; `honouredPreferredPositionOnRealisticLayoutPasses` proves the
  whole pre-launch-plan -> write -> honoured-render -> post-launch-gate
  chain reaches the same PASS `scenario1_realisticCleanBarPass` already
  proves once the gate is clean, and `dryHonouredPreferredPositionIsGateClean`
  proves `--dry` does not change any of that. "Ignored" (the default,
  `honoursPreferredPosition: false`): every existing scenario keeps
  rendering at its old fixed position regardless of what gets written,
  unaffected by this whole rework -- confirmed by every pre-existing I7
  scenario staying green with no assertion weakened. `noRoomOwnerMinX`
  is the dedicated "no room" fixture (an owner item at minX 10, too close
  to the left edge for any helper width/margin combination to clear).
- **Rebased fixture, not a weakened assertion**: `ownerItemsLeftOfHelpersCount`'s
  own layout (`FakeBarWorldLayout.ownerLeftOfHelpersBaseX`/`ownerLeftOfHelpersSpacingPt`)
  moved from `40.0`/`15.0` to `120.0`/`8.0`. At `40.0`, the three helpers'
  combined width (41.5 pt) alone already exceeded that base X, so
  `step1bPlacementPlan`'s own new pre-launch check would refuse *before
  any launch* on that exact fixture -- a real, and arguably more correct,
  earlier failure mode, but not the one `helpersRightOfOwnersEndsInconclusiveBeforeAnyLength`
  is testing (the post-launch gate, with helpers actually launched and
  reaped). `120.0`/`8.0` leaves enough room for a valid pre-launch plan
  (so that test still reaches the post-launch gate, unchanged in every
  other respect) while staying left of the helpers' old fixed positions
  (150/190/230) for the "ignored" render to still trip that same gate.
  Every assertion in that test still holds, unchanged, plus new ones
  (the exact top-level reason string, the write/forget log).
- **Not exercised**: no notch is modelled in the fake bar at all
  (`geometryProvider`'s own existing gap, above) -- `step1bPlacementPlan`'s
  own `notchRightEdge` is always `0` in every I7 scenario. `PlacementPlan`'s
  own notch-refusal branch is covered only by `PlacementPlanTests`
  (C1Core, pure), not by I7. Noted as a gap, not fixed.

## Amendment v9 -- sort-key placement values, real pitch, gate, signal precedence (rework #9)

- **New primary reading, still unverified**: a fifth cross-check
  (crosscheck-rework8.json #0/#4) found the owner's own recorded stored
  `NSStatusItem Preferred Position` values contradict the old
  right-edge-distance reading and instead follow the items' own
  left-to-right order (`~/IceReverse-evidence/20260925-092244-icerun/before/app-statusitem-keys.txt`).
  `PlacementPlan` now treats the values primarily as **sort keys**: each
  helper's own value is `floor + step` (`sortKeyStepPt`, 100.0), where
  `floor` is the largest of `historicalMaximumStoredValue` (5772.0) and
  every on-bar owner's own scanned stored value. This is still a plan, not
  a promise -- `step2bPlacementGate`'s own post-launch read decides either
  way.
- **C1Core (pure, 100% covered)**: `PlacementValueScan` (new;
  `Sources/C1Core/PlacementValueScan.swift`) classifies one on-bar owner's
  own raw scan into numeric values or one of four issues (`unreadable`,
  `nonNumeric`, `missing`, `attributionUnclear`); `PlacementPlan.plan`'s
  own signature changed to take `[PlacementValueScan.Classified]` plus
  each helper's own real *occupied* pitch (`targetOccupiedPt`/
  `spacerOccupiedPt`/`protectedOccupiedPt` -- 28/32/28,
  `C1HelperWidth.occupiedPitchPt`/`.spacerOccupiedPitchPt`,
  crosscheck-rework8.json #1) rather than nominal AX widths, and returns
  `PlacementPlan.Outcome` (`.planned`/`.refused`) instead of `Result?`, so
  a scan-uncertain refusal and a no-room refusal are distinguishable.
  `PlacementGate.check` now takes a `Reading` (each helper's own minX,
  `nil` when off the bar or folded) and requires the internal order
  (`Target < spacer < Protected`) explicitly, returning one of three
  distinct `FailureReason`s; `PlacementGate.materiallyAgree` is the new
  two-consecutive-reads check. `PlacementValueScanTests`/`PlacementPlanTests`/
  `PlacementGateTests` cover all of this, including the sort-key floor
  math, every scan issue (deterministic leftmost-first when several
  owners have one), and `materiallyAgree`'s own tolerance/owner-order
  handling.
- **StageC1 (`StageC1Placement.swift`, rewritten)**: `step1bPlacementPlan`
  now also reads each on-bar owner's own bundle id
  (`item.process.bundleID`) through the new
  `environment.ownerPreferenceScanner` (`C1OwnerPreferenceScanning`,
  `C1StageEnvironment.swift`) before calling `PlacementPlan.plan`, and
  records the on-bar owner minXs and the floor used. `step2bPlacementGate`
  now loops discovery reads (bounded by `placementGateAgreementBoundSeconds`,
  5.0) until two consecutive ones `materiallyAgree`, recording every pass
  (`placement.gateRead`) before deciding (`placement.gateFailed`, with a
  reason distinct per `FailureReason` case).
- **Live scanner (new)**: `LiveOwnerPreferenceScanner`
  (`Sources/vizprobe/StageC1Live.swift`) -- `defaults export <bundleID> -`,
  read-only, with a 2 s timeout (`DispatchGroup.wait`, `process.terminate()`
  on timeout) and a `maxMatchingKeys` (16) cap on how many matching keys
  it returns -- the "bounded in time and count" the hard rules ask for.
  Never exercised live (the hard rules forbid it); exercised only through
  `FakeOwnerPreferenceScanner` in I7.
- **Signal precedence (`StageC1.swift`)**: `run()`'s first step loop now
  re-checks `safetyStop` after a step's own `.abort`, not only before the
  next step begins -- `step1bPlacementPlan` was the first pre-launch step
  whose own body could turn a terminal state into a plain abort
  (crosscheck-rework8.json #5), which used to report a re-runnable
  INCONCLUSIVE (exit 2) over a recorded safety-stop-needing-attention
  (exit 3).
- **Fake**: `FakeBarWorld.honoursPreferredPosition: Bool` became
  `placementHonoring: PlacementHonoring` (`.ignored`/`.distance`/
  `.sortKey`) -- `.distance` is the old inversion (kept only for the
  dedicated misorder fixture below; its own render numbers are no longer
  physically sensible once `PlacementPlan` writes sort-key-shaped
  magnitudes, so the two pre-existing "honoured" I7AmendmentV7Tests cases
  moved to `.sortKey`, the reading Codex round 9b ruled primary).
  `.sortKey` ranks a helper's own written value against the other
  helpers' and the dedicated stale-owner fixture's own fixed value
  (`sortKeyPackedXLocked`), packing at `sortKeyPitchPt` (28, the real
  measured pitch) from `sortKeyAnchorX` (45 -- picked to clear
  `IceCore.RoomGuard.minimumFreeRoom`, 41 pt, once the AX-frame
  convention's own 1 pt trim is subtracted). `staleOwnerPresent` adds the
  dedicated on-bar owner item pre-seeded with the recorded 5703;
  `ownerPreferenceUnreadable` marks the templated owner's own domain
  unreadable; `forceHelperMisorder` (only effective with `.distance`)
  swaps Target's and Protected's own rendered positions, for the
  dedicated misorder fixture. Every owner-family domain
  (`ownerKey`/`ownerLeftKey`/`noRoomOwnerKey`'s own namespaces) is now
  pre-seeded with a small, legible default stored value in `init` (never
  through `defaultsWrite`, so it never shows up as something a run itself
  wrote) -- without this, every existing I7 scenario's own templated/
  untemplated/no-room owner items would make `step1bPlacementPlan` refuse
  as `missing` before ever reaching the code each of those scenarios
  actually means to test.
- **New I7 coverage (`I7AmendmentV9Tests.swift`)**: the sort-key mode with
  a stale on-bar owner value still reaching PASS at the 28-pt pitch, a
  forced misorder ending INCONCLUSIVE with its own distinct reason, an
  unreadable owner scan refusing before any launch, and a signal during
  step1b's own discovery ending SAFETY STOP NEEDING ATTENTION rather than
  a re-runnable INCONCLUSIVE.

## `pump`

- **Live**: `LivePump` -- `Pump.run`/`Pump.blocking` (a real run-loop
  pump), `Thread.sleep`, `ProcessInfo...systemUptime`.
- **Fake**: `FakePump(clock:)` -- a shared `VirtualClock` `sleep`/`run`
  advance directly; `blocking` bridges via a plain `DispatchSemaphore` and
  `Task.detached`, never `RunLoop.main` (documented in its own comment: no
  I7 test runs on the main thread with a run loop to pump).
- **Difference, acceptable**: this is I7's whole reason for existing --
  documented and intentional.

## `caffeinate`

- **Live**: `LiveCaffeinate` -- a real `caffeinate -d -w <pid>` process.
- **Fake**: `FakeCaffeinate` -- counts `start()`/`stop()`, and (new, G5
  audit) tracks whether it is currently "running" and logs that state at
  every capture `FakeStripCapturer` takes.
- **Difference, acceptable**: no real process; the ordering property G5 is
  about (caffeinate must outlive every verdict-deciding read) is exactly
  what the new `captureRunningLog` lets a test assert directly, without a
  real timer.

## `evidenceFactory`

- **Live**: `LiveEvidenceFactory` -> `LiveEvidence` (files under
  `~/IceReverse-evidence`).
- **Fake**: `FakeEvidenceFactory` -> one in-memory `FakeEvidence`, asserted
  against directly (`allRecords()`, `lastVerdict()`, `terminalReasons()`).
- **Difference, acceptable**: documented and intentional.

## `isTrusted`

- **Live**: `{ AXIsProcessTrusted() }`.
- **Fake**: `{ true }` always.
- **Difference, acceptable**: I7 never tests the untrusted-process path
  (a setup precondition, not an orchestration concern); Accessibility
  trust is a one-time OS grant, not something a live run can lose mid-run
  without the whole process losing all its other AX reads too.

## `discoveryExecutorBoundSeconds` (G7, rework #7b)

- **Live**: defaults to `C1DiscoveryExecutor.boundSeconds` (3.0 s, live
  default unchanged) -- `C1StageEnvironment`'s own default parameter value,
  so `C1LiveWiring.make()` needs no change to keep it.
- **Fake**: `FakeC1EnvironmentFactory.make(...)`/`I7.run(world:...)` both
  default the same way, but a test can now pass a genuinely short bound
  (`discoveryHang`'s own scenario, 3g, pairs a 0.05 s bound with a 0.2 s
  fake hang instead of paying the live default's real 3.0 s+).
- **Difference, acceptable, intentional**: exactly the point of making
  this injectable -- I7 no longer needs to pay real wall-clock time past
  a hard-coded live bound to exercise a discovery timeout.

## Calibration mapping (G8)

See `SimulatedLatency`'s own doc comment in `FakeBarWorld.swift` for the
full reconciliation of `captureSeconds`/`axReadSeconds`/`discoverySeconds`
against the brief's own per-operation figures (observe ~0.43 s, verify
~7.2 s, prepare ~11.5 s, discovery pass 36.5 ms). In short: bumping
`captureSeconds` from rework #6a's screen-capture-only 6 ms to the
duration lens's own residual per-capture estimate (~30 ms) is *sufficient*
-- the real `VisibilityObserver`/`HidingVerification` call counts and
sleeps already in `Packages/MenuBarCapture`/`Packages/MenuBarDiscovery`
(2 samples x (capture, AX, capture) + `minSampleSpacing` for an observe;
24 x `warmUpSpacing` + a `baselineMinSamples`/`baselineMinSpan`-bound
`baseline()` call for a prepare/verify's own warm-up) reproduce the
brief's figures on their own, with no additional charge and no double
count.
