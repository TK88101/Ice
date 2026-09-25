# Plan -- one item's unreadable `AXIdentifier`, and step 6's room gate

Two open questions left by the T6 re-freeze and the verify runs of 2026-09-25
(`2026-09-25-residuals.md` Deviations 11 and 12). Both are decisions first and
code second, so the options come with their measured consequences and nothing
is implemented before the ruling.

## 1. Goal and non-goals

**Goal.** Decide, and then implement, what one menu bar item's unreadable
`AXIdentifier` should cost -- today it costs its whole process, which costs
every pass its completeness, which costs T6 its PASS and costs Ice that item
entirely. And decide what to do about step 6's room gate, whose stated remedy
("free 5 pt") is refuted by measurement.

**Non-goals.** Any hiding mechanism. Persistent identity aliasing and transition
telemetry, both ruled out in §3.5. The deferred and withdrawn items (D01,
D02, D15, D30, D31, D32, N3b; D04, D13, D29). Re-running Ice. `getMenuBarItems`.
Anything in `Packages/MenuBarCapture` or the detector files (A4 keeps them
byte-identical to `af4baf1`). Re-opening D10, D7, the pid-in-every-key rule, the
30 s carry window, the `.prohibited` skip, or R3's D14 correction.

## 2. What is measured, before any option is weighed

Every line here is READ or MEASURED today; nothing is inferred.

**M1 -- the error, exactly.** One third-party accessory process (PID 24733;
the app is named only in `~/IceReverse-evidence/`) owns one menu bar item.
Read directly against its `AXExtrasMenuBar` child: `AXFrame` succeeds
(`x=1321, y=4.5, w=34`), `AXIdentifier` returns `-25200` = `kAXErrorFailure`.
Its extras bar has exactly **one** child.

**M2 -- why the frame comes back unread anyway.** `LiveExtrasReader.readChild`
reads role, identifier, title, description, help, frame *in that order*. A hard
error -- anything outside `{success, noValue, attributeUnsupported}` -- sets
`stopped`, and so does a **successful** call that took at least
`slowThreshold`, which the reader normalizes to `cannotComplete`
(`LiveExtrasReader.swift:119-125, 135-141`). Either way `stopped`
which (a) makes every later attribute of that child `notAttempted` and (b)
breaks the process's whole child walk (`LiveExtrasReader.swift:104-160`, the
`if shouldStop { break }` at line 98). The doc comment says this is deliberate:
"frame deliberately last, so any early stop always leaves at least one of
role/identifier/frame unread, which is what makes `ReadClassifier.outcome` fail
this record regardless of which attribute actually triggered the stop."
So the census records `identifier: failure`, `frame: notAttempted` -- **the
frame is unread by our own design, not by the app's refusal** (M1 proves it is
readable).

**M3 -- the blast radius.** `ReadClassifier.attributeFailure`
(`ReadClassifier.swift:110-127`) fails the whole process read; `ItemCatalog.build`
appends the pid to `failedPIDs` and `continue`s, so the process contributes no
items (`ItemCatalog.swift:93-101`); `completeness` becomes
`.incomplete(failedPIDs:)` for the entire pass (line 167).

**M4 -- what `.incomplete` actually costs each consumer.**
- `ItemCatalog.carryOver` (`ItemCatalog.swift:200-244`) is the only thing that
  acts on `.incomplete`: for each failed pid it re-injects that pid's previous
  items for ≤ 30 s from `lastConfirmedAt`, which carrying never advances.
  **This process has never had a successful read, so there is no previous item
  to carry: its item is permanently absent from Ice's list, not merely stale.**
- D10 sectioning (`DiscoveredCachePlan.make:98-173`) never reads `.incomplete`;
  it short-circuits only on `.permissionDenied` (line 99), and its per-boundary
  fallback keys off **Ice's own** read (`evaluate`, lines 181-192), not off a
  third party's. So sectioning is unaffected except that the item is not there
  to be sectioned.
- The check (D7) never reads completeness either: `CheckPlan`,
  `HidingVerification`, `PreparedVerification`, `VerificationGuards`,
  `VerificationTrigger` and `HidingVerifier` contain no reference to it. An
  absent item is simply not a target and raises no skip reason.
- The Ice app layer reads completeness nowhere at all (zero hits in `Ice/`).
  `isLoaded` and the three "Loading menu bar items…" sites key off the cache,
  not the pass, so an incomplete pass still publishes.
- `DiscoveryLabels.compare` (`DiscoveryLabel.swift:94-101`) appends an
  unconditional mismatch for **any** `.incomplete`, whichever pid failed, and
  `mbdiscover --check` exits 1 on any mismatch (`main.swift:160-168`). This is the
  **direct** cause of T6 failing. A missing item is a second, independent way to
  fail the same comparator (`DiscoveryLabel.swift:103-124`), which bites whenever
  labels are frozen against a bar where the item was present -- so "completeness"
  and "the item is absent" are two failure paths, not one.

So the status quo costs, directly: T6 cannot pass while that app runs, and Ice
never shows that app's item. Indirectly, every consumer that works off the item
set sees one fewer item -- D10's candidate set included -- without any of them
reading completeness.

**M5 -- step 6's room gate, and why "free 5 pt" cannot work.** 26 one-second
samples of the bar (13:14:28-13:15:36) while a `verify --dry-run` ran: a
`MenuBarAgent` frame appears at **x=1214** three to six seconds after capturing
starts, and while it is up the leftmost non-agent item moves 1146 → 1098 (-48 pt).
`RoomGuard.readBar` (`StageRun.swift:304-322`) counts an agent frame as the
capture indicator only when it is **left of the leftmost item**
(`agentLeft`, line 308); 1214 is not, so `indicatorUp` stays false and `needed`
keeps its 41 pt reserve. The gate therefore pays 89 pt for one indicator: 48 pt
of room it consumed, plus the 41 pt reserve held against it. The preflight
figure is read before the indicator arrives, which is the whole of the 48 pt
gap between preflight's 189.5 pt and the gate's 141.5 pt in the same run
0.3 s apart. Across the three runs the gate read 141.5 pt at step 2 and
113.5 pt at step 6 **every time**, while preflight read 145.5, 141.5 and 189.5 --
the 48 pt freed before the third run was cancelled, to the point, by the
indicator's 48 pt. Three runs do not prove that every future retry cancels
exactly what was freed; they do show the prescribed one-retry remedy cannot be
relied on as written.

**M7 -- the error is deterministic, and it is one app.** Eight consecutive
direct reads of that child: `AXIdentifier` `-25200` and `AXFrame` success every
time, same frame. A sweep of every running app's extras children on this bar
(13 on-bar items) found `AXIdentifier` answering `-25212`
(`attributeUnsupported`, harmless -- this is the norm and the reason nine items
are `.unnamed`) for every item but two: one answers `success`, and this one
answers `-25200`. So `kAXErrorFailure` on an identifier is, on this machine, a
single app's single item, reproducibly.

**M6 -- one action clears both gates.** That process's item is 34 pt wide at
x=1321, right of the leftmost item, so quitting it moves the leftmost item to
≈ 1180 and the step 6 gate to ≈ 175.5 pt against 118.5 pt needed; it also makes
the census `complete`, which is T6's precondition. Verified read-only, not acted on.

