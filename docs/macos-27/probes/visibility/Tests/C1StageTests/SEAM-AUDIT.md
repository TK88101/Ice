# SEAM-AUDIT -- rework #7a (G1, G7)

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
- **G1 -- fixed by this rework**: `discoveryResult()` now returns
  `ownRead: .notRead`, matching the live harness exactly. This is the
  defect the whole rework is about: `C1Discoverer.discover`
  (`Sources/C1Live/C1Discoverer.swift:57`) copies `ownRead: set.ownRead`
  unchanged into the set it composes, so a live run's composed set also
  carries `.notRead`. `HidingVerification.prepare` runs `CheckPlan.make` on
  that composed set (`Packages/MenuBarDiscovery/Sources/MenuBarDetectorFeed/HidingVerification.swift:131`),
  whose first guard is `set.ownRead == .ok`
  (`Packages/IceCore/Sources/IceCore/CheckPlan.swift:25`) -- otherwise
  `.skip(.dividerUnavailable)`. Step 3 can therefore never reach `.ready`
  on a live run. With the fake now honest, every existing I7 scenario now
  fails the same way (see the worker report); the fix -- `C1Discoverer`
  composing `ownRead: .ok` -- is a one-line source change, left to the
  next worker, and pinned by the new `C1LiveTests.C1DiscovererTests
  .ownReadNotReadStillPassesCheckPlan` case.
- **Difference, acceptable, not fixed**: `completeness` is always
  `.complete` in the fake (no per-pid AX-read timeout is modelled at the
  `ItemCatalog` layer -- capture/AX-read failures are modelled separately,
  at the `Sampler`/`StripCapturer`/`MenuBarAXReading` layer, via the
  `.captureFailure`/`.discoveryHang` knobs). `staleProcesses`/`dropped`/
  `systemElements` are always empty. Every fake item is `.declared`/
  `.onBar` (never `.parked`/`.stacked`/`.positional`) -- those states are
  I1's own scope (`C1CoreTests`, already 100% covered pure logic), not
  I7's.

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
  real `Process` spawn) / `LiveHelperDefaults` (`defaults` domain read).
- **Fake**: `FakeHelperLauncher` (every bundle validates, nothing is ever
  already running) / `FakeHelperDefaults` (every domain reads back empty).
- **Difference, acceptable, not exercised**: no scenario models a
  non-empty or unreadable helper preference domain (Amendment v4 P1's own
  teardown-failure path). Noted as a gap, not fixed.

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
