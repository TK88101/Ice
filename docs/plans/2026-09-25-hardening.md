# Hardening after the responsiveness quarantine

2026-09-25 · branch `wip/hardening` (from `main` b2dc61d) · the seven items the
quarantine's reviews deferred (security review LOW-1/-2/-4/-5/-8, altitude P2 x2)
plus the macOS 27 status statement Codex found missing. The owner asked for this
wrap-up before the hiding feasibility study.

## 1. Goal and non-goals

Close or explicitly accept each deferred item, one at a time (Codex: do not batch
them into one change), and state plainly what Ice does and does not do on 27.
**Not**: any hiding work (next plan); re-opening the quarantine's settled rules;
`Packages/MenuBarCapture` or the ten frozen IceCore detector files; running Ice.

## 2. Items

| # | item | disposition | change | test first |
|---|---|---|---|---|
| H1 | `DiscoveredFrameReader` has no sample-level deadline, **and** (found in review) reports a keyed pid whose read is `.failed` as its keys being absent -- which the frozen contract (`MenuBarAXReading.swift:19-25`) defines as a *successful* read that found nothing, i.e. a fabricated disappearance | **fix (v2)** | a keyed pid whose read classifies `.failed`, or that the sample deadline cuts or leaves unread, makes the whole snapshot `nil` -- the contract's "nothing here can be trusted", so the sampler takes no sample; `.none` (no extras bar, process gone) stays an honest absence. Inject `now` and `deadline` (defaults `systemUptime`, 2.0 s); pids are read in a sorted, deterministic order; the agent read keeps `{ false }` | f1 a keyed pid's `.failed` read -> `nil` (characterizes today's absent first, then flips); f2 a `.none` read still leaves the key absent; f3 a slow first pid past the deadline -> `nil`, the second pid never read; f4 the interrupt trips at the deadline; f5 pid order is sorted |
| H2 | the child cap is checked after the whole `AXChildren` array crossed the process boundary | **fix** | fetch through a seam, `fetchChildren(bar, maxValues:)`, whose live form calls `AXUIElementCopyAttributeValues(bar, AXChildren, 0, cap + 1, ...)`; `cap + 1` elements means over the cap; the count still comes from the array the walk is handed (G3); errors map through `AXErrorNames` as before | w8 the seam is asked for `(0, 65)`; w9 its array reaches `walkChildren` untouched (indices, count); w10 an error maps exactly as `AXUIElementCopyAttributeValue`'s did; live census before/after as supplementary evidence |
| H3 | `agentPID()` matches a bundle id only; a process claiming `com.apple.MenuBarAgent` first in the list would take over the agent's routing and exemption | **fix** | also require the bundle URL, standardized, to have `/System` as its first path component; a pure helper decides | a1 right id under `/System/Library/...` -> agent; a2 right id elsewhere -> not; a3 `/SystemX/...` -> not; a4 nil URL -> not; a5 an unstandardized path with `..` resolving outside `/System` -> not; live: `systemElements > 0` |
| H4 | `MenuBarDiscoverer`'s `queue` is injectable; a concurrent queue would let two passes read and write the quarantine state at once | **fix** | remove the parameter; the discoverer owns its serial queue. No caller passes one (checked) | c1 two concurrent `discover` calls never overlap inside the reader (a fake records enter/exit) |
| H5 | the age gate compares the wall clock with the kernel start time; a forward clock step makes a young process look old | **fix (v2, was accept)** | MEASURED: `proc_pid_rusage` `ri_proc_start_abstime` is available for 73 of 73 processes, stable, nil for a dead pid; on the same (sleep-excluding) mach clock the age is at most the wall-clock age -- always the safe direction. `ProcessInfoRecord.startUptime` (default nil); `QuarantineContext` carries the mach-clock now instead of the wall clock; no `startUptime` -> not quarantinable. `startTime` stays the identity | k1 a young process by the monotonic clock is not quarantined whatever the wall clock says (forward step); k2 a backward step changes nothing; k3 no `startUptime` -> never entered; k4 60 s boundary |
| H6 | "what happened to pid X this pass" is derived twice (vizprobe's `readConclusively`, `mbdiscover --watch-pid`) | **fix (v2)** | `DiscoveryResult.status(of: pid)` -> a struct: `enumerated`, `listed`, `failed`, `quarantined`, `permissionDenied` -- not an enum, because an entering pid is failed *and* quarantined | s1 failed+quarantined; s2 read clean, no item; s3 listed; s4 permission denied; s5 pid not enumerated |
| H7 | `ResponsivenessQuarantine` matches the literal `"extrasBar"` that `ReadClassifier` emits | **fix** | `ReadClassifier.extrasBarCall` / `childrenCall` used by the classifier and the quarantine | t1 a quarantine test builds its stall through the shared constant |
| H8 | nothing tells a user what Ice does on 27 | **write** | `docs/macos-27/STATUS.md`, each claim tagged MEASURED (with the build and date) or INFERRED, never a general guarantee; one README line pointing to it | the link resolves (a grep in the acceptance) |

## 3. Acceptance

All six suites green; coverage no lower than now (IceCore 97.53 %, Discovery+Feed
97.70 %); Ice builds; `build.sh` builds; A3/A4, A8, A8b, A10, X4; H2's census
equality and H3's live check; the 24 quarantine mutation probes still killed; one
new mutation probe per fixed item (H1 no deadline, H2 fetch unbounded is live-only
so none, H3 bundle id only, H6 a field swapped).

## 4. Risks

H2 is the only live-only change: if `AXUIElementCopyAttributeValues` answers
differently from `AXUIElementCopyAttributeValue` for some process (an error, or a
different count), the seam tests and the census comparison show it before anything
is merged, and H2 is dropped rather than bent. H1-v2 returns a whole-snapshot `nil`
(no detector sample) where today it returns fabricated absences: a slow or failing
keyed process now starves the check of samples instead of faking a disappearance --
the fail-safe direction (Codex round 2). H5's sleep-excluding clock only delays a
quarantine, also fail-safe.

## Appendix -- review record

### Round 1 -- Codex
H1 P1 **adopted, widened**: the deadline must not leave absent keys -- and neither may a `.failed` read, which already did (an untested contract violation). H2 P2 adopted (seam test). H3 P2 adopted (path components, edge cases). H4 P3 adopted (concurrency test). H5 P1 **adopted**: accept -> fix, with the measured monotonic source. H6 P1 adopted: a struct, not an enum. H7 P3 adopted (direct test). H8 P2 adopted (measured vs inferred, link check).

### Round 2 -- Codex
CONVERGED apart from the stale risk text above (fixed): H1-v2's sample starvation and H5's sleep exclusion are both fail-safe.

## Deviations (ledger)

| # | from | to | why |
|---|---|---|---|
| HD-1 | H2: bounded fetch through `AXUIElementCopyAttributeValues` | **dropped** (reverted) | section 4's own rule: MEASURED 2026-09-25, read-only, 71 of 71 empty array attributes across the running apps answer `kAXErrorIllegalArgument` to `CopyAttributeValues(index 0)` where `CopyAttributeValue` answers success with `[]` (`AXUIElement.h` documents an out-of-range index as illegal). A process with an extras bar and no children would have failed every pass. The before/after census had agreed (73 of 73) only because no such process was up. The cap still refuses an oversized snapshot, after the copy |
| HD-2 | H3: bundle id + `/System` first path component | + the running process satisfies `anchor apple and identifier "com.apple.MenuBarAgent"` (by pid, only for a candidate that passed the cheap checks; about 0.8 ms) | security review MEDIUM: `/System/Volumes/Data/...` passes the path check and is user-writable. The path check stays as specified |
| HD-3 | H1: a keyed pid cut or left unread by the deadline -> `nil` | also a keyed read that **finishes** past the deadline -> `nil` | Codex review P1 (round 1): the last keyed read had no later iteration to check the clock. The deadline bounds the whole sample, as the init's doc says |

## Execution record

### simcodex round 1

- **Codex** (`codex review --base main`): one P1, adopted (HD-3; test f6).
- **Security review**: MEDIUM H3 spoof -> adopted (HD-2; g1-g5). LOW agent read not bounded by the sample deadline -> **rejected, owner's ruling** ("the agent read keeps `{ false }`"), and it presupposes the spoof HD-2 closes. LOW one keyed process can starve every sample -> accepted as a residual: fail-safe, as section 4 states. LOW H2 empty children -> confirmed by measurement (HD-1). Note: `LiveMenuBarAXReader` (frozen) still matches the agent by bundle id alone; only vizprobe and `MBCaptureSanity` use it -- a residual until the freeze lifts.
- **Simplify** (reuse, simplification, efficiency, altitude): one owned-item fixture for the discovery tests; `FakeExtrasReader` also records the interrupt after its handler, so f4/f4b use `makeReader` and the extra fake goes; `PIDStatus` uses its synthesized init. **Skipped**: altitude P1 "reuse the discoverer's `now` for the age gate" -- the gate must compare `startUptime` with the clock it was read on; `now` is caller-supplied with only a monotonic contract (tests start it at 0), while `startUptime` and `uptimeNow()` share one timebase conversion in `LiveRunningApps`. Efficiency P2 (a second syscall per process, about 1-2 ms a pass) noted, not changed.
- Added from my own check: s8 (the discoverer fills `enumeratedPIDs`), f3b (an agent read past the deadline leaves keyed pids unread).

### simcodex round 2

- **Codex**: no finding ("No discrete, actionable regression").
- **Simplify** (on the round-1 delta): no P1. Deferred P2: (a) `LiveExtrasReader.read` times the extras-bar and the children reads with two near-identical blocks (restored as they were by the H2 revert); (b) `agentPID()` re-checks the agent's signature on every call -- once per sample during a check, about 0.8 ms each; a cache keyed by `(pid, startUptime)` would need shared, locked state for a few ms a second.
- Coverage: IceCore 97.53 % (unchanged); Discovery+Feed 97.89 % against 97.70 %, after two tests for lines the change had left uncovered (the reader's default clock; a keyed pid no longer enumerated).

### simcodex round 3, acceptance, mutations

- **Codex round 3**: no finding. simcodex had already met its early-exit condition in round 2.
- **Items**: H1 (f1-f6, f3b, f4b), H3 (a1-a6, g1-g5; live: the plain listing finds the agent, `systemElements` 4, with and without HD-2), H4 (c1: 1 read at a time; 2 with a concurrent queue injected into the old code), H5 (k1-k4, red when the gate is put back on `startTime`; live start uptime for this process, stable, `nil` for a dead pid), H6 (s1-s8), H7 (t1), H8 (`STATUS.md`, every row tagged, the README link resolves) -- done. H2 -- dropped (HD-1).
- **Acceptance**: IceCore 378, MenuBarDiscovery 85, Feed 47, MenuBarCapture 30, SafeWidthCore 277, IceWatchCore 44 -- all green; line coverage IceCore 97.53 % (unchanged), Discovery+Feed 97.89 % (was 97.70 %, same exclusions); Ice builds; `build.sh` builds; A3/A4 byte-identical to af4baf1; A8 71 hits as expected; A8b empty; A10 as expected; X4 IceCore imports nothing.
- **Mutation probes**: 39 of 39 killed -- the quarantine plan's 24 (anchors of M8/M9 updated for H7/H5) and 15 new: N1a-N1e (H1: no pre-read check, keyed reads handed `{ false }`, a `.failed` read left absent, pids in hash order, no post-read check), N3a/N3b (H3: path not checked, path not standardized), N4 (H4: a concurrent queue), N5a-N5c (H5: gate on `startTime`, enumeration without `startUptime`, the discoverer judging age on its pass clock), N6a/N6b (H6: failed/quarantined swapped, no enumerated pids), N7 (H7: a drifted spelling), N8 (HD-2: the signature not required). None for H2 (dropped). Runner and output: evidence `20260925-195224-hardening/mutations/`, restored from in-memory copies, never from git.
- **Found on the way** (desk, read-only): the local build of Ice and its `MenuBarItemService.xpc` are ad-hoc signed with no team identifier, while the release Ice (0.11.13-dev.2) and its service carry a Developer ID team. The service's peer requirement is `.isFromSameTeam()`, so the XPC failure measured on 27 is INFERRED to be this build's signing, not macOS 27 -- the next plan takes it up.