## 3. Question 1 -- what an unreadable identifier should cost

`ItemKeying.assign` (`ItemKey.swift:176-197`) already turns a `nil` identifier
value into `""`, and `""` unique in its process into `.unnamed`, `""` shared
into `.positional` keyed by `childIndex`. So "treat it as unnamed" and "treat it
as positional" are **not two knobs**: they are the two outcomes of the existing
uniqueness count. What has to be decided are five independent axes; the earlier
draft's O1-O5 conflated them (Codex round 1).

### 3.1 The axes

**A -- walk policy.** Its only two results are `proceed` and `stopWalk`; v2's
third result (`stopThisChild`) had no defined use and is dropped (Codex round 2).
- **A1** a hard error -- anything outside `{success, noValue, attributeUnsupported}` --
  or a *successful* call at or past `slowThreshold` normalized to
  `cannotComplete`, stops this child's remaining attributes **and** the
  process's child walk (today; `LiveExtrasReader.swift:104-160`).
- **A2** the same, with exactly one exception: a **fast `AXIdentifier` `failure`**
  proceeds -- to this child's remaining attributes and to the next child.

**B -- accepted identifier-error set (the classifier).**
- **B1** none: only `success`, `noValue`, `attributeUnsupported` are harmless
  (today).
- **B2** `failure` is harmless for `identifier` only; `role` and `frame` keep
  B1's rule.
