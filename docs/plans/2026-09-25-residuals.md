# Plan — the ax-discovery residuals: deferred cleanups, T6 re-freeze, verify step 6

Status: **v3, final** (v1 + Codex round 1, 12 findings; round 2: all three contested rulings withdrawn, one new P1 adopted -- Appendix A; Jev, Appendix B). Branch `wip/first-run` (HEAD `112fd04`). Follows
`2026-09-23-ax-discovery.md` (Deviation 10's deferred list, Progress) and the
first run (`2026-09-24-ice-first-run.md`, FINDINGS "Ice itself on the user's
bar"). Recon: workflow `wf_53d5cd85-5f3` (four read-only readers; the P2 list
recovered from the 2026-09-23 session record: 37 findings from the Reuse,
Simplification, Efficiency and Altitude lenses and Codex / Opus rounds 1–3).
Basis tags: **MEASURED**, **READ**, **INFERRED**.

## 1. Goal and non-goals

**Goal.**

1. Clear the deferred cleanups named in Deviation 10 -- `PreparedVerification.generation`
   (unread), the Ice icon key threaded through four layers, section membership
   decided twice -- and every P2 of the 2026-09-23 simcodex that still applies,
   is behaviour-preserving and passes the standing constraints; record a ruling
   for every other P2.
2. Re-freeze T6's labels from a fresh read-only census and pass T6 (acceptance
   A5) again -- after the cleanups, so it is also their E2E check for discovery.
3. Run the verify stage of T8b with step 6 (two adjacent helper items), room
   permitting -- after the cleanups, so it is also the E2E check for
   `HidingVerification`.
4. Then `/simcodex`, the full test run and the evidence package.

