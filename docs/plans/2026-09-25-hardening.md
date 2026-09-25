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