- **B2s** B2, but only when the process's children snapshot held exactly one
  child (K5's gate).

**C -- what the walk reports.** Today a truncated walk is only *implied*, by
`notAttempted` landing on role, identifier or frame; the moment A2 or a reordered
read removes that implication, the signal has to become explicit. One Bool is not
enough, because "the policy stopped" and "how many children there were" are
different facts and each is needed for a different reason (Codex round 2).
- **C1** neither fact (today).
- **C2** `RawRead` carries both: `walkInterrupted: Bool`, true for **every**
  policy stop -- set the moment the policy returns `stopWalk`, before asking
  whether another attribute or child remained, so it is a policy-event flag and
  not a "work was skipped" flag -- and `childCount: Int`, the size of the AX
  children snapshot beside the records actually produced, `0` whenever the
  children read did not produce a snapshot at all (unambiguous, because
  `childrenError` already fails the read before B2s could apply). Two classifier
  invariants follow, and **both** are R-e, not one (Codex round 3):
  an interrupted read fails whatever B says; **and**, when `childrenError`
  succeeded, `records.count != childCount` is a malformed or partial walk and
  fails independently of `walkInterrupted`. `childCount` is also what B2s gates
  on.

**D -- identity policy.** D1 unreadable becomes `""` and goes through the
existing uniqueness rule (`.unnamed` alone, `.positional` when another record in
the process is also `""`). D2 a new `IdentityBasis` case for "unreadable", which
costs the exhaustive switches at `DiscoveryLabel.swift:155-162` and
`CheckPlan.swift:36-44` plus label-file compatibility. D3 an alias keyed by
`(pid, launchTime, childIndex)` migrating the remembered tag when an unreadable
identifier later reads as declared -- state, child-order ambiguity, migration
tests.

**E -- verifier eligibility.** E1 eligible like any `.unnamed` item (gets a
frame, can be a detector target). E2 excluded like `.positional` (listed, never
verified).

**S -- the seam that makes A testable.** A pure policy proves what the rule
*says*; it does not prove the walk obeys it -- that `proceed` really went on to
read the frame and the next child, or that a stop really set `walkInterrupted`
(Codex round 2, P1). So A needs a seam, and there are two:
- **S1** the walk's *sequencing* moves into IceCore as a pure function over
  injected read operations -- `readProcess(childCount:readsLabels:readString:readFrame:)`
  returning `(records, walkInterrupted)` -- with `LiveExtrasReader` reduced to
  building the closures around each `AXUIElement`. Tests script the closures and
  assert which attributes were asked, in what order, per child, plus the record
  and the flag. IceCore gains the walk order it already depends on in the
  classifier.
- **S2** the order stays in the adapter and gains an injectable attribute-read
  operation, tested in `MenuBarDiscoveryTests`. Smaller diff; IceCore stays out
  of sequencing.

**S2 is the reviewed choice** (Codex round 3): it closes the obedience gap just as
well -- the injected operation can script every attempted read and assert order,
records and interruption -- and AX child traversal, the messaging timeout and the
choice of live attributes belong in the Accessibility adapter, not in the domain
package. S1 is permissible (IceCore would only ever see `String`, `BarRect`, a raw
error name and an elapsed `Double`) but promotes one adapter's traversal protocol
into IceCore for no gain; had it been chosen it would have needed per-child
closures, `(Int, String) -> TimedRead<String>` and `(Int) -> TimedRead<BarRect>`,
not the under-specified pair v3 named. Either seam leaves the live boundary itself
unproven -- AX error mapping, the timeout call, frame conversion, the child
binding -- so **a minimal live smoke test of one real process's walk stays in the
plan** alongside the scripted one.

Either way the policy itself is one pure function, and its result carries three
things, not two (Codex round 3):
`classify(attribute:rawError:elapsed:timeout:) -> (recordedError: String, value: .keep | .discard, decision: .proceed | .stopWalk)`.
The third is there because today's slow-success normalization does two things at
once -- it records `cannotComplete` **and drops the value it just read**
(`LiveExtrasReader.swift:119-125, 135-141`) -- and a policy that only picked the
error name could not require the adapter to discard a `String` or a `BarRect`,
which would change observable `RawRead` contents without changing any verdict.
The comparison stays `>=`: a call at exactly `timeout * slowFraction` is slow
today and must remain slow.

**The axes are not freely composable** (Codex round 2, adopted). Marked
explicitly so no ruling picks an inert pair:
- **A1 · B2 is inert**: under A1's order the frame still comes back
  `notAttempted`, so the record fails anyway -- only the blamed call moves.
  This is v1's old O2, refuted.
- **A2 requires C2**: without it, a continued walk that later stopped would be
  reported complete. This is R-e, and it is why C2 is in the plan at all rather
  than as speculative generality.
- **B2s requires C2's `childCount`**, and K5 additionally requires the frame to
  be read before the identifier **for a known-singleton snapshot only** -- every
  multi-child process keeps today's order, so no other process changes which
  error it reports first.

### 3.2 The combinations worth ruling on

| # | vector | what it costs | what it buys |
|---|---|---|---|
| K0 | A1 · B1 · C1 | nothing | the status quo: T6 unpassable while that app runs; that app's item permanently absent from Ice (M4) |
| K1 | A2 · B2 · C2 · D1 · E1 · (S1 or S2) | the policy, the seam, two fields on `RawRead` threaded through 5 source and 41 test construction sites, one classifier rule | any process with this error is enumerated, with a frame, verifiable; no interrupted walk is ever reported complete; key churn accepted and documented |
| K2 | K1 but E2 | the same, plus a positional-style exclusion | listed but never verified -- smaller blast radius in D7, at the price of never checking it |
| K5 | A1 · B2s · C2 · D1 · E1 · (S1 or S2), frame before identifier for a singleton snapshot only | the same two fields and seam; no walk continuation at all | exactly the measured case (a one-child process, deterministic failure), with today's stop-on-any-hard-error kept everywhere else. A multi-child process with the same error stays as it is today |
| K3 | K1 but D2 | K1 plus every `IdentityBasis` switch and label-file compatibility | "unreadable" never confused with "empty" in evidence or labels |
| K4 | K1 plus D3 | K1 plus persistent alias state and migration tests | the remembered section survives the identifier becoming readable |

**Ruled: K1** (Codex round 4 conceded, Jev agreed from the start -- see Appendix B
and Appendix A round 4). The argument that decided it: K5's defining mechanism is
a conditional reorder of attribute reads for *every* process whose children
snapshot holds one child -- most processes on this bar -- which breaks the
invariant documented at `LiveExtrasReader.swift:104-110`, can change which failure
becomes observable when more than one attribute fails, and is two coupled
mechanisms (a count gate plus an order switch) where K1 is one (tolerate one
error, keep reading). K5 is strictly more machinery for strictly less coverage.
The rest of this subsection records how the contest read before round 4.

**Rounds 2 and 3 had picked K5** (superseded).
K5 wins R-a, R-b and R-d: it changes nothing about when the walk stops, and its
reorder is confined to processes whose snapshot has one child -- the whole of the
measured evidence (M1, M7). R-c and R-e come out equal once the seam and both C2
invariants are in place, and neither vector meets R-f without D3. Nothing measured
makes K1 *unsafe*: M1/M7 establish a deterministic one-child case, which makes K1
broader and less justified rather than harmful -- and equally, they do not
establish that K5 would cover a future multi-child manifestation. K1 is the answer
only if "a multi-child process with an unreadable identifier must also be
enumerated" is adopted as a requirement, which nothing measured today demands. D2/D3 stay documented rejections unless
R-f is retained; neither is implemented "just in case" (Codex round 2, adopted).

### 3.3 Consequences, by name

- **carry-over.** Under K0 the item is absent forever (M4: no successful read has
  ever happened, so there is nothing to carry). Under K1/K2/K5 it is read fresh
  every pass and carry-over never applies to it -- strictly less stale data, not
  more.
- **D10.** No combination changes how sectioning decides anything: it never
  reads completeness, and its per-boundary fallback keys off Ice's own read
  (`DiscoveredCachePlan.swift:181-192`). What changes is the *candidate set* --
  one more item to section (`DiscoveredCachePlan.swift:154-163`) -- and, for that
  one item, `section(for:)` gives a frameless item its previous section or
  `.visible` (`DiscoveredCachePlan.swift:123-126`), which is why E and the frame
  matter here at all.
- **the check (D7).** K1/K5 give the item a frame and an ordinary target. K2
  lists it and skips it. K0 has nothing to check.
- **`--check` and T6.** `.incomplete` produces an unconditional mismatch
  (`DiscoveryLabel.swift:92-101`) -- the direct cause. A missing item is a
  second, independent way to fail the same comparator
  (`DiscoveryLabel.swift:103-124`).

### 3.4 Requirements the ruling is judged against

R-a the behaviour the first run measured is kept wherever it is not the thing
being changed; R-b no scope beyond this file's goal; R-c every change pinned by a
unit test that fails first **and** by a test that the walk obeys the rule; R-d
lower maintenance cost; R-e **no interrupted or partial read is ever reported as
complete**; R-f **forward** continuity -- once the item is admitted under an
empty identifier it may acquire a remembered section, and a later declared
identifier changes its `tagKey` and loses it (`DiscoveredCachePlan.swift:115-119`).
R-f is not disposed of by the item's pre-change absence, which only disposes of
*historical* continuity (Codex round 2, adopted).

### 3.5 The ruling

**Q1 = K1**: A2 (the walk proceeds past a **fast `AXIdentifier` `failure`** and
nothing else) · B2 (`failure` harmless for `identifier` only) · C2 (`RawRead`
carries `walkInterrupted` and `childCount`, with both partial-walk invariants) ·
D1 (the identifier becomes `""` and goes through the existing uniqueness rule) ·
E1 (the item may be a detector target) · **S2** (the sequencing stays in the
adapter behind an injectable attribute-read operation, tested in
`MenuBarDiscoveryTests`, plus one minimal live smoke test).

Ruled by: Jev's per-requirement nouls (Appendix B) and four Codex rounds, the
fourth of which **conceded K1** after Jev contradicted the reviewer's K5
preference (Appendix A round 4). K2, K3, K4 and K5 are documented rejections and
are not implemented.

**R-f is an accepted, documented consequence, not a requirement.** Debated on its
own (Appendix A round 5) after Jev left `rf_is_required` at 0.58. What decided it
was evidence about the *remedy*, not a preference: D3's alias is keyed by
`(pid, launchTime, childIndex)`, and a process that reorders its children would
migrate a remembered section **onto the wrong item** -- a silent misapplication of
the user's own placement, strictly worse than the bounded harm it prevents, which
is one item returning to its default section once, after which the user drags it
back. So:

- no D3, no alias, no persistent state;
- **no telemetry either** (Appendix A round 6): logging the
  `empty → declared` transition would cost either the first logging facility in
  `MenuBarDiscovery`, or D2's rejected identity case, or a new field on the
  discovered item -- and `ItemKeying.assign` (`ItemKey.swift:176-197`) maps a
  missing value and a genuinely empty identifier to the same `""` and the same
  `.unnamed`, so nothing cheaper can tell them apart. Scope (R-b) decides it;
- the consequence is written into this plan and into FINDINGS: **if that process
  ever starts answering `AXIdentifier`, that one item's key changes and its
  remembered section reverts to the default once.** MEASURED against this: the
  failure is deterministic over 8 consecutive direct reads and every pass of
  three sessions today; no flip has been observed.

**Q2** stays as §4 rules it: P1 behind the numeric gate predicate, P2 rejected
for this run, P4 as the fallback with an explicit disposition record.

## 4. Question 2 -- step 6's room gate

§5 of the residuals plan says that if step 6 skips for room, the user frees room
and the stage re-runs once. M5 shows that remedy is **not reliable** under the
indicator behaviour measured today: the gate's figure does not follow the room
the user frees, because the indicator takes 48 pt and keeps its 41 pt reserve at
the same time. Three runs is not proof that every future retry cancels exactly
what was freed (Codex round 1, P2 on M5) -- it is proof that the one-retry
remedy cannot be relied on as written.

Step 6 has **two** room gates, not one: before the pair launch
(`StageVerify.swift:134`) and again before the relaunch of its second half
(`StageVerify.swift:186`). Any remedy has to clear both.

| # | option | what changes | consequence |
|---|---|---|---|
| P1 | the user quits the app of M6 (the same one Q1 is about), **then both gates are predicted read-only, with a numeric margin, before the stage is run** | nothing in code | see the gate predicate below; M6's ≈ 175.5 pt is an estimate for the first gate only, and P1 is conditional on the predicate clearing at both |
| P2 | count an indicator-width agent frame anywhere among the items as `indicatorUp` | `RoomGuard.readBar`'s `agentLeft` filter | **rejected for this run** (Codex round 1, adopted): it changes a pre-registered gate after seeing it miss, and width alone does not prove a frame is the capture indicator. A legitimate future revision needs independent characterization of the frame's correlation with capturing, lifetime and race handling, every related guard updated, and a rerun from preflight |
| P3 | quit the step 2 reference helper before step 6 | `StageVerify` | **refuted by the code**: step 6 requires it (`StageVerify.swift:127` guards on `reference`/`referenceKey`, line 147 passes both to `step6a`). Note step 6 already quits the *target* before its room read (line 129), so 113.5 pt is the figure with only the reference up |
| P4 | close R14 with step 6 pre-registered as skipped | documentation | the two-item half of section 6 stays unmeasured. Not a pass: it requires an explicit R14 disposition record -- the gate readings, the cause, and the user's approval of the closure, written into this plan's ledger and the evidence directory -- rather than presenting non-execution as a result (Codex round 3) |

**The gate predicate** (objective, read-only, no stage run). Both step-6 gates
have the same occupancy -- the reference helper up, the target or the pair quit
(`StageVerify.swift:129, 186`) -- so one predicate covers both:

```
predictedFree = (leftmostNonAgentOnBarItemX - notch.hi) - 76
```

where 76 pt = 48 pt for the capture indicator (MEASURED, M5) + 28 pt for the
step-2 reference helper (MEASURED: the step-2 gate read 141.5 pt and the step-6
gate 113.5 pt in all three runs). The gate needs 118.5 pt, so the run starts only
when **`predictedFree >= 138.5` pt** -- a 20 pt margin -- in **five** read-only
samples taken 2 s apart, all five clearing it, written to
`<evidence>/step6-gate-prediction.txt`. Today's reading is 189.5 - 76 = 113.5 pt,
which fails the predicate; quitting M6's item (34 pt at x=1321, right of the
leftmost item) is predicted to move the leftmost item to ≈ 1180 and
`predictedFree` to ≈ 147.5 pt, which clears it.