**Non-goals.** Any change of behaviour that the first run measured (first-pass
ordering, publish frequency, what the verifier reports); anything that needs a
new line containing `getWindowBounds|isWindowOnScreen|captureWindow|setWindowID|windowID`
under `Ice/` (A8), or touches `ControlItem.swift`, `AppState.swift`,
`MenuBarLayoutSettingsPane.swift`, `Shared/`, `MenuBarItemService/` (A10); the
detector files and `Packages/MenuBarCapture` (byte-identical to `af4baf1`,
A3/A4); IceCore beyond the standard library; macOS 14–26 behaviour; running Ice
again (a re-run needs the user's approval; the Ice-layer edits are checked by
build + A8/A8b/A10 -- behaviour-preserving except R3's stated D14 correction); the committed
`probes/visibility/labels.json` (vzreplay's oracle, `30ab8b0`, a different file
from T6's labels -- its push decision stays the user's).

## 2. Tasks (each: change → test first → DoD)

Order is by dependency: IceCore, then MenuBarDiscovery, then MenuBarDetectorFeed,
then Ice, then the live checks. Test commands (scratch paths outside
`~/Documents`): IceCore `swift test --enable-code-coverage --scratch-path
/private/tmp/claude-501/icecore-build`; MenuBarDiscovery (both targets) `...
--scratch-path /private/tmp/claude-501/mbdiscovery-build`; Ice `xcodebuild
-project Ice.xcodeproj -scheme Ice -configuration Debug CODE_SIGNING_ALLOWED=NO
-derivedDataPath /private/tmp/claude-501/ice-main-build3 build` (the
registered derived data, so no new LaunchServices record); then
`docs/plans/checks/check-a8.sh`, `check-a10.sh`, the A8b greps, and A3/A4 as one
command: `git diff --exit-code af4baf1 -- Packages/MenuBarCapture` plus
`Packages/IceCore/Sources/IceCore/{DetectorParameters,Ink,StripImage,Template,TemplateMatcher,CaptureStability,FoldWitness,StripAssessor,MenuBarItemVisibility,MenuBarItemCacheState}.swift`
(identical at `112fd04`).

**Test-first for a refactor** (Codex round 1): before each behaviour-preserving
change, a *characterization* test pins today's behaviour and is run green on
the old code; the refactor keeps it green. A compile failure against a new
API is only the red of that API's own test, never the evidence of safety.

| # | what | where | test first | DoD |
|---|---|---|---|---|
| R1 | **section membership once at prepare time**: one IceCore function `CheckPlan.sectionMembers(set:sectionMap:sections:) -> [DiscoveredItem]` = every item of `set.items` whose mapped section is requested, **parked included**, in set order (exactly `rosterTargets()` today); `CheckPlan.make` iterates it and still drops `.parked` itself; `runPrepareBody`'s skip rosters use `.map(\.key)`. The verify-time re-filter in `HidingVerifier.runVerify` stays (§3 N3b) | `CheckPlan.swift:37-48`, `HidingVerification.swift:129-134` | characterization first, green on old code: a prepare skip (`noGeometry`) whose roster holds a parked, a stacked and a positional member; then `sectionMembers` unit tests | green; `rosterTargets` gone |
| R2 | **`listedItems`** (`items` + `visibleControlItem`) on `DiscoveredItemSet`, used at the three remaining hand-written sites (D06) | `ItemCatalog.swift` + sites | unit test -- red: no property | green, sites use it |
| R3 | **the Ice icon key**: drop `iceIconKey:` from `CheckPlan.make`, `HidingVerification.prepare` / `runPrepareBody`, `HidingVerifier`, `AppState+HidingCheck`; the plan reads the icon from the fresh set (`set.visibleControlItem`); drop `MenuBarItemManager.iceIconKey` and its update block. The icon's key is the own pid + a fixed identifier (D9), so the old guard `visible.key == iceIconKey` held whenever both existed; the one difference: when the cache pass had not yet published a key, the old code left candidates unbounded on the right, the new code bounds them by the icon it just read. That window is real: `MenuBarItemManager.swift:555-558` sets the key to `nil` whenever a cache pass misses Ice's icon (an own-read failure, seen once in the first run). **A deliberate semantic change**: in that window the old code broke D14 (a reference must lie left of Ice's icon); stated in the ledger | `CheckPlan.swift:21,50-53`, `HidingVerification.swift:71,96,117,144`, `HidingVerifier.swift:44,79,85,156`, `AppState+HidingCheck.swift:44`, `MenuBarItemManager.swift:25,555-558` characterization first (old code): with a matching key the icon bounds the candidates; then after the change two regression tests: the set's icon bounds them with no cached key (the changed case), and without an icon in the set they stay unbounded (unchanged) | IceCore + Feed green; Ice builds; A8/A8b/A10 pass |
| R4 | **`PreparedVerification.generation`** removed with `generationLock`, `generationCounter`, `nextGeneration()` and the parameter chain. Not quite unread (Codex round 1): the probe copies it into its evidence (`vizprobe/StageShared.swift:114`) and nothing consumes that field; the probe's `describe` drops it, so future `vzverify` / `vzdiscover` evidence lacks one field (stated in the ledger) | `PreparedVerification.swift`, `HidingVerification.swift`, `HidingVerificationTests.swift:195`, `StageShared.swift:114` | none possible (no reader); counts unchanged | Feed green; `build.sh` builds |
| R5 | **warm-up / observer / retry once** in `HidingVerification` (prepare and verify repeat them almost verbatim, D08): `makeObserver(origin:flag:)`, `warmUp(_:)`, `retrying(_:)` private helpers; retry counts, delays and cancellation checks unchanged | `HidingVerification.swift` | characterization first (old code): the capture count of warm-up + retries on each side, and early exit (fold absent at baseline, fold readable at verify) | Feed green |
| R6 | small feed cleanups: `verify`'s unreachable `.cancelled` branch → `switch prepared.state` (D10); `frames(for: baselineKeys, in: itemsByKey)` computed once (D09); one `LiveExtrasReader(readsLabels: false)` shared in `HidingVerificationLive` (D26) | `HidingVerification.swift`, `HidingVerificationLive.swift` | existing tests | Feed green |
| R7 | **cancel while `prepare` awaits discovery** → `.skip(.cancelled)`, pinned (D28; the discoverer-level cancellation is tested at `MenuBarDiscovererTests.swift:43-72`, the nil-without-cancel twin in `HidingVerificationDeviation5Tests`) | `HidingVerificationTests` | a characterization test with a blocking, cancellation-aware `Discovering` fake (no code change expected) | Feed green |
| R8 | feed access levels: `CancellationFlag`, `CancellableCapturer`, `CancellableReader`, `DiscoveredTargets` `public` → `internal` if nothing outside the module (tests use `@testable`) needs them (D20) | feed sources | build of every dependent (Ice, probes, mbdiscover) | all build |
| R9 | discovery: the cursor uses the existing `DiscoveryBox` instead of its own `NSLock` (D03, first half; moving `CancellationFlag` across modules is not done, R8 narrows it instead); `timeout: Double = 0.25` → `ReadClassifier.defaultTimeout` (D05) | `MenuBarDiscoverer.swift` | existing rotation / deadline tests (characterization: the cursor rotates across passes) | green |
| R10 | `DisplayProviding.bar()` returns `(bounds: BarBounds, origin: DiscoveryOrigin)` instead of a raw origin tuple (D07); `subtractOrigin` takes the `DiscoveryOrigin` | `DisplayProviding.swift`, `MenuBarDiscoverer.swift`, test fakes | existing discoverer tests (origin subtracted from every frame) | green |
| R11 | test fixtures once in IceCoreTests: `DiscoveryTestSupport.swift` for the `DiscoveredItem` / `DiscoveredItemSet` builders repeated across `CheckPlanTests`, `DiscoveredCachePlanTests`, `VerificationGuardsTests`, `ItemCatalogCarryOverTests` (D14, same target, precedent `StripTestSupport.swift`) | IceCore tests | the suites themselves | green, same counts |
| R12 | drop `HidingCheckStatus.summary`, a stored property nothing reads (READ: the only reader of `hidingCheckStatus` is the pane's `Text(status.message)`, `MenuBarLayoutSettingsPane.swift:103-112`); synthesized equality then compares `message`, so `AppState+HidingCheck.swift:57-61` stops republishing a status whose text did not change (D23, rounds 2 and 3). No custom `==` | `HidingVerifier.swift:14-37` | no Ice test target: build + the grep that `summary` has no reader | Ice builds; A8b greps empty |
| R13 | **T6 re-freeze** (read-only; §4) | evidence only; the ax-discovery ledger | the negative control | A5 PASS or VOID ×3 reported |
| R14 | **verify stage with step 6** (sacrificial helpers; §5) | evidence only; ledger | pre-registered expectations | as §5 |

## 3. Rulings on the rest (from the recon; §7 Jev for the open ones)

Dropped after Codex round 1: D04 (a `live` factory has no testable seam; three concise call sites stay), D13 (the two `Fakes.swift` serve different modules through `@testable`), D29 (one running-apps snapshot changes the race between the process list and the agent pid; an optimization, not a cleanup).

Skipped, with the reason: D11 (placeholder keys: the triplication is already
gone), D12 (`mbdiscover`'s Census types: CLI-only), D16, D22, D24, D27 (style
only, no cost), D17 (subsumed by R3 for `iceIconKey`; `discoveredSectionMap`'s
`@Published` stays -- the pane may observe it later), D18 (a guard that is dead
on 27 today but protective if AX moves ever come), D19 (one extra O(n) pass in
a small, load-bearing function), D21 (`.notInSection` unused, a public case --
removal is API churn), D25 (old `TagCollision.split` overload, test-only),
D33–D37 (blocked by A8 / A10 / the frozen package / D5).

Open (a behaviour or an untested Ice-layer change; proposed **defer**, put to
Jev in §7): D01 (reorder divider tracking before the first cache pass and drop
the fallback), D02 (one `$state` subscription for the verifier and the cache),
D15 (drop `Job.id` / `nextJobID` in `HidingVerifier`), D30 (publish the cache
only on membership / order / title changes), D31 (skip the image cache's no-op
passes on 27), D32 (do not await the first discovery pass in setup), N3b (the
verify-time re-filter).

## 4. T6 re-freeze (R13)

`MBD = /private/tmp/claude-501/mbdiscovery-rel/out/Products/Release/mbdiscover`
(rebuilt from HEAD in step 1; every command below runs `$MBD` by this path).
Read-only toward the bar; `mbdiscover` writes only to stdout (READ,
`mbdiscover/main.swift:1-5`, A8b's grep covers its directory). The labels are
hand-written from the census into the evidence directory; nothing enters the
repo except a ledger line.

1. Rebuild `mbdiscover` release from HEAD into `/private/tmp/claude-501/mbdiscovery-rel`.
2. `E = ~/IceReverse-evidence/<ts>-t6/attempt1`. `$MBD > E/census-before.txt`.
3. Write `E/labels.json` (`[DiscoveryLabel]`: owner, childIndex, position,
   basis, planIndex) from that census -- by a script that transcribes, then
   read back by eye for planIndex (ascending x among on-bar items).
4. `$MBD --check E/labels.json --hash | tee E/check.txt` → `labels-hash`
   line into `E/labels.sha256`; PASS needs `agree: N labels`, exit 0.
5. Negative control: `labels-wrong.json` with one field contradicted →
   `--check` must exit 1 with a mismatch line; if it agrees, T6 FAILS (the
   comparator), no retry.
6. `$MBD > E/census-after.txt`; any change from census-before → VOID,
   repeat from 2 in `attempt2` (≤ 3 attempts), never a code change.
7. `$MBD --plan --collapsed > E/plan.txt`; `$MBD --time 5 > E/time.txt`
   (a warm pass > 50 ms is a Deviation, not a failure).

Outputs name installed apps: they stay in `E`; the conversation gets counts.

## 5. Verify step 6 (R14)

`docs/macos-27/probes/visibility/build.sh` (scratch `/private/tmp/claude-501/visibility-live`),
then `vizprobe verify --apps <scratch>/apps --dry-run` (preflight and baseline
only, nothing launched), then `vizprobe verify --apps <scratch>/apps`
(watchdog 20 min). Only sacrificial helpers draw items: bundle ids
`com.icespike4.target` (the target role, reused for step 6's pair) and
`com.icespike4.protected` (the reference role); step 6's pair are one
`com.icespike4.target` process with two items whose AX identifiers are
`vz-a` and `vz-b` (READ, `StageVerify.swift:122-141`); no spacer is expanded and no event is posted
(READ, `StageRun.swift:13-14`, A8b). Step 6 needs free room ≥ 60 + 17.5 + 41 =
118.5 pt at its own launch (READ, `StageRun.swift:42-48,304-347`); MEASURED
now 154.5 pt with no helper up (the reference helper of step 2 takes part of
it). Pre-registered, from section 6 of the ax-discovery plan: (a) the second
child of the pair observed drawn at its own x, or a stated skip; (b) "gone":
both `hidden(folded: false)` (`foldUnreadable` recorded, not a stop); "stayed":
both `stillDrawn`. Every other step as in the two 09-23 runs. Aborts: `«` or a
pill left of the items, a user item not found at its preflight x twice. If
the room gate skips step 6 again, the user is asked to free room (by role, not
by name) and the stage is re-run once.

## 6. Acceptance

| # | check |
|---|---|
| X1 | IceCore green (≥ 329 + new), ≥ 80 % lines; MenuBarDiscovery 19 + Feed 31 (+ new) green, ≥ 80 % excluding the live adapters and the CLI; MenuBarCapture 30; SafeWidthCore 277; IceWatchCore 44 |
| X2 | Ice builds (`CODE_SIGNING_ALLOWED=NO`, registered derived data); `build.sh` builds the probes |
| X3 | A3, A4 (`git diff --exit-code af4baf1 -- Packages/MenuBarCapture <detector files>`), A8 (`check-a8.sh`, table unchanged), A8b (greps empty), A10 (`check-a10.sh`) |
| X4 | IceCore imports only the standard library (the 2026-09-19 grep) |
| X5 | T6 PASS (or VOID three times, reported) |
| X6 | verify: expectations of §5 met, or a pre-registered skip stated |
| X7 | `/simcodex` ends without P0/P1; the full test run green; the evidence package given; commit / merge / push wait for the user |

## 7. Decisions (Jev)

Asked as in the first run (per-requirement nouls, options neutral): for each
of D01, D02, D15, D30, D31, D32, N3b -- "do now" vs "defer" -- against R-a the
code keeps the behaviour the first run measured, R-b no scope beyond the
deferred list, R-c every change verifiable by an existing test or a new unit
test, R-d lower maintenance cost. Results in Appendix B.

## 8. Risks and rollback

| risk | response |
|---|---|
| a refactor changes the check's behaviour (R5, R10) | unit tests first; R14 runs the check live on helpers afterwards |
| an Ice-layer edit breaks something only a run would show (R3, R12) | R12 is behaviour-preserving for every reader; **R3 is a deliberate D14 correction** (candidates bounded by the fresh set's icon when no key was cached): its acceptance evidence is the characterization and two regression tests plus the ledger entry, not the build; build + A8/A8b/A10 for both; a re-run of Ice offered to the user, not done |
| T6 drifts three times | reported; no code change |
| step 6 skipped for room again | user frees room, one re-run |
| a live stage aborts | its teardown quits the helpers and empties their domains (READ, `StageRun.swift:98-157,232-285`); the user's items are checked against preflight |
| rollback | checkpoint commits on the local `wip/first-run` only (the user's standing rule: wip/ checkpoints allowed, never pushed or merged; formal commit, merge and push wait for the user); `git revert` per checkpoint |

## Appendix A — review record

### Round 1 (Codex on v1; 1 P0, 7 P1, 4 P2)

| finding | ruling |
|---|---|
| P0 checkpoint commits break "no commit" | **reject**: the user's standing rule allows local checkpoint commits on `wip/` branches (never pushed or merged) and the session's start command asks for them; "no commit" in the review prompt meant formal commits. §8 reworded. Fed back |
| P1 A3/A4 placeholder | **adopt** → the ten files and the command listed in §2 |
| P1 R3 changes behaviour when no key is cached | **modify** → kept, stated as a deliberate semantic change (the old code broke D14 exactly in that window; the window is real, `MenuBarItemManager.swift:555-558`), with a characterization test and regression tests for both cases. Fed back |
| P1 R1 drops parked items from skip rosters | **adopt** → `sectionMembers` includes parked; a parked-member characterization test |
| P1 R4 `generation` is read by the probe | **adopt** → the probe's evidence field goes too, stated |
| P1 R10 one running-apps snapshot changes race semantics | **adopt** → D29 dropped; R10 keeps only D07 |
| P1 R12 equality by message changes publication | **modify** → no custom `==`: the unread stored `summary` is dropped, so equality is over what the only reader shows (`Text(status.message)`); a republish of identical text changes nothing any reader can see. Fed back |
| P1 R13 bare `mbdiscover` | **adopt** → `$MBD` absolute path |
| P2 compile-red is not behavioural red | **adopt** → characterization tests first, stated in §2 |
| P2 R7 not test-first; wrong seam | **adopt** → characterization test on the prepare path with a blocking, cancellation-aware fake |
| P2 R11 merging `Fakes.swift` across modules | **adopt** → D13 dropped |
| P2 R9 `live` factory untestable | **adopt** → D04 dropped |
| P2 R14 identifiers | **adopt** → bundle ids and AX identifiers named separately |

### Round 2 (Codex on v2)

| finding | ruling |
|---|---|
| P0 checkpoint commits, R3, R12 | **withdrawn** by Codex (the wip/ rule; the D14 correction scoped and tested; `summary` has no reader) |
| new P1: §8 still called R3 behaviour-preserving | **adopt** → §8 and §1 reworded; R3's evidence is its tests and the ledger |

## Appendix B — Jev

`jev-1.13.0`; request and response in `~/IceReverse-evidence/20260925-residuals/jev/`
(no installed-app names). Requirements: Ra keeps the behaviour the first run
measured; Rb no scope beyond the deferred list; Rc verifiable by a test (the
app layer has no test target); Rd lowers maintenance cost. Choice do-now vs
defer, and one noul per option × requirement.

| item | Jev | p(defer) | do-now nouls ≥ 0.5 |
|---|---|---|---|
| D01 reorder divider tracking | defer | 0.58 (near even) | Rc 0.57 |
| D02 one `$state` subscription | defer | 0.87 | Rc 0.52 |
| D15 drop `Job.id` | defer | 0.86 | -- |
| D30 publish on membership only | defer | 0.97 | Rc 0.60 |
| D31 skip no-op image passes | defer | 0.90 | Ra 0.60, Rb 0.52, Rc 0.53 |
| D32 do not await the first pass | defer | 1.00 | Ra 0.93, Rb 0.82, Rc 0.63 |
| N3b drop the verify-time re-filter | defer | 0.98 | Ra 0.52, Rc 0.62 |

All seven deferred, as proposed; D01's near-even split is stated, not a veto.

## Deviations (ledger)

Format: trigger → what changed → reason.

1. R2 (2026-09-25): `DiscoveredCachePlan.swift:154` builds
   `items.filter { $0.position != .parked } + icon`, which differs from
   `listedItems.filter { … }` when Ice's icon is itself parked → `listedItems`
   is used at the two sites that are exactly `items + icon` (`CheckPlan`,
   `DiscoveryLabel.indexed`); that one stays → a single definition must not
   change a result.
2. R3, R4, R10 reached the probes (not listed in §2): `vizprobe`'s
   `StageDiscover` / `StageVerify` passed `iceIconKey: nil` (removed -- their
   sets carry no Ice icon, so their plans are unchanged); `StageShared`'s
   evidence drops `generation` (as R4 states); `icewatch`'s `BarReader` holds
   the origin as `DiscoveryOrigin` → the probe package must build (X2).
3. The A8 / A10 scripts are zsh (`${0:A:h}`): a first run under bash exited 1
   on an unbound variable, which is not a check result → run with `zsh`; both
   pass (A8 71 hits, A10 three files as expected).
4. R3 is the stated D14 correction: with no key cached, candidates are now
   bounded by the set's own icon (`CheckPlanMembersTests`: "the set's own icon
   bounds the candidates, whatever the last cache pass saw").
5. TDD record: IceCore's new tests were red first (missing
   `sectionMembers` / `listedItems`, old signature); the three Feed
   characterization tests were run green on the old code (IceCore sources
   stashed for the run, then restored) before the refactor, and stay green
   after it. Counts: IceCore 329 → 334, MenuBarDiscovery 19, Feed 31 → 34,
   IceWatchCore 44.
6. `/simcodex` round 1 (four lenses, Opus; Codex on `f1de8c9`): no P0 or P1
   anywhere, Codex found nothing. P2s that were the plan's own tasks left
   unfinished or its evidence overstated were fixed in the round: R2's two
   missed sites (`runPrepareBody`'s `itemsByKey`, `RoomGuard.hasRoom`), R11's
   four hand-built fixtures, `retrying`'s redundant `cancelled` result, a
   shadowed `prepared`, the eager roster (a local func again), the roster
   doc comments, icewatch's copy of the 0.25 s timeout. Deferred to the
   report: test-file placement and naming, the live factory's repeated
   readers, three producers of a screen's origin, moving the status line
   into IceCore, `CheckPlan.make`'s one allocation, pass-through forwards.
7. R3's evidence (corrects 4 and 5): the IceCore "regression" tests only
   failed by the old signature -- exactly what §2 says is no evidence -- and
   duplicated existing tests → removed; R3 is now pinned where it acts,
   `HidingVerificationIconBoundTests` (a candidate right of Ice's icon, no
   key supplied → `.skip(.noReference)`, no capture). Run on the
   pre-refactor code (`git archive 4296f34` into `/private/tmp`, the test's
   calls given `iceIconKey: nil`): **red** for a behavioural reason (the
   candidate was accepted and a capture ran); green now. On the same old
   code the new characterization tests were green: R7 with a
   cancellation-aware fake (the live discoverer's nil path) and without, and
   a cancel at a warm-up capture on each side (R5's moved branches).
8. iCloud made `ItemCatalog 2.swift` and `CheckPlan 2.swift` after the files
   were rewritten; IceCore stopped building ("'DiscoveredItemSet' is
   ambiguous") → both untracked, their blobs in git history (project memory's
   rule) → deleted; every build and test green again. Counts: IceCore 332
   (two duplicates removed), MenuBarDiscovery 19, Feed 36, IceWatchCore 44.
9. Round 2 reviewed round 1's ten-file fix set with one reviewer covering all
   four lenses plus a line-by-line behaviour check against `f1de8c9`, and
   Codex on the uncommitted diff -- proportionate to the diff's size.
10. Round 2: Codex nothing; the reviewer confirmed every changed line keeps
   its outcomes (against `f1de8c9`) and found P2s only, of which the ones in
   code written that round were fixed: the roster doc comments now name all
   three shapes (empty without a set; every member without geometry or on a
   whole-section plan skip; plan targets plus per-item skips otherwise); the
   warm-up cancellation test arms its checkpoint after prepare (it could
   have hung) and pins the sleeps, so losing the warm-up loop's flag check
   fails it (checked by mutation in a `/private/tmp` copy: both cases red);
   a `RoomGuard` test for a parked or frameless icon; the members suite's
   unused divider. Round 3: Codex on everything uncommitted -- nothing.
   Counts: IceCore 333, MenuBarDiscovery 19, Feed 36, IceWatchCore 44; Ice
   and the probes build; A3, A4, A8 (71), A8b, A10 pass; no iCloud copies.
11. R13, T6 re-freeze (evidence `~/IceReverse-evidence/20260925-103322-t6`):
   attempt1 on `f1de8c9` and attempt2 on `b316328`. Both: all 11 labels agree
   on presence, position, basis and plan order; the negative control is
   detected; no drift. **Not PASS**: every pass is incomplete because of
   the bar, not the code -- attempt1, two processes (one accessory process
   that never finished launching and held every AX read for the full 0.25 s,
   which also made warm passes ~290 ms; one third-party accessory app whose
   item answers `AXIdentifier` with `kAXErrorFailure`); attempt2, only the
   latter app (relaunched), warm passes 23-45 ms. Neither VOID (no drift)
   nor a comparator FAIL (the control works). Re-running needs that app
   quit for a minute.
12. R14, verify (evidence `20260925-103606-vzverify` on `f1de8c9`,
   `20260925-110859-vzverify` on `b316328`): steps 3 and 5 as on 09-23
   (`hidden(folded: false)`, baseline reused, `stillDrawn`), user items
   displaced 0, helper domains empty, MenuBarAgent defaults unchanged. Step
   6 skipped for room both times: 113.5 pt free at its launch, 118.5 needed
   (the reference helper up; a 16 pt privacy pill in the middle of the
   user's items since 09:26 moves everything left of it 44 pt). Re-running
   needs ≥ 5 pt more room.
