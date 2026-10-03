# Route C, measurement part 4: the first live sitting (S0 -> S-adv -> S1)

2026-10-03 · branch `wip/icebar-runner` (HEAD `a2aeee9`, not re-cut from main) · final (Codex round 2, cap two) ·
runs the instrument of `2026-10-03-icebar-c-runner.md` (section 3 Q1-Q22, section 9
rows 1-15) and `2026-10-03-icebar-c-d52-closing.md` under the pre-registration
`2026-09-30-icebar-c-prereg.md`, sha256
`0780e997b7b5ed5eae6ea69f5df451413c99d48ec5e51a94c3e7617edb8e5420` (v3 + deviations 1-5
+ both pre-S0 addenda), manifest v2 `2026-10-03-icebar-c-pre-s0-manifest-v2.json`
(`18187e2c9f217497ad4e12ccf10a9c04747fa84a7ff5d3ba555149580b8955c5`, revision `d8e05a5`).

Labels: MEASURED (command, file:line or run id) or INFERRED (reasoning).

## 1. Goal, non-goals, constraints

Goal: stage the frozen instrument for `icetest`, check it without launching anything,
stop for the owner's time, and after the owner's sitting copy, verify and read the
evidence exactly as registered, then record it.

Not in this part: any live run before the owner says "開始" (S0, S-adv, S1 run only in
the owner's sitting, started by the owner); any probe that injects events or creates a
status item outside that sitting; S2-S5; Ice's own IceBar; push or merge; any re-run,
parameter change or new reading after a result (the owner decides re-runs).

No code changes in this part. Every source listed by manifest v2 (173) stays
byte-equal (staging refuses otherwise; a change would need a third addendum and the
owner). `Packages/MenuBarCapture` and the ten detector files byte-equal to `af4baf1`,
`Packages/` to `32d523a`; `Sources/VZGlyphs`, `Sources/IceBarCorpus` frozen by corpus 3.
The pre-registration is not edited; anything that would need it goes to its section 9 as
a deviation and stops for the owner. Build scratch outside `~/Documents`
(`/private/tmp/claude-501/visibility-live`, `stage-icebar.sh`'s default). Images only
under `~/IceReverse-evidence/<run id>/`. Helpers only `com.icespike4.target` /
`com.icespike4.protected`, only inside the sitting in `icetest`. The release Ice in
`/Applications` is not launched by any step here (`icebar-dry` and staging launch
nothing), so no preference export/restore is needed; if that changes, export before and
restore after.

Settled and not reopened: C2 PROVISIONAL FAIL; O1-O4; F1-F4; route C appendix A;
pre-registration r1-r3, deviations 1-5, both addenda; K1; corpus 3's 0/5749 (not
re-checked); part 2's R1-R19 (R15 included); part 3's section 3 readings and its two
Codex rulings; `icebarfreeze verify` compares sources only; the deferred P2 and
security LOW items of runner plan section 9 row 9 and closing plan section 7.

Phase 3 (/simcodex) has no code diff to review in this part; the documents written
(this plan, the result rows) are reviewed by Codex in Phase 1 (this plan) and checked
against the evidence by the reader in T9.

## 2. Tasks

| # | task | DoD |
|---|---|---|
| T1 | this plan; Codex review, round cap two (+ thecure on any point still open) | review record in the appendix; plan final |
| T2 | pre-staging checks (section 3, rows P1-P8) | every row's command output recorded in section 7 row 1 |
| T3 | `docs/macos-27/probes/visibility/stage-icebar.sh icetest` in the owner's account (verify -> `build.sh` with U24 first -> K1 sha256 -> copy to `/Users/Shared/IceReverse-icebar`) | exit 0; the staged tools' sha256 and `icebar.env` recorded |
| T4 | `icebar-dry` on the staged copy: `ICEBAR_K_DIR=/Users/Shared/IceReverse-icebar/k /Users/Shared/IceReverse-icebar/apps/vizprobe icebar-dry --apps /Users/Shared/IceReverse-icebar/apps` | exit 0; 19 templates + K1 chevron; start-up check `ready` at scale 2; three rosters printed; no `PROBLEM` line; no `vzhelper` process before or after (`ps -axo user,pid,comm`). `icebar-dry` exits 0 whatever the start-up check prints (MEASURED `IceBarRun.swift`, `IceBarDryCommand`), so any value other than `ready` at scale 2 is a stop here even with exit 0 |
| T5 | post-staging checks (section 3, rows P9-P11); **stop for the owner** with section 4's checklist | report to the owner; nothing runs until the owner names the time |
| T6 | (owner) the sitting in `icetest`, section 4 | the owner reports the final `結果：…` line, or that none appeared |
| T7 | evidence copy and verification (section 6) | every `manifest.final.json` and `runner.final.json` re-verified on the copy |
| T8 | post-sitting checks (section 6, rows V5-V7): desktop picture restored, no `vzhelper`, helper domains empty | each row's evidence recorded |
| T9 | reading (section 5) and recording: `docs/macos-27/STATUS.md` (MEASURED, build `26A434`, date) and runner plan section 9 (row 16) | rows written; then **stop for the owner** whatever the result |

Parallel candidates: none (a chain gated by the owner).

## 3. Checks before and after staging (the owner's account; nothing launched)

| # | check | command | expected |
|---|---|---|---|
| P1 | branch and revision | `git rev-parse --abbrev-ref HEAD`; `git rev-parse HEAD` | `wip/icebar-runner`; `a2aeee9…` (or a later commit that touches no manifest-listed source, e.g. this plan) |
| P2 | tracked tree clean | `git status --porcelain --untracked-files=no` | empty |
| P3 | pre-registration | `shasum -a 256 docs/plans/2026-09-30-icebar-c-prereg.md` | `0780e997…5420` |
| P4 | manifest v2 itself | `shasum -a 256 docs/plans/2026-10-03-icebar-c-pre-s0-manifest-v2.json` | `18187e2c…55c5` |
| P5 | A3 (detector, MenuBarCapture) | `docs/plans/checks/check-a3a4.sh` | exit 0 |
| P6 | A4 | `git diff --exit-code 32d523a -- Packages` | exit 0 |
| P7 | corpus-3 sources | `git diff --exit-code 6ab69ce -- docs/macos-27/probes/visibility/Sources/VZGlyphs docs/macos-27/probes/visibility/Sources/IceBarCorpus` | exit 0 |
| P8 | E1 OS build; no helper running; owner's helper domains | `sw_vers`; `ps -axo user,pid,comm \| grep vzhelper`; `defaults read com.icespike4.target`, `…protected` | 27.0.1 `26A434` (a different build is recorded, not a stop); no process; both "does not exist" |
| P9 | staged layout | `ls -la /Users/Shared/IceReverse-icebar /Users/Shared/IceReverse-icebar/evidence`; `shasum -a 256` of `apps/vizprobe`, each `apps/*.app/Contents/MacOS/vzhelper`, `k/*`, `run-icebar.sh` | owned by the owner, not symlinks; `evidence` mode 0777 and empty; K1 `a3bcce60…39e6`; `run-icebar.sh` byte-equal to the repository's |
| P10 | `icebar.env` | `cat /Users/Shared/IceReverse-icebar/icebar.env` | `EXPECT_USER=icetest`, `OWNER_USER=<owner>`, `EXPECT_GEOMETRY` from the owner's own build, `ICEBAR_K_DIR` |
| P11 | still nothing launched | P8's process and domain checks again | as P8 |

A failure of P1-P7 or of T3/T4 stops the part before the owner is asked for a time and
is reported as it is; no source is changed to make it pass.

## 4. The owner's steps (only after T5's report, at the time the owner names)

Before the time (once, in `icetest`; the same settings C2 used, re-checked):

1. Log into `icetest` (fast user switching; your own session stays as it is).
2. Check: screen saver and screen lock off; menu bar auto-hide as in your own account;
   Terminal has Accessibility and Screen Recording (System Settings > Privacy & Security);
   the bar shows only system items.
3. E3: the desktop picture is a **static** picture (not dynamic, not time-of-day, not
   rotating). D5.2 replaces it between S-adv variants with two staged solid images and
   restores it before S1 and at the end; the closing plan's deferred note says a dynamic
   picture would come back as a static file.
4. No other app window near the top of the screen (E4); the Mac on power (the sitting
   holds a `caffeinate -d -i`, about 4-5 h, INFERRED K5).

At the time:

5. In `icetest`, open Terminal and run exactly:
   `/Users/Shared/IceReverse-icebar/run-icebar.sh`
6. Leave the Mac unlocked and untouched; do not switch accounts until the last line
   `結果：…｜…｜…` appears (switching away ends the sitting `中斷`; that is recorded, not
   repaired).
7. When the last line is there, before switching away, in the same Terminal run
   `defaults read com.icespike4.target; defaults read com.icespike4.protected`
   (expected: empty, `{}` or "does not exist", twice; required) and glance that the desktop picture is
   the original; then switch back to your own account and tell Claude the final line
   and the two `defaults` results. A domain that is not empty is reported as it is;
   Claude then gives the one `defaults delete` command for that helper domain only,
   and you decide whether to run it.

If something goes wrong while you are there: Ctrl-C once in that Terminal ends the
sitting on its normal path for the picture (restored; D5.2 B2), but it is **not** a
clean step teardown: the step child gets the same SIGINT, asks its helpers to quit
without waiting and finishes its report at once, so its domain-clearing teardown does
not run (MEASURED `IceBarRun.swift` `StepFinisher.stop`; helpers exit on their own when
the step process does, `LaunchedHelpers`). After a Ctrl-C, step 7's `defaults` check is
what shows the domains' state. Never `kill -9`: SIGKILL cannot restore the picture (the
first record of `runner.jsonl` holds the original's path and sha256).

## 5. Reading (as registered; no new reading)

Sources, in order: the owner's final line; `runner.final.json` (`result`) and
`runner.jsonl`; each step directory's `result.json` (`StepReport`), trusted only
through its verified `manifest.final.json` (as `IceBarSitting.readReport`), and its
`samples.jsonl` records (`LiveEvidence.record`: `placement`, `sample`, `baseline`,
`attempt`, `attempt.judged`, `observation`, `cycle`, `sAdv.step`, `teardown`, `step`,
`step.result`). Runner Q22 names `cycles.jsonl`; the frozen runner writes these records
into `samples.jsonl` instead (MEASURED `Sources/vizprobe/LiveEvidence.swift:52`), which
is where they are read.

| # | item | how it is read | registered at |
|---|---|---|---|
| R1 | 7a result line | the line printed in `icetest`'s Terminal, as the owner reports it, is the registered output (it is not written to any evidence file). `runner.final.json` `result` holds the same `SittingResult` as one interpolated string (e.g. `completed("S1 capacity 4")`, MEASURED `IceBarRun.swift` `writeFinal(["result": "\(result)"])`), quoted verbatim as corroboration; no separate reason field is derived from it. If the owner has no line, the 7a word is read from that string's case by `ProgressLine.final`'s own mapping (`completed` 完成, `failed` 失敗, `interrupted` 中斷, `safetyStop` 安全停止) and stated as such | route C 7a; runner Q20; `ProgressLine.final` |
| R2 | S0 outcome | step 001's `s0.outcome`: `pass` (5/5 not granted, members drawn at every restore control, final control after Menus quits) / `noGo` (granted once: `失敗`) / `notShown` / `incomplete` | route C S0; Q15; `Sitting.afterS0` |
| R3 | C3 | `s0.c3`: `holds` / `notListed(id)` / `mismatch(id)` (any helper unlisted in any capture, or a visible helper's x, y, w, h off its AX frame by > 1 pt), with the first offending helper id as the outcome names it. The per-capture window bounds are not written to the evidence by the frozen runner (only each `sample` record's `overlap`), so no per-capture delta table is reported | deviation 2 C3; Q12-Q13 |
| R4 | section 8 | `s0.section8`: `consistent` / `contradiction(names)` / `unmeasured(names)`; and from every S0 `baseline` record's `measurements` in `samples.jsonl`: max kept distance vs `T_agree`, largest row cluster vs 16 and max row deviation vs `T_bg`, C_r vs 129, texture max vs 12, plus the count of baselines that reached the pixel clauses and the refusal reasons of the others. K1: `unmeasured` stops the sitting (`中斷`) and the owner decides | prereg section 8; Q16; K1 |
| R5 | S-adv | per variant (dark/light x ordinary/coloured): sweeps run, each sweep's `RepeatResult`, the upward endpoint length, re-runs; the `«` rest state's episodes. Outcome by `Repeats.judge` as `SAdvSequencer` applied it (from the step order in `runner.jsonl` and each report's `sweep`). Each step's named appearance (E5) and the picture set before it (`runner.jsonl` `desktopPicture` events) | route C S-adv; Q17-Q18; deviation 5 D5.2 |
| R6 | BControl (C5) | the sitting's own gate: S1 started iff `BControl.evaluate` was `.valid` (`Sitting.afterSAdv`); otherwise the reason line names `mismatch at capture i` / `insufficientCaptures(n)` / `insufficientEpisodes(n)`. Reported with the counts of (a)-captures and episodes summed from the S0 and S-adv reports' `chevronObservations` (a tally, not a re-judgement) | deviation 2 C5; deviation 5 D5.1; Q14 |
| R7 | S1 capacity | the final line's reason (R1; corroborated by the `runner.final.json` string) `S1 capacity k` / `S1 capacity k, below 4; …` / `S1 NO-GO: …`; per profile (k, menu): band, midpoint L, the 5 cycles' numerator by cause, pass/fail/repeat-inconclusive, replications, k = 3 confirmation | route C S1; prereg section 4; Q9, Q19 |
| R8 | not reached | every stage after the one that ended the sitting is written "not run (the sitting ended at …)"; never inferred | route C section 4 order |

A NO-GO, failure, interruption or safety stop is recorded as it is and the part stops for
the owner (no re-run, no tuning, no other reading). A reading that the evidence does not
support (a field missing, a report that does not verify) is written as such ("not
readable: …"), not filled in.

## 6. Evidence transfer and post-sitting checks

| # | step | how | expected |
|---|---|---|---|
| V1 | locate | `ls /Users/Shared/IceReverse-icebar/evidence` | exactly one new `<yyyyMMdd-HHmmss>-icebar` directory; its name is the run id |
| V2 | copy | `ditto /Users/Shared/IceReverse-icebar/evidence/<run id> ~/IceReverse-evidence/<run id>` | a byte copy; the shared copy is left in place (deleting it needs the owner's word) |
| V3 | verify the copy | a reader in the session scratchpad (not in the repository): for `runner.final.json` and every step's `manifest.final.json`, re-hash every file of that directory except the manifest itself and compare both ways with its `files` map (as `C2Manifest.verify`); also `diff -r` against the shared copy | every directory verifies; a missing or mismatched one is reported by name and that directory's reading is "not readable" |
| V4 | first record | `runner.jsonl` first records: `desktopPicture.original` (path, sha256) | present |
| V5 | picture restored | `runner.jsonl`: if any `desktopPicture` event names a staged appearance (`dark`/`light`), the last `desktopPicture` event must be `appearance: original` after it, with no `desktopPicture.failed` after it; if none does (the sitting ended before the first S-adv change), the record is "no picture change requested" (the frozen code emits no restore event then). Plus the owner's glance (section 4 step 7) | restored or never changed; else the original's path from V4 is given to the owner |
| V6 | no helper left | `ps -axo user,pid,comm \| grep vzhelper` (every user's processes) | none |
| V7 | helper domains empty | each step's `teardown` record (`problems` empty; a step ended by a signal or the watchdog has none, and that is stated), the owner's required `defaults read` in `icetest` (section 4 step 7), and P8's check again in the owner's account | empty everywhere; a non-empty `icetest` domain is reported and its delete is the owner's decision |
| V8 | no image in the repository | `git status --porcelain` | no image |

## 7. Records

| # | date | record |
|---|---|---|
| 1 | 2026-10-03 | T2-T5, MEASURED in the owner's account, 09:4x. P1 `wip/icebar-runner` `a2aeee97c4f6…`; P2 clean (tracked); P3 `0780e997…5420`; P4 `18187e2c…55c5`; P5-P7 exit 0; P8 macOS 27.0.1 `26A434`, no `vzhelper`, both owner helper domains `{}` (empty; the plan's "does not exist" widened to "empty" before staging, a wording fix). T3 `stage-icebar.sh icetest` exit 0 (`icebarfreeze verify` passed, `build.sh` with U24, K1 checked): staged in `/Users/Shared/IceReverse-icebar`, geometry `1728x32:771.5-956.5`. T4 `icebar-dry` exit 0: 19 glyphs + chevron 29x27 (K1 sha256 as pre-registered), start-up check `ready` at scale 2.0, S0 / S-adv / S1-k16 rosters printed (S0: 3 visible + hidden2, hidden3; S-adv: 3 visible + 4 coloured members; k16: 3 visible + 16 members, all members `com.icespike4.target`, visible `com.icespike4.protected`), no `PROBLEM`; no `vzhelper` before or after. P9 every staged path owned by the owner, no symlink, `evidence` 0777 and empty; sha256 `apps/vizprobe` `4507d027…0657`, K1 `a3bcce60…39e6`, `run-icebar.sh` `17970cce…dea40` byte-equal to the repository's; each `.app`'s `vzhelper` hash differs from the others (ad-hoc codesign per bundle, as `build.sh` signs each app). P10 `EXPECT_USER=icetest`, `OWNER_USER=ibridgezhao`, `EXPECT_GEOMETRY=1728x32:771.5-956.5`, `ICEBAR_K_DIR=/Users/Shared/IceReverse-icebar/k`. P11 as P8. **Stopped for the owner** |
| 2 | 2026-10-03 | The owner said "開始" at 13:47:59 JST ("那我就現在過去那邊開始了"): the sitting is started by the owner in `icetest`. At that moment `/Users/Shared/IceReverse-icebar/evidence` was empty and no `vzhelper` or `vizprobe` process ran (MEASURED, owner account) |
| 3 | 2026-10-03 | T6-T9. Owner's photo of the Terminal (kept as `~/IceReverse-evidence/20261003-134859-icebar-owner/terminal-photo.png`): `步驟 1 S0 開始 [13:48:59]`, `步驟 1 S0 結束：completed [13:50:54]`, `結果：失敗｜S0 not shown: a cycle inconclusive three times｜/Users/Shared/IceReverse-icebar/evidence/20261003-134859-icebar`. V1 one directory; V2 `ditto` + `diff -r` identical; V3 `001-S0/manifest.final.json` (263 files) and `runner.final.json` (265) verify both ways; V4 `desktopPicture.original` present. R1 失敗 as above; R2 `notShown(a cycle inconclusive three times)`; R3 `notListed(reference)`; R4 `unmeasured(kept distance, row spread, texture, C_r)`, 3 baselines all refused `foldNotAbsent(unreadable)`, none reached the pixel clauses; R5-R7 not run (the sitting ended at S0); R6 tally: 260 `chevronObservations` in S0's report, not judged (S-adv not reached). V5 no picture change requested; V6 no `vzhelper`; V7 S0 `teardown` `problems` empty, owner-account domains `{}`, `icetest` `defaults` result **pending from the owner**; V8 no image in the repository. Details in runner plan section 9 row 16. **Stopped for the owner** |
| 4 | 2026-10-03 | Cause of S0's inconclusive captures, owner's question "A or B" (A: macOS 27 gives a status item no window of its own; B: the runner selects windows wrongly). Read-only window list in the owner's account, nothing launched (`~/IceReverse-evidence/20261003-135901-winlist-readonly`, 26A434): 182 windows, 2 at `kCGStatusWindowLevel` (25), neither at the top of the screen; **0** windows shaped like a status item (y < 40, height 10-40, width <= 200) at any layer, with the owner's third-party items on the bar. Same as 2026-09-19 on 26A428 (FINDINGS "there are no per-item windows left at all"). So **A**, MEASURED for the owner's items on this build; for the route C helpers INFERRED (ordinary `NSStatusItem` apps, and S0's every capture `missing("reference")` agrees). Not B: no selection rule over this list could find a window that is not listed (`StatusWindows` filters pid and layer 25; dropping the layer filter would still find nothing bar-shaped). This is the runner plan's risk K4, anticipated at deviation 2 C3; as registered, C3 cannot hold on macOS 27 and any change is a deviation for the owner |
| 5 | 2026-10-03 | Deviation 6 drafted and debated with Codex (three rounds, thecure); **withdrawn**: AX frames cannot replace C3, and an offline sweep MEASURED the oracle's occlusion blind spot (10.5 % of pairwise overlap composites). Converged: route C cannot proceed on macOS 27 under the registered design; the run stays a provisional S0 failure, replication not run; halt or a new study is the owner's decision (`2026-10-03-icebar-c-deviation6.md`) |

## 8. Acceptance

| # | check |
|---|---|
| AC1 | P1-P11 as expected; T3 and T4 exit 0; no helper launched before the owner's sitting |
| AC2 | the evidence copy verifies (V3) |
| AC3 | R1-R8 written in `docs/macos-27/STATUS.md` (each MEASURED with the run id, build `26A434` or the one recorded, date) and runner plan section 9 row 16, each traceable to a file of the run |
| AC4 | V5-V8 hold, or each failure stated |
| AC5 | the pre-registration still `0780e997…`; manifest-listed sources unchanged (`icebarfreeze verify` exit 0 after the sitting) |

## 9. Risks

- K1 (INFERRED, likely): S0's baselines stop at the fold, section 8 `unmeasured`, the
  sitting ends `中斷` after S0. Recorded; the owner decides.
- K4/K4b (INFERRED): status windows unlisted or off-screen on 27 -> C3 `notListed` /
  `mismatch`, `中斷` after S0.
- R1 of the closing plan: the solid picture may not move the bar's luma into E5's range;
  S-adv steps inconclusive, re-runs, possibly `not shown`.
- The live `NSWorkspace` desktop-picture calls and the parent's signal path run for the
  first time in this sitting (closing plan R2).
- K5: S1 up to k = 16 may take about 5 h; per-step watchdogs only.
- The owner's session left (account switch, sleep): `中斷`, recorded.
- Rollback: this part changes no code; staging overwrites only
  `/Users/Shared/IceReverse-icebar/apps`, never evidence.

## Appendix. Review record

Round cap set before round 1: two.

### Round 1 (Codex gpt-5.6-terra): 2 P1, 1 P2

| finding | ruling | change |
|---|---|---|
| P1 V5 demands a restore event that the frozen code never emits when no picture was changed | accepted | V5 conditional on a staged-picture event; otherwise "no picture change requested" |
| P1 R1/R7 read `runner.final.json` as separate result and reason fields; it holds one interpolated `SittingResult` string | accepted | the Terminal line (owner-reported) is the registered output; the JSON string is quoted verbatim as corroboration; fallback mapping only via `ProgressLine.final` |
| P2 `icebar-dry` exits 0 even when the start-up check is not `ready` | accepted | T4 states it: anything but `ready` at scale 2 stops the part |

### Round 2: 1 P1 -- accepted, modified; cap reached, plan final

| finding | ruling | change |
|---|---|---|
| P1 Ctrl-C ends the step without its teardown (no domain clearing, helpers not reaped), yet the plan called it a safe exit and the `defaults` check optional | accepted, modified (the code is frozen: the signal path is not changed) | section 4: Ctrl-C described as restoring the picture but skipping the step teardown; step 7's `defaults` check required after every sitting; V7 states a signalled step has no `teardown` record; a non-empty domain's delete is the owner's decision |

Codex confirmed round 1's three changes close their findings. Trend: 2 P1 + 1 P2 -> 1 P1
(closed by specification).