## 5. Tasks (change → test first → DoD)

Nothing here starts before §3's ruling. The task list is written for the K1/K5
family; a ruling for K0 deletes T-1..T-5 and keeps T-6..T-8.

| # | task | test first | DoD |
|---|---|---|---|
| T-1 | the pure policy in IceCore: `classify(attribute:rawError:elapsed:timeout:) -> (recordedError, decision)`, owning the slow-success normalization too. `AttributeRead` carries no duration (`DiscoveryInputs.swift:62-70`), which is exactly why the decision cannot live in the classifier | policy unit tests: a fast `identifier` `failure` proceeds; the same error slow stops; a fast `role` or `frame` error stops; every harmless error proceeds; and the normalization pinned in both types -- a **slow success carrying a non-nil `String`** and one carrying a non-nil `BarRect` each become `value: .discard` + `cannotComplete` + `stopWalk`, at `elapsed == timeout * slowFraction` **and** just below it, so the `>=` boundary cannot drift | tests red first, then green; IceCore still imports only the standard library |
| T-2 | the seam (reviewed choice: S2 -- an injectable attribute-read operation in the adapter, tested in `MenuBarDiscoveryTests`), so the walk's *obedience* is testable, not just the rule | a scripted-read test asserting, per child, **which attributes were asked and in what order**, the resulting records, and `walkInterrupted` -- written for the ruled vector, not generically (Codex round 3). For **K5**: a singleton snapshot is asked `role → frame → identifier` (label attributes in their selected place), records that frame, stops on the identifier and sets `walkInterrupted`; a **multi-child** snapshot keeps today's order and stops as today; a stop on the final planned read still sets `walkInterrupted`. For **K1**: a fast identifier failure goes on to ask the frame and the next child; a slow one asks neither; an error after a tolerated one leaves the read interrupted | red first, then green; the trace assertions are specific to the ruled vector, so an implementation of the other vector fails them. Plus one minimal live smoke test of a real process's walk, for the boundary no scripted test reaches |
| T-3 | `RawRead` gains `walkInterrupted: Bool` and `childCount: Int`, both required by the initializer with **no default** so no site can be missed silently | two classifier tests, each stating its expected outcome: every record clean but `walkInterrupted` true → `.failed`; and `childrenError` successful with `records.count != childCount`, `walkInterrupted` false → **also** `.failed` (the partial-walk invariant, independent of the flag). Plus `childCount == 0` whenever the children read produced no snapshot | red first, then green |
| T-4 | the classifier rule the ruling picks (B2 or B2s) | a `ReadClassifier` test: a record with `identifier: failure` and a readable frame, not interrupted → `.items`; a multi-child process where child 0 has the tolerated error and a later child fails → `.failed`; under B2s, the same tolerated error with `childCount == 2` → `.failed` | red first, then green |
| T-5 | an `ItemCatalog`-level test, which the suite has none of today: one record's tolerated identifier error no longer flips the pass's completeness, and the item reaches `items` with its frame | the test | red first, then green |
| T-6 | thread the two fields through every construction site: `LiveExtrasReader.swift:74` and `:88` (process-level early exits: `false`, `childCount` 0), `:101` (from the walk's own result), `MenuBarDiscoverer.swift:127` (the synthetic deadline read: not attempted, so `false`), and **`MenuBarDiscoverer.swift:164` `subtractOrigin`, which reconstructs `RawRead` and would silently drop both facts** (Codex round 2); plus 41 test construction sites across 9 files, each updated deliberately | the existing suites, which must still pass unchanged in meaning | every site updated with a stated intent; no site takes a default |
| T-7 | the ledger: FINDINGS' open question answered; M1-M7 recorded; the Refuted table's three duplicate rows left alone | n/a | FINDINGS and this plan agree |
| T-8 | T6-a: residuals §4 as written, with the app quit, run by an `mbdiscover` built from **9afd236** (the pre-change commit, via `git archive` into `/private/tmp` -- the working tree already carries the change, and a build artifact is the honest way to hold the old behaviour still) | n/a | PASS, or VOID three times reported. The labels it freezes are `L` |
| T-9 | three checks, not one, so that "the app was quit" and "the code changed" are never the same variable: **(a)** app quit, changed code, `--check L` → must PASS, which is the regression check proper (the change is behaviour-preserving when the error is absent); **(b)** app running, **pre-change** binary, `--check L` → must fail with `incomplete pass`, which pins the starting point as a measurement rather than a memory; **(c)** app running, changed code, `--check` against `L` plus **exactly one** added label for the previously-absent item → must PASS. `L` and T6-a's evidence preserved, never overwritten; the one-label patch kept as its own artifact | n/a | (a) PASS, (b) fails for that reason and no other, (c) PASS with no delta beyond the one label, justified in writing. Limit stated: a discovery-label regression check, not evidence about frame coordinates or anything labels do not encode (Codex round 2) |
| T-10 | step 6 once §4's ruling holds: **both** gates re-measured read-only with margin first | n/a | both halves run ("gone" two `hidden(folded: false)`, "stayed" two `stillDrawn`), or P4 with its cause |

T-8 before the code change and T-9 after it exist because re-freezing labels
*after* changing discovery would normalize the very change T6 is meant to detect
(Codex round 1, adopted).

## 6. Acceptance

| # | check |
|---|---|
| X1 | every named suite passes -- IceCore, MenuBarDiscovery, MenuBarDetectorFeed, MenuBarCapture, SafeWidthCore, IceWatchCore -- with line coverage ≥ 80 % for IceCore and for Discovery+Feed excluding the live adapters and the CLI, measured by the commands recorded in the evidence package. Counts are reported for the ledger, not asserted (Codex round 3: fixed counts are brittle) |
| X2 | Ice builds (`CODE_SIGNING_ALLOWED=NO`, external derived data); `build.sh` builds the probes |
| X3 | A3, A4 (`git diff --exit-code af4baf1 -- Packages/MenuBarCapture <detector files>`), A8 (zsh, table unchanged), A8b (greps empty), A10 (zsh) |
| X4 | IceCore imports only the standard library |
| X5 | T6-a PASS **or** a protocol closure the user explicitly approves -- "VOID three times" is evidence of non-completion, not a pass (Codex round 1, adopted); T6-b agreeing with exactly one reviewed added label and no other delta |
| X6 | step 6's two halves met after the gate predicate cleared at five samples, or P4's explicit R14 disposition record -- gate readings, cause, and the user's approval of the closure |
| X7 | `/simcodex` ends with no P0/P1; full test run green; evidence package delivered; commit / merge / push wait for the user |

## 7. Impact surface

- `Packages/IceCore/Sources/IceCore/ReadClassifier.swift` -- the rule.
- `Packages/IceCore/Sources/IceCore/DiscoveryInputs.swift` -- `RawRead`'s two new
  required fields.
- a new IceCore file for the policy, and (under S1) the pure walk sequencing.
- `Packages/MenuBarDiscovery/Sources/MenuBarDiscovery/LiveExtrasReader.swift` --
  the walk; a live adapter, excluded from the coverage floor.
- `Packages/MenuBarDiscovery/Sources/MenuBarDiscovery/MenuBarDiscoverer.swift` --
  the synthetic deadline read at `:127` and `subtractOrigin` at `:164`.
- the IceCore, MenuBarDiscovery and Feed test suites: 41 `RawRead` construction
  sites across `ItemCatalogBuildTests` (17), `DiscoveredFrameReaderTests` (12),
  `Fakes.swift` in both test targets (4 + 1), `DiscoveryInputsTests` (3),
  `ItemCatalogCarryOverTests`, `ReadClassifierTests`, `DiscoveryLabelsTests`,
  `MenuBarDiscovererTests` (1 each).
- `docs/macos-27/FINDINGS.md` and this plan.
- **only if the ruling picks D2**: `DiscoveryLabel.swift:155-162`,
  `CheckPlan.swift:36-44`, the detector's `childIndex` filtering, and label-file
  compatibility.
- **not** `Packages/MenuBarCapture` or the detector files (A4). **not**
  `docs/macos-27/probes/visibility/**`, since round 1 rejected P2 for this run.

## 8. Risks and rollback

| risk | response |
|---|---|
| a degraded read hides a genuinely broken process | the tolerated set is exactly one attribute, one error, fast only, and under K5 only for a one-child snapshot; everything else keeps K0's behaviour, pinned by T-1, T-2 and T-4 |
| an interrupted walk is reported as complete | `walkInterrupted` is set for **every** policy stop and fails the read whatever B says; T-3 pins it. This is R-e and it is not negotiable |
| the rule is right but the walk disobeys it | that is exactly what T-2's seam and scripted-read test exist for; a pure policy alone would not catch it (Codex round 2) |
| a key flips when the identifier starts reading | documented, not fixed, by K1/K2/K5; K4 is the option that meets R-f, at the cost of state. R-f's necessity is a ruling, not an assumption |
| `RawRead` gains two required fields | no defaults, so the compiler names every one of the 5 source and 41 test sites; `subtractOrigin` is called out by name because it reconstructs the value |
| continuing the walk costs time on a hostile process | continue only after a **fast** error; the per-call timeout is unchanged. The arithmetic, measured off the code in review: for a process that answers this way at *every* child, worst-case AX calls per pass go from **4** (bar + children + role + identifier, then the break) to **2 + 6N** -- 122 at N = 20, about 30x. That is the cost of recovering the frame and the later children, not waste, and neither budget breaks: tolerance requires `elapsed < slowThreshold` (≈ 0.2 s) or the walk still stops, and `MenuBarDiscoverer`'s 2.0 s pass deadline is checked between processes, as it was before this change |
| changing a pre-registered gate mid-protocol | P2 rejected for this run; P1 conditional on re-measuring both gates; P4 as the fallback |
| iCloud duplicates after a rewrite | check for `X 2.swift` before every build, per project memory |
| rollback | checkpoints on `wip/identifier-failure` only; never pushed, never merged; `git revert` per checkpoint |

## Deviations (ledger)

Format: trigger → what changed → reason.

1. **Enforcement last (sequencing).** `RawRead`'s two new fields were added and
   threaded through all 5 source and 41 test construction sites **before** any
   behavioural test was written, and the suites were run green at that point
   (IceCore 333, MenuBarDiscovery 19, Feed 36 -- unchanged counts, unchanged
   meanings). Only then were the behavioural tests written. Reason: a test that
   fails because a signature changed is not evidence (residuals Deviation 7), so
   the signature change had to land first for the red to mean anything.
2. **TDD record, and it is behavioural throughout.**
   - `AttributeWalkPolicy` was first written with **K0 semantics** (today's rule,
     no tolerated error) so its 10 tests could fail for a behavioural reason.
     Exactly one failed -- the tolerated case -- and the other nine passed, which
     is what proves the suite was pinning today's behaviour and not the new code.
     Adding the exception turned it green.
   - The five new `ReadClassifier` tests were run before the classifier changed:
     **four red** (`.items` expected and `.failed` returned, and the reverse for
     the two invariants), one green -- the one that pins existing behaviour
     (a fast `cannotComplete` on the children read is still "no items", not a
     partial walk).
   - The 10 walk-trace tests were written after the seam, so their red is by
     **mutation** instead, each reverted and the file verified identical
     afterwards: removing the K1 exception → the two tolerated-case traces fail
     (the frame is never asked for); tolerating the error however slow → the slow
     case fails; keeping the value on a slow success → both discard tests fail.
   - The five `ItemCatalog` tests, which are the first at that layer at all, were
     mutation-checked the same way: with the classifier's tolerance removed, four
     of the five fail.
3. **`FailureReason` gained two cases** (`walkInterrupted`, `partialWalk`) rather
   than reusing `unexpectedError`: the record that triggered a stop can now look
   clean, so the stop is the fact to report, and a count mismatch is a different
   fault from an attribute error. Cheap because nothing in production switches
   over `FailureReason` -- only tests pattern-match it.
4. **The attribute order is unchanged**, deliberately. `LiveExtrasReader`'s old
   comment justified the frame's lastness as what made a stopped walk fail;
   `walkInterrupted` carries that now, so the order is no longer load-bearing --
   but reordering would change which failure a process reports first, which is
   exactly the R-a regression that lost K5 the ruling.
5. **Coverage.** IceCore 97.86 % lines (353 tests); MenuBarDiscovery + Feed
   97.56 % lines over the plan's exclusions (live adapters, the CLI, the live
   verification factory), 29 + 36 tests. `LiveExtrasReader` itself went from
   wholly uncovered to 37 of 125 lines, since the walk it now delegates is
   scripted in tests -- it stays an excluded file regardless.
