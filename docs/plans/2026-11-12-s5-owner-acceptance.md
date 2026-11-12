# S5: the owner's acceptance, on the owner's own bar

2026-11-12 · final for the owner's confirmation; Codex three rounds (Appendix) · branch `wip/s5-owner-acceptance` (from
`wip/unstable-rest-rebaseline`, `a5630ab` + STATUS). Carries out "S5 Owner acceptance"
of plan `2026-10-07-icebar-preference-hiding`. S4 closed 2026-11-12 on the lowered gate
of plan `2026-11-12-displaced-baseline`, section 3 (run `20261112-100028`: `k8` a
regression pass, the recovery not witnessed live). Labels: MEASURED, INFERRED, TBD.

## Goal and non-goals

Goal: in one short sitting in the owner's account, on the owner's real menu bar, the
owner sees whether this fork keeps a chosen item inside Ice and opens its menu from the
IceBar, and whether the layout pane says so when Ice's icon is left of its divider.
The sitting ends with one of `pass`, `fail`, `notEstablished`, each with its reason.
The release Ice's settings are untouched; what does change on the owner's bar is said
beforehand (D8) and measured afterwards (C8).

Non-goals: installing this build as the owner's daily Ice or replacing
`/Applications/Ice.app` (a later plan, only after a `pass`); the always-hidden section
(T2d open: off); a second display; fixing what the sitting finds; changing `run-lab.sh`,
`Packages/MenuBarCapture` or the frozen detector files; any Swift change.

## 1. What is known, and what is not

| # | Fact | Grade |
|---|---|---|
| F1 | The release Ice and every local build share bundle id `com.jordanbaird.Ice`, the prefs domain and the executable name; Ice writes every setting back at setup | MEASURED 2026-09-24 (memory `release-ice-shares-identity`) |
| F2 | The report mode (`-IceLabReport YES`) runs only under a bundle id starting `com.icespike4.lab.`; it keeps the normal launch path and adds a JSON report on stdout, a 0.5 s snapshot timer and a command reader on stdin: the acceptance is of an instrumented Ice | MEASURED (`LabReportRule.swift:94-118`, `LabReport.swift:9-13, 119-159`) |
| F3 | A lab copy started by path from Terminal ran with Terminal's Accessibility and Screen Recording in `icetest` | MEASURED (`icetest` runs; `run-lab.sh:133-139`). In the owner's account, from the owner's Terminal: TBD (U1) |
| F4 | A status item started after Ice lands leftmost, left of the hidden divider, and becomes a member | MEASURED in the owner's account (L3 of the parent plan), for helpers |
| F5 | In the lab one or two members verified about 300 s after Ice's start; a member added at a verified rest verified again in about 35 s | MEASURED (run `20261111-233109`: `sparse` 299 s, `k2` 297 s, `addremove` 351 to 386 s) |
| F6 | The lab never showed the panel drawing its cells nor a mouse click reaching one; `inverted` after start was never run | MEASURED (parent plan, S4 design; STATUS ledger) |
| F8 | When two helper items appeared on the owner's bar (2026-10-08), MenuBarAgent changed the stored values of 15 of the owner's own entries within 30 s (by -28 to +46 pt); no key was added or removed; nothing changed after the helpers quit. Whether anything visible or lasting followed: unknown. STATUS then said "no further run without the owner's approval" | MEASURED, 1 run (`20261008-081444-y8GnWW-remembered`; STATUS "The owner's own entries changed") |
| F7 | Release Ice is not running in the owner's account now; it is an enabled login item | MEASURED (`pgrep`, 2026-11-12) / memory |

