# WebKit services: no released items while Safari opens pages

2026-11-16 · branch `wip/webkit-services` · version 1.1.4. Labels: MEASURED, INFERRED, TBD.

## The owner's report (2026-11-16)

On 1.1.3 the hidden items sometimes come back on the bar and are hidden again a little
later, with no action of the owner's. The owner approved the direction below on
2026-11-16 ("我確認可以開始做了"), including that it overturns the 2026-09-25 exclusion
of filtering by bundle id (`2026-09-25-responsiveness-quarantine.md`, section 1).

## Facts (MEASURED 2026-11-16, macOS 27.2.1, the owner's Mac; evidence `~/IceReverse-evidence/20261116-flash/`)

| # | Fact |
|---|---|
| F1 | Each release is a pass `incomplete(1 failed: <pid>)` -> `blocked(discoveryIncomplete)` -> the length is retired (`passes.log`, `stream.log`): 11:15:41-11:16:03 every pass failed on one pid and the items stayed out |
| F2 | The failing pid was a `com.apple.WebKit.WebContent` process 40 s old; the five quarantined pids were WebContent too. Safari starts one per page |
| F3 | `ResponsivenessQuarantine.minimumAge` is 60 s: a younger process that stalls fails every pass until it is old enough to enter. Short releases of about 1 s every ~31 s came from older WebContent processes (`stream.log` 11:14:32, 11:14:33) |
| F4 | `census-before.tsv`: 12 WebKit service processes (WebContent 6, GPU 4, Networking 2), every `AXExtrasMenuBar` answer -25204, child count 0. Old WebContent stall the full 0.25 s; GPU and Networking answer at once |
| F5 | `proc_pidpath` gives `/System/Volumes/Preboot/Cryptexes/OS/...` or `.../Cryptexes/Incoming/OS/...` + `System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/<id>.xpc/Contents/MacOS/<id>` for all 12. `NSRunningApplication.executableURL` is not usable: three different shapes, one relative |
| F6 | `/System/Volumes/Preboot` is not sealed (`mount`), so the path proves nothing alone; the services are signed `Identifier=<id>`, Authority `macOS Software Signing` |

## Design (converged with Codex over three rounds, 2026-11-16)

- D1 `WebKitServiceRule` (IceCore, pure): bundle id exactly one of
  `com.apple.WebKit.WebContent`, `.GPU`, `.Networking`, and the kernel path's components
  exactly a root of F5 + `System/Library/Frameworks/WebKit.framework` + optional
  `Versions/A` + `XPCServices/<id>.xpc/Contents/MacOS/<id>`. No `.`/`..`. The plain
  `/System/...` root is not measured on 27.2.1 and is left out.
- D2 `LiveRunningApps.processes()` leaves out a process that matches D1 **and** satisfies
  `anchor apple and identifier "<id>"`, checked once per process identity (pid + kernel
  start time), the requirement compiled once. Anything unread, gone or failed stays
  enumerated: the quarantine handles it as before.
- D3 Left out means not read and not enumerated, as `.prohibited` processes are.

Not in this plan: the quarantine's rules, other processes' failures, own-read and
blocker releases (they still release, by design).

## Checks

- T1 IceCore: D1 accepts the three ids at both roots, with and without `Versions/A`;
  refuses another id, a mismatched executable, the plain `/System` root, a `/System/Volumes/Data`
  root, `..`, a relative path, `nil`.
- T2 MenuBarDiscovery: the filter leaves out only matches that pass the signature
  check; the check runs once per identity; a failed check keeps the process.
- T3 Build; lab identity copy with Safari opening several new pages: no `incomplete`
  pass caused by a WebKit pid, no WebKit pid among the quarantined or enumerated, pids
  recorded with start time.
- T4 Codex gate on the branch; owner confirmation before release.