6. **A regex bug of mine, and its repair.** The script that threaded the two
   fields through the test sites matched `RawRead(` inside the identifiers
   `readerRawRead(` and `readerFailedRawRead(`, so it appended arguments to a
   helper's signature and to ten of its call sites. Caught by the editor's
   diagnostics before any test ran, repaired in place (the helper already sets
   both fields itself), and the whole suite re-run green. No revert was needed
   and nothing but my own edit was touched.

7. **T6 needed no user action in the end, and became a stronger measurement.**
   T-8/T-9 were written assuming the app had to be quit for the census to read
   `complete`. The change itself makes it read `complete` **with that app
   running**, so T6 ran as residuals §4 writes it and **PASSED**: `agree: 11
   labels`, exit 0; the negative control detected; no drift in any labelled
   field; warm passes 16-30 ms, every one `complete`. Evidence
   `~/IceReverse-evidence/20260925-140256-t6` (`result.md` there).
   The control is better than T-9's planned label diff, because it holds the bar
   still instead of the code: at the same minute, on the same bar, with the same
   app running, the binary built from `9afd236` reported 10 items and
   `incomplete(1 failed)` while the changed one reported 11 and `complete`. One
   item's difference, and it is the item at x=1321 whose identifier read fails.
8. **T-9(a) is retired as written, and why.** It asked for "app quit, changed
   code, `--check L` -> PASS". With `L` frozen while the app runs, quitting the
   app must make the check fail on a missing item -- correctly -- so that
   comparison cannot be run against this `L` and would need a second frozen set
   to mean anything. Its purpose (the change is behaviour-preserving where the
   error is absent) is met by evidence already in hand: every pre-existing test
   in all six suites is green with no expectation altered (IceCore 333 -> 353 by
   addition only), and A3, A4, A8 (71 hits), A8b and A10 all pass.
