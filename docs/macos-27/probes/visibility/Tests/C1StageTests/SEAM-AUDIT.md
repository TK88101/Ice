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