| # | Unknown | How the sitting meets it |
|---|---|---|
| U1 | Whether the owner's Terminal has Accessibility and Screen Recording | the dry run (`icewatch preflight`); without them the script stops and says so; it never opens Ice's Permissions window flow and nobody clicks Grant in it |
| U2 | Where a fresh identity's divider and icon land on the owner's bar (T2a: 6 of 6 on 2026-10-08; the bar has changed since) | clause C1, before anything else is started |
| U3 | Whether the owner's bar has room for one more item, or folds it behind the system's `«` (the lab's `crowded` case) | clause C2; if folded: `notEstablished`, the sitting ends |
| U4 | Whether the owner's own items between divider and icon serve as references, and how long a walk takes on this bar | the report; an unverified rest is reported as such, never as a pass |
| U5 | Whether the panel draws and a click opens the menu | the owner's eyes: this is what S5 is for |

## 2. Design

D1 **Identity: a lab copy, not `com.jordanbaird.Ice`.** The script makes a copy of the
staged, hash-checked `Ice.app` under `com.icespike4.lab.s5r<run id>` with its own
executable name, re-signed ad hoc, exactly as `run-lab.sh` does (`stage_ice`,
`start_ice`), started by path with `-IceLabReport YES`, Sparkle off, `UseIceBar` on,
`ShowOnHover`/`ShowOnScroll` off, always-hidden off. So the release's settings are
never written (F1), the report gives a machine record beside what the owner sees (F2),
and nothing has to be restored but the lab domain, which is deleted. What this does
not show: this build under the real bundle id (the non-goal above).

D2 **Two phases, the first without the owner's items.**
Phase A (unattended, about 6 minutes): Ice starts; one sacrificial helper
(`com.icespike4.target`) starts after it and becomes the only member (F4); the script
waits for `verified`. No item of the owner's is left of the divider (C1), so the spacer
carries only the helper.
Phase B (the owner, about 10 minutes), prompted line by line in the Terminal:
1. Click Ice's icon. Is the helper listed in the IceBar? Click it. Did its menu open?
2. Command-drag one item of your own choice left of Ice's divider. Wait for the
   Terminal to say `verified`. Click Ice's icon: is your item listed? Click it: did its
   menu open?
3. Open Ice's Settings, the layout pane. Command-drag Ice's icon left of its divider:
   does the pane say the icon must be right of the divider? Drag it back: is the line
   gone, and does the Terminal say `verified` again?
4. Command-drag your item back to where it was. Is it back in its place?
5. Press Return. Ice and the helper quit; your items are drawn again.
Each question is answered `y`, `n` or `s` (skip) at the prompt. The script only reads
the report and the answers: it never moves, clicks or presses anything and posts no
event.

D3 **The owner's item is the owner's act.** The project rule "only sacrificial helpers,
never the items on my bar" stands for everything the script and the assistant do. Step
2 is the owner dragging one own item, and while it is a member Ice's spacer keeps it
off the bar: that is the feature under acceptance. Confirming this plan is the owner's
yes to that one step; `s` skips it and the result then says "helper only".
The same yes covers F8: Ice's two items and the helper appearing on the bar will, as
measured once, change values MenuBarAgent stores for the owner's items. A guard that
stops on any such change (as `run-remembered.sh` has) would stop every sitting, so the
script does not stop on it: it keeps the store before, records every changed entry, and
judges what the owner can see, the order of the bar (C8). The store is not ours to
write: if C8 finds the order changed, the recovery is the owner's Command-drag, with
the order before printed item by item.

D4 **Guards, enforced before anything starts** (`--dry-run` runs only these): the
account is `OWNER_USER`; `lab.env`'s hashes of `Ice.app`, the helper, `icewatch`,
`lab-tool.py` and the script hold; Terminal's preflight (U1); no process whose image
is an `Ice.app` or an `IceLab*` executable is running (if the release runs, the script
names it and stops: the owner quits it, the script signals nothing it did not start);
no other display. Before the start it exports `com.jordanbaird.Ice` and MenuBarAgent's
store to the evidence directory.

D5 **Every way out is the same cleanup** (Return, INT, TERM, HUP, a 40-minute
watchdog, a failed clause): stop Ice by the pid it started, image path checked; quit
the helper; delete the lab domain and check it empty; export `com.jordanbaird.Ice`
again and compare with the first export (any difference is a `fail`, and the first
export is the restore file); export the store; print the report.

D6 **Evidence** in `~/IceReverse-evidence/<run id>-s5/` (mode 0700; it holds the
owner's app names, so not `/Users/Shared`, not the repository): the report, Ice's log,
the answers, both exports, the store before and after, `verdict.json`, `report.txt`.

D7 **The verdict** (`lab-tool.py s5 <dir>`, pure, from the report and the answers):

| # | Clause | If not |
|---|---|---|
| C1 | within 120 s of Ice's start, a snapshot that is `complete` with `hiddenBoundaryUsable` true (the divider settled at standard length, so membership has been evaluated against it): `iconPlacement` right of the divider, the roster empty, `cacheHidden` and `cacheAlwaysHidden` holding nothing of the owner's | `notEstablished`; nothing else is started |
| C2 | the first complete snapshot after the helper's start, waited for up to 120 s (the lab's rosters came about 4 s after start, F5's runs; a fuller bar may read slower), has a roster of exactly the helper, ready and pressable | `notEstablished`, with the system's `«` listed or not (`icewatch chevron`) and where the snapshot has the helper (U3) |
| C3 | `verified` with that roster within `HIDE_LIMIT` (1100 s) | `fail`, with the last status |
| C4 | answers 1: listed `y`, menu `y`; the report shows the bar presented with exactly one cell, the helper's, enabled | `fail` |
| C5 | step 2: the roster becomes exactly the helper and one more member, both ready and pressable, no blocker; `verified` with that roster; a presented snapshot with exactly those two cells enabled; both answers `y`. The new member's key and the owner's typed name for the item go into the evidence, so the answer is tied to that member | `fail` (a `blocked(positional` or a stale or stacked member is named: D-a); skipped: recorded, result "helper only" |
| C6 | step 3: a status `blocked(iconLeftOfDivider` with a null length and no IceBar offered, then `verified` again; both answers `y` | `fail`; skipped: recorded |
| C7 | cleanup: Ice gone, lab domain empty, `com.jordanbaird.Ice` unchanged; in MenuBarAgent's settled store no key added or removed but the lab copy's and the helper's | `fail` |
| C8 | step 4 answered `y`, and the order of the owner's items (`cacheAlwaysHidden + cacheHidden + cacheVisible`, each sorted by frame by `DiscoveredCachePlan`; the lab copy's and the helper's entries left out) in the last snapshot before the stop, which must be `complete` and later than step 4's answer (every answer is written as a step with the report's last `seq` and the time, as `run-lab.sh`'s `mark` writes `steps.jsonl`), equals the order in C1's snapshot. The lists carry no frames: that the item is back at its exact place is the owner's answer alone | `changed`: both orders printed; the owner drags; said in the result. No complete snapshot within 60 s of the answer: `notEstablished` for C8, said as such. Changed stored values alone (F8) are recorded with their count, not a failure |

`pass` = C1-C8 with nothing skipped. A rest that stays `notVerified(...)` is a `fail`
of C3 or C5 with that status named: the parent plan's D-c says an unverified hide never
counts in S5. No clause is retried; the sitting is not repeated without a new decision.

D8 **What stays after the sitting** (stated to the owner before the start): the item
dragged in step 2 stays where it was dropped until the owner drags it back
(MenuBarAgent remembers a dragged position; the store cannot be edited by us);
MenuBarAgent keeps the lab copy's and the helper's records (as every lab run), and
may have changed values it stores for the owner's items (F8).

## 3. Tasks (tests first)

| # | What | Tests first | DoD |
|---|---|---|---|
| T1 | `lab-tool.py s5`: the verdict of D7 | unit tests on synthetic reports: each clause holding, failing, skipped; an unverified rest; a report cut short; a positional blocker; a disabled cell; an order changed; a store key added. a C8 end snapshot that is incomplete | lab-tool suite green |
| T2 | `run-s5.sh` beside `run-lab.sh` (its own file: the tested matrix runner is not touched; it copies `stage_ice`, `start_ice`, `stop_ice` and the domain checks, about 80 lines) | `test-s5.sh` with a stub Ice and stub helper, as `test-lab.sh`: the guards one by one; the prompts fed from a file; every way out runs D5; a changed `com.jordanbaird.Ice` export fails | `test-s5.sh` green |
| T3 | `stage-lab.sh` also copies `run-s5.sh` and records its hash | `test-lab.sh`'s staging case | green |
| T4 | `/simcodex`; stage; `run-s5.sh --dry-run` in the owner's Terminal (U1) | | dry run passes or names what is missing |
| T5 | The sitting: the owner starts `run-s5.sh` at a time of the owner's choosing | | a verdict in STATUS, MEASURED, with what was skipped |

Serial: T2 reads T1's verdict format, T3 and T4 need T2; nothing is dispatched.

## 3a. As built (2026-11-12; where the code differs from the text above)

- The judge is its own file, `s5-tool.py`, which loads `lab-tool.py` for the report's
  reading and damage rules: `lab-tool.py` is at 1076 lines already. Its hashes are in
  their own `s5.env`: `run-lab.sh` refuses a `lab.env` line it does not know.
- A fourth result, `partial`: every judged clause holds and a step was skipped or C8
  could not be read. D7's "result helper only" is a `partial` with that note.
- C8's end snapshot must be of a discovery pass begun after the last answer (two passes
  later than the one the report had then; a pass is about 5 s): a snapshot written
  right after the drag back still holds the lists of the pass before it.
- Each answer and the helper's start are recorded with the report cut the next wait
  counts from, so the runner and the judge cannot disagree on "after".
- One more guard: one display. The staged files' ownership and write checks of
  `run-lab.sh` do not apply (the owner owns them); the hashes do.
- The prompts and the result line are in Chinese, for the owner; reasons stay as the
  report words them.

- A wait of the runner's that ran out is a step (`timedOut`, with its clause): the judge
  fails the clause on it and does not look for a later `verified`. The runner's budgets
  (`limit`) and the member it saw (`ownSeen`) are on its steps too.
- C8 is judged whenever Ice ran, from the runner's `lastLook` step: also when the
  sitting ended at C1, C2 or C3.
- The staging must be the owner's own, no link, not writable by others (review: the
  sha256 live beside what they check, so they catch a stale staging, not another
  account's); the evidence root likewise.

Review of the code (2026-11-12, cap two rounds): round 1, four quality reviewers, a
security reviewer and Codex: no P0, no CRITICAL or HIGH; 8 P1 or MEDIUM taken (the three
above, one writer for steps, the cells check, a unit-tested `wait`, the helper's KILL,
no bytecode cache). Round 2, one reviewer and Codex: 3 P1 taken (C5's blocker bounded
by the owner's answer, C8 on early ends, the cool-down counted from the last probe
capture) and C6's retired length. Left, P2: the store's own keys are decided by the
runner; `timedOut` names the status at the cut, not since the wait began; no runner
test drives a C5 or C6 timeout (the judge's unit tests do); about 15 s of the test
suite is waits that end by timeout.

## 3b. Amended after the first sitting (2026-11-12, the owner's yes the same day)

Run `20261112-120353` failed at C3 after 19 minutes: on the owner's bar no rest can be
`verified`. The bar overflows at rest (10 status items, 8 on the bar, the system's `«`
listed with no Ice running), and the detector's baseline gives no template while a fold
is present (`StripAssessor.swift:124-130`, frozen): STATUS, "S5, the owner's sitting".
D7's rule "an unverified hide never counts in S5" made `verified` a condition of
looking, against the product's own state model (the parent plan's O1 and D-c: unverified,
the length is applied and the IceBar offered). Debated with Codex (one round, agreed):

- **C3 is now**: within `REST_LIMIT` (420 s) Ice rests with the length applied and the
  IceBar offered for `REST_SECONDS` (15 s) without a break, the helper its one member,
  ready and pressable, its one cell enabled; and the owner does not say the helper is
  still on the bar (a new first question). Verified or not: the verdict carries
  `verified` and, when not, the note "hidden, not verified" with Ice's status.
  15 s because Ice's first three rests on that bar lasted 1 to 3 s (40, 89, 137 s: its
  baseline retries) and the fourth stayed (from 187 s); replayed over that report the
  rule holds at 203 s.