9. **Still owed to the user, and only this**: the step-6 room gate. It does not
   turn on the identifier error but on the leftmost item's x, so it still needs
   that app (or any one menu bar icon) quit -- `predictedFree` is 113.5 pt against
   the 138.5 pt the predicate requires.

10. **The two new facts are belt and braces today, and that is the point**
   (simcodex round 1, the altitude and security reviews agreeing independently).
   Under this exact policy no live read can reach them: the only tolerated error
   is on `identifier`, `frame` is read after it, so every stop still leaves a
   non-harmless `frame` on the interrupted child, which the per-record check
   already fails -- `interruptedWalkFails` has to hand-build a `RawRead` the real
   reader cannot produce. They are in the plan because that is a coincidence of
   the read order, and Deviation 4 says the order is no longer load-bearing: the
   moment a tolerance reaches `role` or `frame`, or the order changes, or a second
   adapter produces a `RawRead`, they are what keeps R-e true instead of silently
   regressing it. Said plainly in the code rather than implied to be load-bearing.
11. **The security review's MEDIUM-2 was refuted by measurement, and a
   different, real hazard took its place.** As reported: `childCount` was taken
   after `(childrenValue as? [AXUIElement]) ?? []`, and since that cast "fails
   wholesale when any one element is not an `AXUIElement`", a process could
   return N children, yield zero records, and have the pass read
   `.items([])` -- "no extras, read complete". I changed the count to come from
   `CFArrayGetCount` and wrote a test for the shape.

   **Then the round-2 mutation check said the change was pinned by nothing**: put
   `children.count` back and every suite stayed green. MEASURED directly
   afterwards, which is what settles it: `as? [AXUIElement]` **does not check its
   elements**. `AXUIElement` is a Core Foundation type, so the conditional cast
   succeeds on any `CFArray` whatever it holds -- `[NSString, NSNumber]` casts to
   "an array of 2", and so does `[AXUIElement, NSNumber]`; only
   `as? [NSString]` returns `nil`, which is the cast the review's own probe used.
   So `children.count` always equalled `CFArrayGetCount`, the described hole
   cannot occur, and my fix was a no-op.

   What the measurement did expose is worse than the reported hole and was there
   all along: the unchecked cast hands the walk **garbage elements**, and the walk
   then calls `AXUIElementSetMessagingTimeout` and
   `AXUIElementCopyAttributeValue` on a value another process chose and that is
   not an element at all. The fix is therefore a filter, not a count:
   `childElements` checks each member's type id, `snapshotCount` still counts what
   Accessibility claimed, and a malformed answer now leaves
   `records.count != childCount` -- which `ReadClassifier` fails as
   `.partialWalk` instead of the walk reaching into it. Nothing changes for a
   well-behaved process: every child is an element and the two agree. Pinned by
   four tests over real `AXUIElement`s made for our own pid, and mutation-checked
   (revert the filter -> two red).

   This is the "silent half of a fix" pattern from the learned skill, caught by
   the one thing that catches it: the reported symptom was imaginary, the
   underlying hazard was real, and the first fix addressed neither.

12. **`.discard` on the tolerated error** (security review LOW-1): the tolerated
   verdict kept whatever the failed call returned, so "tolerated failure implies
   no identifier" was true by trust, not by construction -- if Accessibility ever
   populated the out-parameter while returning the error, the item would be keyed
   on a string a failed call produced. Now discarded, and the policy test says so.
13. **The census carries both facts** (security review LOW-6): `--census-json`
   omitted them, which would have left the very artifact this tolerance was argued
   from unable to tell a truncated walk from a complete one. Verified live: 70
   reads, both keys present, none interrupted, no count mismatch.

14. **T6's real precondition, found after it passed.** The check was re-run
   after the round-2 fixes and came back `incomplete` three times, then four and
   five -- a growing count, so not a transient. The census named them: four
   `com.apple.WebKit.WebContent` XPC services, each holding its
   `AXExtrasMenuBar` read for the full 0.25 s. Not a regression from anything in
   this plan -- the census shows no `partial`, no `walkInterrupted`, and no
   attribute error beyond the tolerated one, and the previously-absent item is
   still enumerated (items 11, unnamed 10). The T6 PASS recorded at 14:02 stands
   on its archived evidence; what changed is the bar's condition, not the code.
   The finding itself is in FINDINGS: those processes are `.accessory`, so the
   `.prohibited` filter that `RunningAppsProviding.swift:20-28` names as the
   mitigation for exactly this case never sees them. Out of scope here, and the
   obvious widening is wrong (`.accessory` is what real menu bar apps are).

15. **R14, step 6: PASS, and the gate predicate held to the decimal.** After the
   operator freed room (four icon-owning apps quit), the read-only predicate
   `predictedFree = leftmost - notch.hi - 76` read **251.5 pt** over five samples
   against the 138.5 pt it required; the live gates inside the run read 279.5 at
   step 2 and **251.5 at both step-6 gates** (the pair launch and the relaunch) --
   the predicate matched the measurement exactly, at both. All pre-registered
   expectations met: (a) the pair's second child `drawn(x: 1161.5)` against
   `axMinX: 1160`; (b) "gone" both `hidden(folded: false)`, "stayed" both
   `stillDrawn`; `userItemsDisplaced: 0`, helper domains empty, MenuBarAgent
   defaults unchanged. Evidence `~/IceReverse-evidence/20260925-145221-vzverify3` (`result.md`),
   probe data `20260925-145233-vzverify`. **P4 is not needed and §4's fallback goes unused.**
