# Responsiveness quarantine, the walk's deadline contract, and childCount wiring

2026-09-25 · branch `wip/responsiveness-quarantine` (from `main` 954ee5e, which
is 39c604c plus the identifier-failure plan's section 9 handover) · items 1-3 of
that section 9, in that order. **v3** -- revised after three Codex rounds and a
four-lens Opus review, each finding checked by a skeptic (Appendix A), with Jev
as a second opinion on the two value calls (Appendix B).

## 1. Goal and non-goals

**Programme goal (unchanged, not re-opened here).** Ice on macOS 27 no longer
stalls at "Loading menu bar items...": Accessibility enumerates the bar's items
and their identities (replacing the `MenuBarItem.windowID` identity chain); Ice's
own dividers split them into three sections (computed only when a divider has
been collapsed >= 1 s and nothing changed during the pass; carried over while
expanded); after Ice collapses a section it calls the visual detector to check,
read-only, that the section really is not drawn, logs the result and shows it in
the layout settings. The detector is not changed and is wired to no hiding
behaviour. A hiding mechanism that works on 27 is out of scope.

**This plan.**

- **G1 -- responsiveness quarantine.** A process identity that has never
  supplied extras and holds its `AXExtrasMenuBar` read for the full timeout is
  made temporarily ineligible: later passes skip it, a bounded backoff re-probes
  it, the first answer lifts it. Known item owners are exempt and keep making a
  pass `incomplete` when they fail. What `complete` now means is written where
  `Completeness` is defined.
- **G2 -- the deadline and cancellation contract.** Cancellation and the pass
  deadline are polled between children inside a walk, not only between
  processes; a per-process child cap makes an oversized snapshot an interrupted
  read instead of a silent truncation; every pass still makes progress.
- **G3 -- childCount wiring**, with G2's edit to `LiveExtrasReader`: the helper
  takes the raw children value, derives count and elements itself and returns
  the `RawRead`, so no call site handles a count.
- **E0 -- enabler, surfaced by this plan's own measurement (M3/M4).** Section 9
  keys the quarantine on `(pid, launchTime)`, but `NSRunningApplication.launchDate`
  is nil for every WebKit content process. `ProcessInfoRecord` gains a separate
  `startTime` -- the kernel's process start time -- used by the quarantine only.
  `launchTime` and everything that reads it (`carryOver`) stay as they are.

**Not in this plan** (settled or excluded by the owner): any hiding mechanism;
re-opening D2 or persistent aliases; live Ice runs for R3/R12; both mitigations
of the empty-identifier ambiguity; the deferred D01 D02 D15 D30 D31 D32 N3b; the
withdrawn D04 D13 D29; running Ice (Ice's *sources* do not change, but its
discovery behaviour does -- the live checks exercise the same `MenuBarDiscoverer`
through `mbdiscover`; an Ice run stays the owner's call); filtering by
`activationPolicy` or bundle id (and the settled `.prohibited` skip stays);
lowering the per-call timeout; changes to `ReadClassifier`'s table,
`AttributeWalkPolicy`, `ItemCatalog`, `carryOver`, `DiscoveredCachePlan`, the
detector or `Packages/MenuBarCapture`.

## 2. Measured before designing

Evidence directory `~/IceReverse-evidence/20260925-170012-quarantine-calib/`
(census output names installed apps; only aggregates appear here).

| # | fact | source |
|---|---|---|
| M1 | WebKit content processes can hold every `AXExtrasMenuBar` read for the full 0.25 s; four up (uptimes 9-55 min) made warm passes ~1 s instead of 16-30 ms and every pass `incomplete`; all report `.accessory` | FINDINGS, MEASURED 14:20 today |
| M2 | 12 census runs, 5 s apart, 17:0x today: 70 processes each, **0 timeouts**; the 8 WebKit processes answered **fast** (6 `cannotComplete` < 50 ms = `declinesAccessibility`, 2 `noValue`). The pathology depends on the process's state (suspended or not) | census x12 |
| M3 | `launchDate` is nil for **55 of 70** processes -- **all 8 WebKit** processes and 5 of the 13 identities that own extras | census |
| M4 | the kernel's start time (`sysctl` `KERN_PROC_PID`, `kp_proc.p_starttime`) is available for **70 of 70**, identical across two reads, nil for a dead pid | scratch probe `starttime.swift` |
| M5 | fast extras answers: p50 13 ms, p99 28 ms, max 32 ms; the classifier's stall line is 0.2 s (0.8 x 0.25 s) | census |
| M6 | largest children snapshot of any process: 6 | census |
| M7 | who reads `completeness`: `carryOver` (failed pids), `DiscoveryLabels.compare` (T6), `mbdiscover` output, `DiscoveredCachePlan` (`permissionDenied` only), and **vizprobe's `readConclusively`** (`StageRun.swift:416-421`, which takes `.complete` to mean every pid was read). Ice's own code reads none; `HidingVerification` ignores it and passes `previous: nil`. Ice's cache pass: a 5 s timer and `runningApplications` changes (0.25 s delay + 1 s debounce), one static discoverer; `HidingVerification`'s discoverer is cached per display | code, `MenuBarItemManager.swift:81-84`, `AppState+HidingCheck.swift:43-55` |
| M8 | within one pass, a stalled process contributes no fresh items whether or not it is quarantined; what the quarantine changes is (i) completeness, (ii) carry-over (failed pids only), (iii) whether *later* passes read it and (iv) time. So a false quarantine costs a **delay**: a recovered process's items appear at its next due re-probe, i.e. after at most the backoff in force plus the time to the next pass | `ItemCatalog.swift:93-101,200-225` |

## 3. Design

### 3.1 Identity (E0)

`ProcessInfoRecord.startTime: Double?` -- the kernel start time in seconds since
1970, filled by `LiveRunningApps` with `sysctl(KERN_PROC_PID)`, nil when the
lookup fails. The initialiser takes it **with a default of `nil`**, the one
deliberate exception to "no defaults": nil is the fail-safe value (no identity,
so never quarantined), a forgotten site can only switch the quarantine off, and
T5's integration test plus L1 catch that. `ProcessIdentity` = `(pid, startTime)`,
failable; **no identity, no quarantine** (section 9, rule 3). `launchTime` keeps
its `launchDate` source and meaning, so `carryOver` and the census's `launchTime`
field are untouched.

### 3.2 Entering the quarantine

A read makes its identity quarantined when **all** hold:

1. **trigger** -- its outcome is `.failed(.timedOut(call: "extrasBar"))`. A
   children timeout, a walk stop, an unexpected error: never, because the process
   has shown it has an extras bar;
2. **identity** established (3.1);
3. **age** -- the process has been running at least `minimumAge = 60 s` (the
   pass's wall clock minus `startTime`). A young process's "never supplied" says
   nothing: an app still launching stalls exactly like a suspended one, and at
   login that is every app. M1's WebKit processes were 9-55 minutes old;
4. **not exempt** -- not `isSelf`; not the menu bar agent's pid; not an identity
   that **has shown a non-empty extras snapshot** (3.3) to this discoverer; not the identity of a
   process owning an item (or the visible control item) in the caller's
   `previous` set;
5. **witnessed** -- in the same pass, reads whose extras-bar call answered in
   under `timeout x 0.2` (50 ms; M5's fast band tops out at 32 ms) **outnumber**
   reads whose extras-bar call reached the stall line; `notAttempted` reads
   count as neither. A slow AX service as a whole fails this.

**The read that enters is still counted**: it stays in the pass as the failure it
is, so the pass that first meets a stall reports `incomplete` (Codex round 1,
adopted: a first-seen owner must never vanish under a `complete`). The
quarantine takes effect from the next pass.

### 3.3 "Supplied extras", narrowly

An identity **has shown a non-empty extras snapshot** (short: *snapshot-shown*) once any of its reads had `extrasError ==
"success"` and a children snapshot of at least one child (`childCount >= 1`),
however that read then classified. Not `noValue` or `attributeUnsupported`, not a
fast decline, not an empty children list, not anything that failed before the
children arrived -- so a WebKit process answering `noValue` quickly (M2) cannot
escape the quarantine the next time it is suspended. Remembered for the
identity's lifetime in this discoverer, and exempt from then on: a process that
has shown children *is* known to own items even if its walk then failed (Opus
review L1-3, adopted).

### 3.4 Lifecycle

- **Skipped**: a quarantined, non-exempt identity is not read in the pass's
  ordinary rotation; it is listed in `DiscoveryResult.quarantined` and is not
  failed.
- **Re-probed at the end of the pass.** After the rotation finishes without
  truncation, due identities (`now >= nextProbeAt`, oldest due first, then pid)
  are re-read one by one while the pass is not cancelled and `now + timeout <=
  deadline`. That is an **admission** condition only -- one extras-bar timeout
  still fits -- so re-probes never take budget from an eligible process; once a
  re-probe answers, its walk obeys the same interrupt as any read, and one AX
  call in flight may cross the deadline, as for any read. One that is not
  admitted stays due, not failed.
- **Outcome of a re-probe**: extras-bar timeout -> stays; backoff doubles
  (2, 4, 8, 16, 30, 30 s); the read is left out of the pass. **Any other outcome
  lifts it** (ledger D-1) and the read is settled like any other: a failure
  counts, children make it snapshot-shown.
- **Backoff** starts at 2 s from the settlement of the read that entered or
  re-probed, doubling to a cap of 30 s. A lifted identity that stalls again
  re-enters through 3.2 afresh. The cap is a choice, not a derivation: it bounds
  a recovered process's delay (M8) at roughly half a minute plus one pass, and
  costs one <= 0.25 s read per quarantined identity per 30 s.
- **Pruned** at settlement: entries and snapshot-shown identities whose identity is no
  longer enumerated.
- **Exempt while quarantined** (it appeared in `previous`): the rotation's skip
  test takes the exemption inputs, so it is read normally in that very pass and
  its entry is dropped at settlement.
- **Cancellation** is checked after the rotation and after the re-probes; a
  cancelled pass returns nil and changes neither the quarantine nor the cursor.

### 3.5 Where it lives

- **IceCore** `ResponsivenessQuarantine.swift`, standard library only, immutable
  values: `ProcessIdentity`; the constants; `QuarantineContext` (agent pid,
  previous owners' identities, wall-clock now); `isSkipped(_:context:)`;
  `dueReprobes(among:now:)`; and one pure
  `settle(processes:reads:reprobes:context:now:timeout:) -> Settlement`. `reads`
  are the rotation's reads (the synthetic tail included), `reprobes` the
  re-probe reads -- two typed inputs, so settlement never has to infer which read
  was which (Codex round 1, adopted in this form). `Settlement` carries the next
  state, the reads `ItemCatalog.build` sees, and the quarantined processes.
- **MenuBarDiscoverer** keeps the state in a `DiscoveryBox` beside the cursor
  and gains an injected `wallClock` (default `Date().timeIntervalSince1970`).
- **`DiscoveryResult.quarantined: [ProcessInfoRecord]`**, sorted by pid, required,
  no default (so a site that rebuilds a result -- vizprobe's `StageShared` -- must
  forward it).

### 3.6 The meaning of `complete`

Written at `Completeness` (IceCore): `.complete` means every process that was
**eligible** in this pass was read conclusively. A process under the discoverer's
responsiveness quarantine is not eligible: it entered only after one of its
reads failed in an earlier pass (which that pass reported), it has never shown
extras, it is at least a minute old, it is revalidated on a bounded backoff, and
it is listed in `DiscoveryResult.quarantined`. Snapshot-shown identities and the caller's `previous` owners are never
quarantined, so their failures always make a pass `incomplete`.

Consequence, stated rather than hidden: `mbdiscover --check` is one cold pass,
and a stall it meets for the first time makes it `incomplete`. T6's `--check`
therefore runs **one warm-up pass on the same discoverer and checks the
second**, both with `previous: nil` (so nothing is carried into the check). It
prints the warm-up's completeness and quarantined pids and **the checked pass's
quarantined count and pids**; `--strict` makes any quarantined pid in the checked
pass a failure (the old cold-complete meaning); T6's protocol records the
checked pass's quarantined count next to its verdict (ledger D-3).

What this can and cannot hide: `DiscoveryLabels.compare` reports both a label
without an item and an item without a label (`DiscoveryLabel.swift:103-114`), so a
quarantined process that owns a **labelled** item still fails the check. The
gap is an **unlabelled** item of a process that is at least a minute old, has
never shown a non-empty extras snapshot to this fresh discoverer, and stalls on
its extras bar in both passes while fast answers dominate -- visible as a
non-zero quarantined count, and closed by `--strict`.

### 3.7 The deadline and cancellation contract (G2)

- `ExtrasReading.read(_:timeout:interrupt:)`, a non-escaping `() -> Bool`, no
  defaulted overload. `MenuBarDiscoverer` passes `{ cancelled || now() >=
  deadline }` to **every** read, the first of a pass included. `DiscoveredFrameReader`,
  the census and icewatch's `BarReader` pass `{ false }`.
- `LiveExtrasReader` polls `interrupt()` before every child, the first included;
  when it trips, the read returns `walkInterrupted = true` with the records so far.
  An AX call in flight stays bounded by the per-call timeout, as today.
- **Child cap** `LiveExtrasReader.maxChildren = 64` (M6: 6 is the largest seen).
  A larger snapshot is not walked: `walkInterrupted = true`, no records,
  `childCount` = its size. The cap is in the reader, so every caller of
  `LiveExtrasReader` gets it (a > 64-child process fails there too).
- **Truncation**, by explicit offsets (not `count - reads.count`, which a skipped
  process would break). Before each read at offset > 0, a passed deadline
  truncates there, cursor on that process (today's rule). A read that comes back
  `walkInterrupted` with the deadline passed keeps its failed read and truncates
  the pass after it; the cursor goes **on** it when its offset is > 0 (so the
  next pass reads it first, with the whole budget) and **past** it when its offset
  is 0 (it already had the whole budget). The unread tail is every later offset
  whose process is not quarantined, each given the synthetic `notAttempted` read,
  exactly once.
- **Progress** (Opus review DL-1/L1-1 and Codex round 2, converged): the cursor
  never stays where the pass started, because a cut at offset 0 moves it past;
  and a process cut later gets the next pass's whole budget. **Accepted
  consequence**: a process whose walk alone needs more than the whole 2 s budget
  is never read to the end -- every pass that reaches it fails it (`incomplete`,
  honestly), and its carried items drop after 30 s. For scale: M6's largest
  snapshot, 6 children x 6 calls x M5's 13 ms p50, is about 0.5 s.
- `RawRead.walkInterrupted`'s doc gains the new causes.

### 3.8 childCount wiring (G3)

`LiveExtrasReader.walkChildren(process:extrasElapsed:childrenElapsed:childrenValue:cap:interrupt:readChild:) -> RawRead`
takes the raw `CFTypeRef?`, derives the count (`CFArrayGetCount`) and the elements
(`childElements`, unchanged), walks with the injected `readChild(index, element)`
and `interrupt`, and returns the `RawRead`; the live `read` returns it directly.
`snapshotCount` folds in; all its assertions move to the helper. Pinned by a mixed
`CFArray` `[AXUIElement, NSNumber]` plus one record -> `childCount` 2, `records` 1,
classifier `.partialWalk(2, 1)`.

## 4. Tasks (test first -> change -> DoD)

Commands (scratch outside `~/Documents`): IceCore `swift test
--enable-code-coverage --scratch-path /private/tmp/claude-501/icecore-build`;
MenuBarDiscovery `... --scratch-path /private/tmp/claude-501/mbdiscovery-build`;
Ice `xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug
CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/claude-501/ice-main-build3
build`; probes `docs/macos-27/probes/visibility/build.sh`.

| # | what | tests first (red before green) | DoD |
|---|---|---|---|
| T1 | IceCore `ProcessInfoRecord.startTime`; `ResponsivenessQuarantine` | **entry** q1 old, identified, witnessed, not exempt, extras-bar timeout -> admitted as failed **and** entered (due at +2 s); q2 each missing condition alone keeps it out: no identity, age 59 s, `isSelf`, agent pid, snapshot-shown, `previous` owner, witnesses not a majority, witness at 60 ms (not fast), a `notAttempted` read as the only "witness"; q3 the trigger is the extras-bar timeout only: `.timedOut(children)`, `.unexpectedError(extrasBar, ...)`, `.walkInterrupted`, `.partialWalk` never enter; **narrowness** q4 earlier `.none(.noExtrasBar)`, `.none(.declinesAccessibility)`, `.items([])` leave it quarantinable; q5 an earlier read with `extrasError == "success"`, `childCount 2` that classified `.failed(.walkInterrupted)` or `.partialWalk` exempts it; **identity** q6 matching is by `(pid, startTime)`: same pid, new start time -> not skipped, not exempt by the old identity's history; **lifecycle** q7 skipped while not due, listed, not failed; q8 re-probe timeouts: 2, 4, 8, 16, 30, 30, left out of the pass; q9 re-probe `.none` lifts, admitted, a later stall re-enters through q1; q10 re-probe `.failed(.timedOut(children))` lifts and is admitted as failed; q11 re-probe with children makes it snapshot-shown; q12 pruning; q13 exempt while quarantined -> not skipped, entry dropped; q14 `dueReprobes` order (oldest due, then pid); **conformances** q15 two `ProcessInfoRecord`s differing only in `startTime` are unequal (synthesized `Equatable`/`Hashable` keep it), and `carryOver`'s identity decision (bundle id + `launchTime`) ignores it | IceCore green; the new file 100 % lines; stdlib only |
| T2 | IceCore docs: `Completeness` (3.6's text), `RawRead.walkInterrupted` (deadline, cancellation, cap), `ProcessInfoRecord.startTime` | -- | in the diff |
| T3 | `ExtrasReading` gains `interrupt`; `LiveExtrasReader.walkChildren` + cap; every conformer and caller: `DiscoveredFrameReader`, census, icewatch `BarReader.swift:60,93`, both fakes | w1 mixed `CFArray` + one record -> 2 / 1 / not interrupted, `.partialWalk(2, 1)`; w2 interrupt after child 0 of 3 -> 1 record, interrupted, count 3; w3 interrupt before child 0 -> 0, interrupted; w4 3 elements, cap 2 -> interrupted, `readChild` never called, count 3; w5 exactly at cap -> not interrupted; w6 a policy stop still interrupts; w7 nil / non-array / empty -> 0 / 0 (every old `snapshotCount` assertion) | Discovery + Feed green |
| T4 | `MenuBarDiscoverer`: skip, end-of-pass re-probes, `interrupt`, the cursor rule for cut reads, offset truncation, post-loop cancellation, `DiscoveryResult.quarantined`; vizprobe `StageShared` forwards it and `readConclusively` treats a quarantined pid as not read | d1 browser: an owner + three old stalling never snapshot-shown + fast others -> pass 1 `incomplete` (the three failed) and three quarantined; pass 2 at +1 s: the three not read, `complete`, listed; d2 pass 3 at +2.5 s: due re-probes run after the rotation, stall again, left out, pass `complete`; d3 re-probes that do not fit the remaining budget are not started, stay due, not failed; d4 a snapshot-shown identity stalls -> `incomplete`, item carried, never quarantined; d5 no `startTime` -> `incomplete` every pass; d6 every read stalls -> nothing enters; d7 the interrupt the reader receives turns true past the deadline for every read, the first of the pass included, and once cancelled -- for ordinary reads **and** re-probes; d8 progress: a first read whose walk outlasts the deadline is cut, the cursor moves past it, and over three passes every other process is read at least once; d9 a read at offset > 0 interrupted past the deadline keeps its failure, `nextCursor` is its index, and every non-quarantined pid appears in the reads exactly once; d10 a skipped process before the truncation point: each pid at most once, no double synthetic read; d11 cancellation during the last read / during a re-probe -> nil, cursor and quarantine unchanged; d12 a `previous` owner that is quarantined is read that pass; d13 a policy stop before the deadline does not truncate the pass; existing suite unchanged | green; Discovery+Feed >= 80 % excluding live adapters and CLI |
| T5 | `LiveRunningApps` fills `startTime` (E0) | integration: `kernelStartTime(getpid())` non-nil and equal across two calls; a pid that does not exist -> nil; `LiveRunningApps().processes()` has a non-nil `startTime` for at least one process | green |
| T6 | `mbdiscover`: `{ false }` in the census; plain listing prints the quarantined count; `--check` = warm-up + checked pass, printing both passes' quarantined count and pids, with `--strict` failing on any in the checked pass (3.6); `--time N [--every S] [--watch-pid P]` -- `S` start-to-start, and per pass the watched pid's `item` / `failed` / `quarantined` as yes/no | -- (CLI, excluded from coverage) | builds; `--time 3` runs read-only |
| T7 | `vzhelper` gains `stall <s>`, `s <= 30`: replies `stalling` and flushes, sleeps the main thread, replies `resumed`. Its three deadmen (controller exit, lifetime, stdin EOF) all run on the main queue, so they are late by up to `s` -- stated in the command's doc | -- | `build.sh` builds |
| T8 | live checks (section 6) | -- | L0, L1, L2 PASS, archived |
| T9 | Docs: FINDINGS (M2-M4, the live results), `RunningAppsProviding.swift:20-28`'s stale mitigation note, this plan's ledger | -- | tagged; no evidence row copied |

**Mutation probes** (each alone; the named test must fail; then reverted;
recorded): `childCount := records.count` in `walkChildren` (w1); no interrupt poll
(w2, d7); no cap (w4); cursor left on a process cut at offset 0 (d8); cursor moved past a process cut at offset > 0 (d9); tail by
`count - reads.count` (d10); keep the interrupted read *and* synthesize one (d9);
trigger on any `.failed` (q3); drop the age gate (q2); witness threshold at the
stall line (q2); witness by "any" instead of majority (q2); drop the snapshot-shown
exemption (q5, d4); drop the `previous` exemption (q2, d12); count `.none` as
shown (q4); leave the entering read out of the pass (d1); lift on a re-probe
timeout (q8); start re-probes regardless of budget (d3); no post-loop cancel
check (d11); match identities by pid only (q6).

**Parallel implementation: none.** The tasks are small and share this plan's
design intent; briefing a worker costs more than doing them (slipknot 15).

## 5. Acceptance

| # | check |
|---|---|
| X1 | IceCore, MenuBarDiscovery, MenuBarDetectorFeed, MenuBarCapture, SafeWidthCore, IceWatchCore pass; line coverage >= 80 % for IceCore and for Discovery+Feed excluding live adapters and the CLI |
| X2 | Ice builds; `build.sh` builds the probes |
| X3 | A3/A4 (`git diff --exit-code af4baf1 -- Packages/MenuBarCapture` + the detector files), A8 and A10 (zsh), A8b greps |
| X4 | IceCore imports only the standard library |
| X5 | every mutation probe fails its named test |
| X6 | L0, L1, L2 PASS |
| X7 | opportunistic, **not a gate, not a substitute**: if WebKit content processes are seen stalling during the session (read-only census every 5 min), `mbdiscover --check` and `--time 10 --every 5` on the new build are run and recorded. L1 is a synthetic stalled supplier, evidence for the state machine on a live bar, **not** for WebKit's own suspension mechanism |
| X8 | `/simcodex` ends with no P0/P1; full test run green; evidence package delivered; commit / merge / push wait for the owner |

## 6. Live checks (T8)

Sacrificial helper `Target.app` (`com.icespike4.target`) only, executed directly
so its stdin is the harness's pipe; `--controller` = the harness; `--lifetime`
300 s; never a signal; never Ice; `mbdiscover` read-only; output only to the
evidence directory; verdicts computed by the harness from `--watch-pid` lines,
which carry no names.

- **L0 -- preconditions.** `mbdiscover` plain listing shows `systemElements > 0`
  (the agent is found and read: section 9's `agentPID()` reachability check).
- **L1 -- a never snapshot-shown process that stalls enters, is skipped, recovers.**
  Launch the helper; wait 65 s (age gate); send `stall 12`, wait for `stalling`;
  run `mbdiscover --time 12 --every 2.5 --watch-pid <helper>` (fresh discoverer).
  Expected from 3.4: pass 0 `failed=yes quarantined=yes item=no`; passes while
  stalled `failed=no quarantined=yes item=no`; the helper resumes at about 11 s;
  the re-probe due at about 15.8 s runs in the pass at 17.5 s, which shows
  `quarantined=no item=yes`. PASS iff pass 0 is as stated, no pass between it and
  the lift shows `failed=yes`, and `item=yes` appears no later than pass 9
  (22.5 s: one pass of margin over the computed 17.5 s).
- **L2 -- a snapshot-shown process that stalls is never quarantined.** Launch the helper
  and wait 65 s too, so the age gate cannot be what keeps it out and the
  snapshot-shown exemption is what is tested; run `mbdiscover --time 10 --every
  2.5 --watch-pid <helper>`; after
  pass 1 prints, send `stall 8`. PASS iff every pass while it stalls shows
  `failed=yes quarantined=no item=yes` (carried), and the passes after
  `resumed` show `failed=no item=yes`.

## 7. Impact surface

- IceCore: new `ResponsivenessQuarantine.swift`; `DiscoveryInputs.swift`
  (`startTime`, docs); `DiscoveredItem.swift` (`Completeness` docs).
- MenuBarDiscovery: `ExtrasReading.swift`, `LiveExtrasReader.swift`,
  `MenuBarDiscoverer.swift`, `DiscoveryResult.swift`, `RunningAppsProviding.swift`,
  `mbdiscover/main.swift`.
- MenuBarDetectorFeed: `DiscoveredFrameReader.swift` (`{ false }`; created at
  65e8be2, after af4baf1, so not a frozen detector file).
- Probes: `vzhelper/main.swift` (`stall`), `icewatch/BarReader.swift` (`{ false }`),
  `vizprobe/StageShared.swift` (forward `quarantined`), `vizprobe/StageRun.swift`
  (`readConclusively`).
- Tests: a new IceCore suite; `LiveExtrasReaderWalkTests`; a new
  `MenuBarDiscovererQuarantineTests`; both targets' `Fakes.swift`.
- Docs: `docs/macos-27/FINDINGS.md`, this plan.
- **Not**: Ice's sources, `Packages/MenuBarCapture`, the detector files,
  `ReadClassifier`, `AttributeWalkPolicy`, `ItemCatalog`.

## 8. Risks and rollback

| risk | response |
|---|---|
| a real item's process is quarantined by mistake | it must be a minute old, never have shown a non-empty extras snapshot to this discoverer, be absent from `previous`, and stall on the extras bar while fast answers outnumber stalls; the pass that meets the stall still reports it; the cost is a delay (M8), measured by L1 |
| a fresh discoverer (Ice just launched, a new `HidingVerification` after a display change, every `mbdiscover` run) has no memory | then only `previous`, the age gate and the witness protect; the entering pass is still `incomplete` and the delay bound holds |
| system-wide slowness | the witness majority with a 50 ms fast line |
| a process known to own items vanishes silently | snapshot-shown memory and `previous`: never quarantined; d4, d12, L2, two mutation probes |
| pid reuse | identity is `(pid, startTime)`; no start time, no quarantine; q6 |
| stalls exhaust the 2 s budget | new stalls are ordinary reads (a cold pass with ~7 or more is truncated and incomplete, as today); quarantined ones are re-probed only within the budget left after the rotation (d3) |
| a slow owner can no longer finish within the deadline | a process cut at offset > 0 is the next pass's first, with the whole budget; one whose walk alone exceeds the budget is never read to the end -- accepted, 3.7 (d8, d9) |
| the deadline is overshot | by one AX call in flight plus the rest of that child's attributes, each below the stop line |
| iCloud duplicates | check for `X 2.swift` before every build |
| rollback | checkpoints on `wip/responsiveness-quarantine` only; never pushed or merged; `git revert` per checkpoint |

## 9. Decisions (after round 1)

- **A-1** E0 as a separate `startTime` field (was: replace `launchTime`) -- modified.
- **A-2** the entering read is counted; the quarantine starts next pass (was: left
  out of the observing pass) -- modified; T6's `--check` gains a warm-up pass.
- **A-3** age >= 60 s **and** a 50 ms-witness majority (was: any read under 0.2 s)
  -- modified.
- **A-4** 2 s x2 to 30 s, time-based; bound restated as backoff + one pass --
  kept, rationale rewritten.
- **A-5** trigger: extras-bar timeout only; lift: any other outcome -- kept,
  ledger D-1.
- **A-6** cap 64, not walked when exceeded -- kept.
- **A-7** replaced: no substituted read; the deadline applies to every read; a
  cut read is kept, the cursor goes on it at offset > 0 and past it at offset 0.
- **A-8** vzhelper `stall` (<= 30 s) -- kept, with the fidelity limit stated (X7).
- **A-9** re-probes at the end of the pass, only within the remaining budget -- new.
- **A-10** "has shown a non-empty extras snapshot" (extras success + >= 1 child) as the exemption -- new.

## Deviations (ledger)

| # | from | to | why |
|---|---|---|---|
| D-1 | section 9: "the first success lifts the quarantine" | any re-probe outcome other than an extras-bar timeout lifts it, and a failure then counts as a failure | a failure must never be absorbed by the quarantine; a process that answers its extras bar is not the pathology |
| D-2 | section 9: identity `(pid, launchTime)` | `(pid, startTime)`, the kernel start time | `launchDate` is nil for all 8 WebKit processes (M3); `launchTime` itself stays untouched |
| D-3 | T6's `--check`: one cold pass | a warm-up pass, then the checked pass on the same discoverer; the checked pass's quarantined count printed and recorded beside the verdict; `--strict` restores the cold-complete meaning | the entering read is counted (A-2), so a cold pass cannot be complete while a stall is first met; the check still fails on any labelled item a quarantined process owns (3.6) |
| D-4 | T6 (CLI): nothing about output buffering | `mbdiscover` sets stdout line-buffered | L2's second attempt was void: `--watch-pid` lines reached the harness's file only when the process exited, so the stall was sent after the run |
| D-5 | section 6, L2: "every pass while it stalls" | read as the failing passes after the helper was first read with its item | the valid attempt's pass 0 failed before any stall -- a cold pass that hit the deadline left the helper in the unread tail -- and the first evaluator counted it; the plan's wording never did |
| D-6 | X7: "opportunistic, not a gate" | observed: WebKit content processes stalled from ~18:07, so the A/B ran on them | recorded in FINDINGS and the evidence; still not a substitute claim for L1 or the other way round |

## Execution record

- T1-T7 done test-first, checkpointed on this branch; suites green (IceCore 371,
  MenuBarDiscovery 60, Feed 37, IceWatchCore 44 at T7).
- **X5**: 22 mutation probes -- the 18 of section 4 plus four discoverer-level
  variants (M2b, M12b, M13b, M15 through d1) -- **22 killed, 0 survived, all
  compiled**; runner and output in the evidence directory (`mutations/`).
- **X6**: L0 PASS, L1 PASS, L2 PASS on its third attempt (the first two void by
  harness and tool defects, D-4, D-5); evidence `20260925-18xxxx-quarantine-live*`.
- **X7**: observed (D-6): with 6 WebKit content processes stalling, main 954ee5e
  was `incomplete` on 6 of 6 passes at ~1.55 s warm; this change was
  `incomplete` only where a stall was first met, otherwise `complete` at 20-36 ms.

## Appendix A -- review record

### Round 1 -- Codex (gpt-5.6-terra, medium)

| finding | ruling | reason |
|---|---|---|
| P0 `DiscoveredFrameReader` is a frozen detector file | **rejected** | the frozen set is `Packages/MenuBarCapture` plus ten named IceCore files (residuals plan section 2); `DiscoveredFrameReader.swift` did not exist at af4baf1 (created at 65e8be2, +86 lines since) |
| P0 remove the `.prohibited` filter | **rejected** | "skip `.prohibited`" is a settled ruling (ax-discovery plan line 1026; identifier-failure plan line 21); "no activationPolicy filter" means no *new* one |
| P1 a first-seen owner vanishes under `complete` | **adopted** (A-2) | the entering read is counted |
| P1 one fast witness is not enough | **adopted** (A-3) | majority, 50 ms line, plus the age gate from the Opus review |
| P1 E0 changes carry-over | **adopted** (A-1) | separate `startTime` |
| P1 cancellation after the last read | **adopted** | post-loop checks, d11 |
| P1 per-slot representation | **adopted, modified** | two typed inputs (`reads`, `reprobes`) plus explicit offsets |
| P2 backoff rationale | **adopted** | restated as backoff + one pass; the cap is a choice |
| P2 re-probe interrupt tests | **adopted** | d7 covers re-probes |
| P2 E2E fidelity | **adopted** | X7 wording |

### Round 1 -- Opus, four lenses, each verified by a skeptic

Adopted: DL-1/L1-1 (progress; the cursor rule, A-7 replaced), DL-2 (explicit
offsets, d10), DL-5/L1-5/TS-4 (re-probes within budget, A-9), DL-6/L5-2 (icewatch,
vizprobe sites), L5-1/L1-8 (vizprobe `readConclusively`), L1-2 (age gate, 50 ms
witness), L1-3 (snapshot-shown exemption, A-10), L1-4/L5-6/TS-1 (L1 re-timed from
the backoff table), L5-4 (census `launchTime` untouched now), L5-11 (stall <= 30 s,
deadman delay stated), L5-12 (ledger D-1), L1-12 (L0), TS-2 (q3), TS-3/DL-3 (a cut
re-probe that answered lifts and is admitted as failed), TS-6 (q5), TS-7 (q6),
TS-8 (d13, d7), TS-9/DL-4/L5-7 (d11), TS-10 (identity-bearing fixtures), TS-11
(T5), TS-12 (`--watch-pid`), TS-13 (`stalling`/`resumed`), TS-15 (all
`snapshotCount` assertions move), DL-7/TS-16 (overshoot wording), DL-8 (the cap
applies to every caller, stated), DL-9/L1-10 (skip test takes exemption inputs;
fresh-discoverer row in section 8), L5-3 (non-goal wording), L5-8, L5-9, L5-10,
L1-9, TS-17. Refuted by its own skeptic: L1-11. Superseded: L5-5 (A-7 is replaced
rather than deleted, because the progress fix needs the cursor rule).

### Round 2 -- Codex

Both rejected P0s: **conceded** by Codex (the frozen set is MenuBarCapture plus
the ten IceCore files; the `.prohibited` skip is settled). New:

| finding | ruling | reason |
|---|---|---|
| P1 the first read, exempt from the deadline, is unbounded in time (64 children x 6 calls just under 0.2 s) | **adopted, modified** | the deadline applies to every read; progress comes from the cursor rule (past a cut at offset 0, on a cut at offset > 0); the never-finishing slow walk is an accepted consequence (3.7) |
| P1 the warm-up weakens `--check` | **maintained, then converged** (round 3) | `compare` fails on labelled items a quarantined process owns; the gap is unlabelled items only; making any quarantined pid fatal would make T6 unpassable with a suspended content process up. Converged on: print the checked pass's quarantined pids, `--strict`, T6 records the count (D-3) |
| P2 `now + timeout` is not a whole-read bound | **adopted** | reworded as an admission condition (3.4) |
| P2 `startTime` changes synthesized equality | **adopted** | kept in the conformances; q15 characterizes it |
| P3 "known owner" overstates the evidence | **adopted** | "has shown a non-empty extras snapshot" throughout |

### Round 3 -- Codex

Every ruling above accepted; the items it left "open" were only v2's unedited
text, now edited (v3). Its closing line: "No additional P0s."

## Appendix B -- Jev (TypeSafe System One), per-requirement nouls

Request and response archived in the evidence directory (`jev/`). Values are the
probability that the option **violates** the requirement.

| option | R1 owners never vanish silently | R2 no real item hidden | R3 no scope creep | R4 T6 passable with suspended content processes | R5 maintenance | R6 honest `complete` |
|---|---|---|---|---|---|---|
| A-2 X: leave the entering read out | **0.86** | 0.54 | -- | 0.72 | 0.35 | **0.91** |
| A-2 Y: count it, warm-up check (**v3**) | 0.15 | 0.28 | -- | 0.63 | 0.55 | 0.14 |
| A-1 P: replace `launchTime` | -- | -- | **0.77** | -- | 0.37 | 0.16 |
| A-1 Q: separate `startTime`, default nil (**v3**) | -- | -- | 0.21 | -- | 0.28 | 0.26 |
| A-1 S: separate, no default | -- | -- | 0.75 | -- | **0.92** | 0.25 |

Choices: A-2 Y 0.99 over X; A-1 Q 0.75, P 0.25, S 0.00. Read as consequences, not
vetoes: R4 is undecided for both A-2 options (0.63-0.72), which matches what 3.6
states -- a suspended content process younger than a minute, or enough stalls to
truncate the warm-up, still makes `--check` fail.