- C5 and C6 wait for the same kind of rest, not for `verified`.
- A `pass` now means: usable by the owner's eyes, on a bar where Ice cannot vouch for
  the hide. It is not the lab's `verified`, and STATUS must say which it was.
- If the panel does not list the helper or the click does not open its menu, the
  project stops there (the owner's decision, 2026-11-12).
- Not done: lifting the fold rule in the frozen detector (large, uncertain); raising
  `CheckPlan`'s two-candidate cap (not the cause: Codex, same day).

## 4. Risks and rollback

- Ice misbehaves with the owner's item hidden: Return or Control-C ends it; with Ice
  gone its divider is gone and every item is drawn again (the spacer is Ice's own item).
- The script dies without cleanup (power, `kill -9`): the lab copy keeps running until
  quit from its own menu; `com.jordanbaird.Ice` was never written (D1).
- A fresh identity places its divider among the owner's items (U2): C1 stops the
  sitting before the helper starts; the only length ever applied is standard.
- Rollback of the code: three files under `docs/macos-27/probes/visibility/`; no Swift.

## Appendix: the argument with Codex

Cap set before round 1: three rounds.

| Round | Point | Outcome |
|---|---|---|
| 1 | P0: the store change on the owner's bar (F8) was neither a stop nor a failure | Codex's fact, taken (F8, D3, C7, C8). Its remedy, stop on any unrelated change, refused: F8 was 1 of 1, so that guard stops every sitting; the order of the bar is judged instead and the store diff recorded |
| 1 | P0: C2's 30 s is unsupported | modified: not unsupported (the lab's rosters came at about 4 s) but the owner's bar is fuller; the first complete snapshot, up to 120 s, classified with `«` |
| 1 | P1: "the Mac as it was" against D8 | Codex's; taken (goal, step 4, C8) |
| 1 | P1: C5 did not hold D-a's conditions nor tie the answer to the member | Codex's; taken (C5) |
| 2 | The stop-on-any-store-change guard | Codex conceded: no evidence that value-only changes are visible or lasting; C8 is the observable, over the three cache lists joined, which are sorted by frame |
| 2 | C2's wait | Codex conceded |
| 2 | Is the helper-first phase worth about 6 minutes | Codex: yes; the panel and click path were never witnessed (F6), so not on the owner's item first. Kept |
| 2 | P1: C8's end snapshot may be incomplete and hold an older cache | Codex's; taken (C8) |
| 2 | P1: C1 had no deadline | Codex's; taken (C1, 120 s) |
| 3 | P1: C1 could pass before membership is trustworthy | Codex's; taken (C1: `hiddenBoundaryUsable`, the hidden caches empty of the owner's items) |
| 3 | P1: no marker ties an answer to the report | Codex's; taken (answers as steps with `seq`, the runner's existing `mark`) |
| 1 | P2: F2 "changes nothing else" too strong | Codex's; taken (F2) |

Trend: 5 findings (2 P0), then 2 (P1), then 2 (P1); no P0 since round 1. Round 3 ended
"not converged" on its two points; both were taken as written, nothing is in dispute,
and the cap of three rounds was kept: no fourth call.