16. **The attempt before it aborted at step 3, for the same root cause as the room
   gate.** `agentSetMatchesPreflight` went false at `step3.start`, two user items
   left their baseline x, and the safety monitor stopped the run -- correctly, and
   with room never in question (279.5 against 118.5). The cause is M5's capture
   indicator arriving mid-run among the items; it had been costing the room gate
   89 pt, and here it displaced user items instead. It also moved macOS's own
   `MenuBarAnalytics.lastReportedTrailingItemCount` 10 -> 11, which counts items on
   the bar rather than being a setting the probe wrote. Teardown verified clean:
   no helper process, helper domains empty, and the bar back to on-bar 9 /
   leftmost 1284.0 over three samples. So the thing between a run and step 6 is
   the indicator's timing, not room -- which is also the independent
   characterisation a future P2 revision was said to need.

## Appendix A -- review record

### Round 1 (Codex, gpt-5.6-terra, reasoning=medium, on v1: 7 P1, 6 P2)

| # | finding | ruling |
|---|---|---|
| 1 | "fast" is not representable: `AttributeRead` has no duration (`DiscoveryInputs.swift:62-70`), `slowFraction` applies only to the extras/children calls | **modified.** The premise is right and verified, the conclusion is not: v1 put the fast/slow judgement in the *adapter*, which holds the clock -- not in the classifier. The real defect it exposes is testability, which is why v2's T-1 extracts the decision into a pure IceCore policy taking `(attribute, error, elapsed, timeout)`. That makes A2 unit-testable without giving `AttributeRead` a duration |
| 2 | "stop only when slow" would also loosen fast `role`/`frame` errors unless narrowed to `AXIdentifier` + the exact error | **adopted.** Axis A2 is now exactly one attribute and one error, fast only; T-3 pins a multi-child process where a later child still fails |
| 3 | no option fixes identity stability; D5-as-drafted was not a stability fix | **adopted.** v2 says so outright, and adds D3 (the alias keyed by `(pid, launchTime, childIndex)`) as the only option that buys continuity, with its cost stated |
| 4 | the option space is incomplete and wrongly coupled; a singleton-only option is missing | **adopted.** v2 §3.1 is five independent axes; §3.2 is the combinations, including K5, the singleton-only one |
| 5 | O2 "changes nothing" is overstated -- it moves the blamed call | **adopted.** Reworded to "does not meet the goal under the current walk order" |
| 6 | M2's "every error" omits a slow *successful* call normalized to `cannotComplete` | **adopted**, verified at `LiveExtrasReader.swift:119-125, 135-141` |
| 7 | M4's "only this makes T6 unpassable" and "exactly two things" are too absolute | **adopted.** M4 now separates the direct completeness mismatch from the second, independent missing-item path, and names the indirect consequences |
| 8 | M5's "cannot work" overreaches from three runs | **adopted.** Restated as "cannot be relied on as written", with the sample kept as the condition |
| 9 | P1 is not demonstrated sufficient: step 6 has **two** room gates (`StageVerify.swift:134` and `:186`) | **adopted**, verified. P1 is now conditional on re-measuring both gates read-only, with margin, after a warm-up |
| 10 | P2 is an outcome-driven change to a pre-registered gate, and width alone does not identify the indicator | **adopted.** P2 rejected for this run; the conditions for a future revision are written down |
| 11 | a classifier fixture cannot prove later attributes and later children were attempted | **adopted.** T-1 (the pure policy) plus T-2 (the truncation signal) are exactly this; T-4 adds the `ItemCatalog` level the suite lacks |
| 12 | "re-freeze" plus "VOID three times" is not an acceptance criterion; re-freezing after the change normalizes what T6 should detect | **adopted, and it changed the plan's shape.** T-6 (before the change, app quit) and T-7 (after the change, app running, T6-a's labels plus one reviewed added label) replace a single re-freeze; X5 no longer accepts VOID as a pass |
| 13 | the impact surface misses `IdentityBasis`'s exhaustive switches and label-file compatibility if a case is added | **adopted**, and it is now an argument against D2 rather than a cost to absorb silently |

Nothing was rejected outright; findings 1 was accepted in premise and modified
in conclusion, and the disagreement was fed back in round 2.

### Round 2 (Codex on v2: 5 P1, 5 P2) -- round 1's finding 1 declared resolved

| # | finding | ruling |
|---|---|---|
| 1 | a pure policy does not prove the *adapter obeys* it; a live-only walk leaves that untestable | **adopted.** Axis S added: S1 moves the sequencing into IceCore over injected reads, S2 gives the adapter an injectable read operation. T-2 asserts which attributes were asked, in what order, per child, plus `walkInterrupted` |
| 2 | `stopThisChild` had no defined use | **adopted.** The policy has two results, `proceed` and `stopWalk` |
| 3 | one Bool is not enough: it must mean "the policy interrupted the walk" (including on the last attribute of the last child), and K5 additionally needs the children snapshot's size | **adopted.** C2 is now two facts, `walkInterrupted` and `childCount`, explicitly not alternatives |
| 4 | K5 was underspecified and would reorder reads for every process | **adopted.** K5 is a full vector, and the reorder is confined to a known-singleton snapshot |
| 5 | the axes are not freely composable (A1·B2 inert; A2 requires C2) | **adopted**, marked inline so no ruling picks an inert pair |
| 6 | prefer K5 over K1 unless multi-child support is stated as a requirement | **adopted as the framing**, not as the answer: §3.2 now says the contest is K1 vs K5 and hands it to Jev with R-a/R-b/R-d favouring K5 |
| 7 | the new fields must be threaded through more than the live reader -- `subtractOrigin` reconstructs `RawRead` and can drop them | **adopted**, verified: 5 source sites (`LiveExtrasReader.swift:74,88,101`, `MenuBarDiscoverer.swift:127,164`) and 41 test sites across 9 files; T-6 names them and the initializer takes no default |
| 8 | R-f is not disposed of by the item's pre-change absence -- that only disposes of *historical* continuity | **adopted.** R-f is restated as forward continuity, retained or dropped explicitly, never by that argument |
| 9 | T-6/T-7 are sound; state their limit and keep the one-label patch as an artifact | **adopted** into T-9 |
| 10 | D2/D3 would be over-engineering unless R-f is retained; keep C2 only because A2/K5 need it | **adopted**, said in §3.2 |

Nothing rejected in round 2 either. Round 3 puts v3 back for the two things that
changed materially: the S seam and the K1-vs-K5 contest.

### Round 3 (Codex on v3: no P0, 3 P1, 6 P2) -- converged

| # | finding | ruling |
|---|---|---|
| 1 | **P1** the policy result cannot express today's slow-success *value drop*; a naive migration would keep the value beside `cannotComplete` and change observable `RawRead` contents | **adopted.** The result is now a triple including `value: .keep / .discard`, and T-1 pins the normalization in both `String` and `BarRect` at `elapsed == timeout * slowFraction` and just below, so the `>=` boundary cannot drift |
| 2 | **P1** partiality is not yet a classifier invariant: `records.count != childCount` can expose a partial walk with `walkInterrupted == false` | **adopted.** C2 now states **two** invariants, and T-3 states the expected `.failed` for each; `childCount == 0` whenever the children read produced no snapshot |
| 3 | **P1** T-2's wording describes K1's trace, so a K5 implementation could pass it without proving its own narrowness | **adopted.** T-2 is now vector-specific: K5's singleton `role → frame → identifier`, multi-child order unchanged, and a stop on the final planned read still setting the flag |
| 4 | **P2** S2 closes the obedience gap and is the better architecture; S1 promotes an adapter's traversal protocol into IceCore; either seam leaves the live boundary unproven | **adopted.** S2 is the reviewed choice, S1's cost is recorded, and a minimal live smoke test is added for the boundary no scripted test reaches |
| 5 | **P2** K5 wins R-a/R-b/R-d; R-c/R-e equal once the seam and both invariants land; neither meets R-f without D3; nothing measured makes K1 unsafe, only broader | **adopted** as the review's verdict, put to Jev rather than taken as final |
| 6 | **P2** `walkInterrupted` is implementable unambiguously in both seams as a policy-event flag | **adopted**, and written that way |
| 7 | **P2** "with margin" is not objective; P4 needs an artifact; X1's fixed counts are brittle | **adopted.** §4 now carries a numeric gate predicate (`predictedFree >= 138.5` pt, five samples 2 s apart, a named evidence file), P4 requires an explicit R14 disposition record, and X1 asserts suites-pass-plus-coverage-by-command with counts reported for the ledger only |
| 8 | **P2** §4's P1/P2/P4 rulings confirmed | noted |

Three rounds, nothing rejected, and round 3 named winners (S2, K5) with no P0
outstanding -- the debate is converged. What remains is not a disagreement with
the reviewer: it is R-f, a value judgement no evidence settles, which goes to Jev
and then to the user.

### Round 4 (Codex, narrow: the K1-vs-K5 contradiction fed back) -- conceded

Jev's per-requirement nouls put K5 as the *more* violating vector on exactly the
three requirements rounds 2 and 3 had awarded it (R-a 0.66 / 0.46, R-b 0.69 / 0.42,
R-d 0.58 / 0.20). Fed back with the argument that reading implies: K5's defining
mechanism is a conditional reorder for every one-child process -- most processes on
this bar -- which breaks the invariant at `LiveExtrasReader.swift:104-110` and can
change which failure becomes observable when more than one attribute fails.

**Codex conceded: "K1 wins", and called its own prior K5 recommendation wrong.**
Its reasons: K1 is one mechanism (allow the specified identifier failure, continue
the existing sequence) against K5's two coupled ones (inspect the child count, then
choose a different order); the count condition does not narrow the reorder, it
applies the altered semantics to the predominant process shape; and K5 must
maintain two orders, their predicate, and the resulting first-error attribution
forever. "K5 is strictly more machinery for strictly less coverage."

### Round 5 (Codex, R-f on its own, before putting it to the user)

Asked to argue both sides and decide. **Verdict: accept and document the one-time
section reset; do not implement D3.** The case *for* R-f was stated fairly -- a
user's explicit placement should not vanish because accessibility metadata
improved; the failure could start succeeding after an app update, a TCC change or
a macOS point release; several items flipping together, an invisible default
section, or oscillation would each be worse than one drag. What defeated it was
the remedy: D3's `(pid, launchTime, childIndex)` alias is a plausible identity,
not a durable one, and a process that reorders its children would migrate a
remembered section **onto the wrong item** -- silently misapplying the user's
placement, a worse failure than the bounded one it prevents. Its sentence for the
owner: "Record R-f as an accepted, monitored consequence: do not add the fragile
persistent alias for an unobserved transition whose bounded one-time section reset
is safer than risking silent section migration to the wrong item."

### Round 6 (Codex, the telemetry add-on, with new evidence fed back)

Round 5 proposed structured `empty → declared` telemetry as the cheap half of
"monitored". Evidence found afterwards and fed back: `MenuBarDiscovery` has **no
logging facility at all** (no `import os`, `Logger`, `os_log` or `print` anywhere
in its sources), and logging it in the Ice layer instead needs "unreadable rather
than empty" to survive into the result -- which is exactly the rejected D2, since
`ItemKeying.assign` (`ItemKey.swift:176-197`) maps a missing value and a genuinely
empty identifier to the same `""` and the same `.unnamed`. The options were
therefore (a) first-ever logging in that package, (b) D2, (c) a new Bool on the
item, or (d) nothing.

**Codex chose (d), no telemetry**: "preserving 'unreadable versus empty' solely to
log it expands scope beyond deciding and fixing the reset behavior. Record the
accepted one-time-reset consequence in the plan and FINDINGS, without adding
logging infrastructure, identity semantics, or discovery fields."

Six rounds, one concession, nothing rejected out of hand on either side. The two
judges disagreed exactly once (K1 vs K5) and the disagreement was resolved by
feeding each side's evidence to the other, not by preferring a judge.

## Appendix B -- Jev

Asked as the first run was: one noul per (vector x requirement), options and
vectors described neutrally, the plan's own preference not marked, no installed
app named. Request and response archived at `/Users/ibridgezhao/IceReverse-evidence/20260925-133455-jev`
(`request.json`, `response.json`; model `jev-1.13.0`). High = **violates**.

| vector | R-a | R-b | R-c | R-d | R-e | R-f |
|---|---|---|---|---|---|---|
| K0 | 0.16 | 0.41 | 0.26 | 0.35 | 0.13 | **0.79** |
| K1 | 0.46 | 0.42 | 0.26 | **0.20** | 0.22 | 0.13 |
| K5 | **0.66** | **0.69** | 0.27 | **0.58** | 0.22 | 0.13 |

Three separate results, and one of them contradicts the reviewer:

1. **K5 versus K1 is reversed.** Codex awarded K5 exactly R-a, R-b and R-d; Jev
   puts K5 as the more violating vector on exactly those three. The reading that
   implies is substantive and neither review had addressed it: K5's defining
   mechanism is a *conditional reorder of attribute reads for every process whose
   children snapshot holds one child* -- most processes on this bar -- which is a
   change to behaviour that is not the thing being changed (R-a), a second
   mechanism beside the count gate where K1 has one (R-b), and two orderings to
   keep straight forever (R-d). It also deliberately breaks the invariant
   documented at `LiveExtrasReader.swift:104-110`. Fed back to Codex as round 4.
2. **R-f stays undecided.** `rf_is_required` = **0.58** -- inside the band the
   project memory's rule calls undecided -- so whether forward continuity is a
   requirement (and D3's state paid for) or an accepted documented consequence
   **goes to the user**, exactly as §3.4 said it would.
3. **The seam is a near-tie, and step 6's remedy has one clear loser.**
   `seam_choice`: domain package 0.58, adapter 0.42, confidence 0.16 -- noise, no
   veto over Codex's S2, which has the repo's own constraint behind it (IceCore
   imports only the standard library and must not know Accessibility).
   `step6_remedy`: change-the-gate-rule **0.06** -- Jev and Codex agree P2 is
   wrong -- with close-as-skipped 0.51 against free-more-room 0.43, a tie that the
   plan already resolves by trying P1 behind the numeric predicate and falling back
   to P4.

Read as the project memory says to read it: a high noul is a consequence to state,
not an automatic veto; values near 0.5 are undecided; Jev is a second opinion
beside the adversarial reviewer, not a replacement for it.
