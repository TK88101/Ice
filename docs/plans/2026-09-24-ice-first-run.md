# Plan — the first run of Ice on macOS 27 (observation protocol)

Status: **v3** — v1 reviewed by Codex (17 findings) and three Opus reviewers
(41 findings), v2 by Codex again (4 withdrawn, 1 re-raised and won, 3 new);
rulings in Appendix A, Jev in Appendix B. Approved by the user; **run on
2026-09-25** (evidence `~/IceReverse-evidence/20260925-092244-icerun`; results in
FINDINGS "Ice itself on the user's bar"; Deviations 9–11).
**Nothing in this plan runs Ice before the user approves it in so many
words**, and the launch itself (step 7) waits for a second, live "go".

Follows `2026-09-23-ax-discovery.md` (v5.2, merged into `main` at `2e0c553`).
Every "what Ice on 27 will do" in that plan is INFERRED; this plan turns the
ones that matter into measurements.

Recon behind the claims: workflow `wf_dbccfcdf-933` (six readers, a critic,
eight gap readers); reviews `wf_24f6405b-08e` and Codex (session record).
Basis tags: **MEASURED** (recorded evidence), **READ** (code), **INFERRED**
(reasoning, stated).

---

## 0. What this plan starts from

### 0.1 What Ice does from launch, with the user's stored settings

| # | fact | basis | anchor |
|---|---|---|---|
| F1 | Accessibility is the only required permission. With it, setup starts at once with no human step. Without it Ice opens its Permissions window, creates no status item, and prompts only if **Grant** is clicked | READ | `AppDelegate.swift:42-52`, `AppState.swift:65-107`, `Permission.swift:83-88,121-160` |
| F2 | Setup order: settings (write-back) → the three control items → `await` MenuBarItemService XPC `start()` → appearance → `HIDEventManager` (event monitors) → `await` the first discovery pass → `HidingVerifier` (27) → image cache → **Sparkle** → notifications | READ | `AppState.swift:65-86` |
| F3 | The hidden divider is created at length 0 and set to **10 000 pt one main-queue turn later**, before discovery, whatever the settings. The always-hidden item is created visible (its `Visible` key is absent) and removed in the same drain (section disabled) | READ | `ControlItem.swift:54-57,69,121,193-198,302-317,398-402,419-421,647-674` |
| F4 | `UseIceBar = 1` (stored): no click, scroll or hotkey collapses a divider; only a ⌘-drag in the bar does. So **no D10 split and no verifier job** in the user's configuration | READ | `MenuBarSection.swift:164-205,211-229`, `HIDEventManager.swift:311-327`, `VerificationTrigger.swift:49-74` |
| F5 | Every settings key is written back to `com.jordanbaird.Ice` at setup (value-identical for keys that exist); a launch-argument override of an Ice setting is therefore persisted too; Ice's typed `as? Bool` ignores `-Key NO` | READ / INFERRED | `GeneralSettings.swift:86-218`, `AdvancedSettings.swift:53-121`, `Defaults.swift:123-135` |
| F6 | All six `hasMigrated*` flags are true: no migration writes | MEASURED | the stored plist |
| F7 | Sparkle starts unconditionally (`#if DEBUG` guards only the manual check). `SULastCheckTime` is > 24 h old, so it would fetch the appcast at once, rewrite `SULastCheckTime` in the shared domain and ask for notification authorization. It reads `-SUEnableAutomaticChecks NO -SUAutomaticallyUpdate NO` through `boolForKey:` and then schedules nothing and writes nothing | READ / MEASURED | `Updates.swift:22-26,56-60,91-96`; Sparkle 2.8.0 `SUHost.m:52-68`, `SPUUpdater.m:396-417` |
| F8 | All five stored hotkey bindings are `null`: no system-wide key combination is registered | MEASURED | the stored plist; `Hotkey.swift:37-52` |
| F9 | `HIDEventManager` is **not** inert on 27 (the ax-discovery plan says it is). Its "is the click on an item?" test uses the per-item window list, empty on 27. INFERRED: with `ShowOnClick` a left click on **any of the user's own items** toggles Ice's hidden section; a plain left click on Ice's icon may toggle twice and cancel itself; with `EnableSecondaryContextMenu` a right click also pops Ice's menu; with `ShowAllSectionsOnUserDrag` any ⌘-drag in the bar collapses every divider | READ / INFERRED | `HIDEventManager.swift:47-61,176-209,286-299,311-327,493-528`, `Bridging.swift:410-438` |
| F10 | `MenuBarItemService.Connection.start()` is awaited before discovery; its `sendSync` has no timeout; a successful reply is **not logged** (only failures are); both ends require `.isFromSameTeam()` and this build has no team ID; whether `start()` returns promptly is undocumented | READ / INFERRED | `MenuBarItemServiceConnection.swift:41-57,96-130`, `Listener.swift:28-55`, SDK `session.h:314-353`, `listener.h:238-262` |
| F11 | Ice does nothing on termination (no terminate hook); its status items go when its window-server connection closes. It supports restorable state (`applicationSupportsSecureRestorableState` → `true`) | READ | `AppDelegate.swift:61-75` |
| F12 | Ice writes no files of its own; its log is os_log only (subsystem = bundle id). The notes, heartbeat and per-item check lines are `debug` / `info`: **only a `log stream` started before launch records them** | READ | `Logging.swift:8-21`, `MenuBarItemManager.swift:519-576`, `HidingVerifier.swift:49` |
| F13 | Ice logs `Posting <type> to <location>` (subsystem `com.jordanbaird.Ice`, category `MenuBarItemManager`, debug) just **before** every synthesized event; every posting site is behind the 27 refusal guards | READ | `MenuBarItemManager.swift:2037-2050`, `:749-752,1228-1239,1324-1333,1412-1420,1489-1492,1624-1628` |
| F14 | Surfaces. The **search panel** is the only one that shows item names and sections (no Screen Recording gate; items right to left per section). The layout pane needs Screen Recording; it then shows Loading / "No menu bar items", one row per section ("Unable to display menu bar items" when non-empty) and the status line, whose texts are exactly `Hiding did not take effect for N item(s)` · `Hidden: N[; Not checked: …]` · `Not checked: r1, r2` · `No items to check` (case names only, no counts, not timestamped, kept in memory until the next report) | READ | `MenuBarSearchPanel.swift:197-199,252-270,304-390`, `MenuBarLayoutSettingsPane.swift:12-112`, `HidingVerifier.swift:14-37,110-113,161-206` |
| F15 | The first show after launch has an empty hidden roster (the map is filled only by a pass that starts ≥ 1 s after the collapse; passes are ~5 s apart, plus one when the layout pane opens). A prepare takes 10–15 s, ≤ ≈ 31 s. A hide before it finishes gives `noBaseline` in the **first** cycle; in a **later** cycle the verify reuses the previous cycle's prepared result | INFERRED | `HidingVerifier.swift:119-215`, `MenuBarItemManager.swift:86-109`, `HidingVerification.swift:46-49` |
| F16 | Smart rehide (`RehideStrategy = 0`) hides every section 250 ms after a click into a titled window of an active regular app — Ice's own Settings window included | READ | `HIDEventManager.swift:213-282` |
| F17 | Opening Settings makes Ice a regular (Dock) app until its last window closes while it is frontmost; while Settings is visible Ice captures the bar every 5 s for its average colour (INFERRED that this finds the bar on 27). The search panel does not change the activation policy | READ | `AppDelegate.swift:61-71,80-86`, `AppState.swift:253-265`, `MenuBarManager.swift:139-147,225-260`, `MenuBarSearchPanel.swift:104-139` |
| F18 | A G4 **verdict** needs at least one on-bar, non-positional item with `midX` between the collapsed divider's `minX` and Ice's icon's `midX`; otherwise the check stops at `noReference` before any capture. The stored positions (Hidden 465, Visible 432) differ by exactly the icon's width, so INFERRED: no such item on the user's layout | READ / INFERRED | `CheckPlan.swift:55-86`, `HidingVerification.swift:150-152,288-291` |
| F19 | The Debug build keeps `assert`s; `ControlItem.swift:91` asserts exactly one width constraint (one was found on the `.noDivider` mimic, FINDINGS) | READ / MEASURED | `ControlItem.swift:87-95` |

### 0.2 The machine

| # | fact | basis | anchor |
|---|---|---|---|
| M1 | The release Ice 0.11.13-dev.2 (build 1120, Developer ID) is at `/Applications/Ice.app`, not running, an **enabled login item**, and the one LaunchServices resolves for `com.jordanbaird.Ice`. The local build (1121, ad-hoc linker-signed, no team) has the **same bundle id, prefs domain and log subsystem**; both executables are named `Ice` | MEASURED | `sfltool dumpbtm`; `lsregister -dump`; NSWorkspace query; `codesign -dv` (`flags=0x20002(adhoc,linker-signed)`, `TeamIdentifier=not set`) |
| M2 | Every local build registered with LaunchServices **at build time**; the `/private/tmp` records carry `in-temp-dir` and are never picked for the bundle id. The last build of `main`, `/private/tmp/claude-501/ice-main-build3`, is registered | MEASURED | `lsregister -dump` |
| M3 | Every process exec'd directly from this Bash tool (vizprobe, vzhelper, axcensus; ad-hoc, rebuilt between runs) was trusted for Accessibility and could capture other apps' pixels. INFERRED: the grants are the host terminal's (the responsible process), so a directly exec'd Ice passes F1 with **no TCC row written** | MEASURED / INFERRED | `20260923-{195750,200409,210134}-vzdiscover/samples.jsonl:1,34,42` |
| M4 | No sandbox is configured for the Bash tool (no `sandbox` key in any settings file); its processes have outbound network | MEASURED | `~/.claude/settings*.json`; session `ea447640` line 1286 |
| M5 | Free room right of the notch (771.5–956.5 pt) read 137.5 or 185.5 pt on 09-23 with nothing of ours up; ≈ 25 pt of a reading is not usable before `«` (one 09-18 configuration); the capture indicator (≈ 20 pt, AX width not recorded exactly) costs 41 pt; the microphone pill ≈ 37 pt | MEASURED / INFERRED | `20260923-*-vz*/samples.jsonl:1,5`; FINDINGS "The safe width", "The detector, run against the real bar" |
| M6 | Ice's icon (`Ellipsis`, 17 × 17 pt) takes ≈ 33 pt | INFERRED | `ControlItemImage.swift:32-40`; the stored `IceIcon` |
| M7 | In the Bash tool's zsh, `log` is a **shell builtin**; the unified-log tool must be called as `/usr/bin/log` | MEASURED | `type log` |
| M8 | The Dock's recents are on (`show-recents` absent) and hold file-URL entries; `~/Library/Saved Application State` does not exist today | MEASURED | `defaults read com.apple.dock` (read-only, by a reviewer) |

### 0.3 The 10 000 pt question — what is measured

The start command asks for the risk first: *Ice's idle state expands the
hidden divider to 10 000 pt, and on 27 expanding a spacer folds the user's
items behind `«`.* The evidence is narrower than that sentence:

- **MEASURED, helper spacer settled at 10 000** (5 jumps, one afternoon): no
  `«`, every user item drawn; the item **left** of the spacer drawn 32 pt
  further right. Folding happened only at **intermediate** lengths (20–652
  pt), and 656–836 pt hid an item without `«`. **Ice never assigns a length
  in [16, 852)** (`ControlItem.swift:34-57,421,429`).
- **MEASURED, the release Ice on 27** (same divider code): four runs on this
  machine (09-17 twice, 09-18 for ≈ 1 h 53 min, 09-22 for 5.7 s). One AX
  snapshot 12 min into the 09-18 run shows the expanded divider **parked off
  the bar** (x 7, y 1121.5, w 5002), Ice's icon on the bar at x 1250, and 11
  user items on the bar at x 1077–1708. It ended by SIGTERM with the divider
  expanded; no crash. The three items parked then were parked before and are
  parked without Ice today.
- **Not measured:** the launch transient 0 → 10 000 (a fold shorter than one
  capture gap, 0.17–0.28 s, cannot be excluded by any record); the
  **collapse / expand** (10 000 ↔ 0) with user items beside the divider,
  which the release never did (F4); the bar right after Ice exits; one drain
  with two 10 000 items (F3).

So the **launch** repeats what the release already did four times on this
bar. What is **new** is Phase 3 (the collapse / expand cycles that G3 and G4
need) and the check's captures.

---

## 1. Goal and non-goals

**Goal.** Measure on the user's bar, with Ice built from `main` (`2e0c553`):

- **G1** Loading goes away: setup finishes and the search panel lists items.
- **G2** The list: what Ice lists, against a census taken at the same moment.
- **G3** D10: after the hidden divider has been collapsed ≥ 1 s and a pass
  has computed the boundary, the search panel's Visible / Hidden split
  equals the split computed from that moment's census.
- **G4** The check: the status line and log lines after a show / hide cycle,
  **against an outcome predicted from the census before the cycle**.
- **G5** Nothing of the user's changes: the bar, the user's apps, the release
  Ice's prefs, LaunchServices, BTM, the Dock's recents, saved state.

**Non-goals.** Code changes before the run (section 8); the no-fold band and
composite-window tests; any spacer we expand; any event we synthesize; any
click on the user's own items; TCC changes; the start command's step 4
leftovers; multiple displays; moving Ice's divider to make G4 reach a
verdict (recorded for later as variant (d), Appendix A V1).

---

## 2. What the user will see, and what it costs

- A new ≈ 33 pt icon (Ice's) somewhere in the bar; the harness tells the user
  where (a crop of the strip) before asking for any click.
- For ≤ 1 s at launch, possibly two more items at an unknown width (F3).
- The capture indicator (≈ 20 pt, left of the items) whenever anything
  captures the bar: the harness's strips (few, listed), the check (Phase 3:
  up to ≈ 31 s after a show, ≈ 14 s after a hide), and Ice while its Settings
  window is visible (opened only twice, briefly).
- Phase 3: each show collapses the hidden divider onto the bar (2 pt); each
  hide expands it to 10 000 pt; items beside it may shift ≈ 32 pt.
- A Dock icon while Ice's Settings window is open.
- The user clicks **only** what section 4 lists; everything else of Ice's is
  on a do-not-touch list. Expected duration: Phases 1–2 ≈ 5 min, Phase 3
  ≈ 6 min, plus conversation.

---

## 3. Decisions for the user

| # | question | options | recommended, and why |
|---|---|---|---|
| **U1** | how Ice is launched | **(a)** `icewatch` spawns `Ice.app/Contents/MacOS/Ice` directly, by explicit path · (b) `open <path>` and grant permissions in Ice's window | **(a)**: it inherits the terminal's grants (M3), so no TCC row is written, and the supervisor knows the PID from the first instant. (b) makes Ice its own TCC client under the bundle id the release also uses, so granting would displace the release's rows (INFERRED). If (a) is not trusted after all, Ice shows its Permissions window and nothing else (F1) — a stop, not a risk |
| **U2** | where the run's settings live | **(a)** the shared `com.jordanbaird.Ice` domain: exported before, restored by `icewatch` on every exit path and verified · (b) the build's Info.plist bundle id changed after building (the build is linker-signed with an unbound Info.plist, so the signature stays valid; the XPC service keeps its own id): a fresh domain, deleted afterwards | **(a)**: (b) is a new app identity (its own prefs domain and log subsystem; LaunchServices records it at the next scan), starts from Ice's first-run path (preferred positions 0 / 1, not the user's 465 / 432, so a different layout from the one the user runs), and still needs the run's settings written. (a) keeps the user's layout and icon and is safe **only because** the restore is automatic and session-independent (section 5) and checked first on a sacrificial domain (P3) |
| **U3** | Phase 3 (collapse / expand cycles) | **(a)** on the user's layout, under `icewatch` · (b) skip Phase 3: G1, G2, G5 only | **(a)**: the only option that measures G3 and G4 at all. Its cost is the unmeasured collapse / expand beside user items (0.3): a fold is acted on at its first AX sign (T-fold, section 5), Ice is SIGKILLed within 1 s of a SIGTERM that did not end it, and the bar is watched 30 s after exit. What it cannot catch: a fold or disappearance shorter than one 0.2 s tick, and hiding in the no-fold band, which AX does not show (FINDINGS) |

Fixed without a decision (reasons in section 0): Sparkle off by launch
arguments (F7); `UseIceBar`, `ShowOnClick`, `ShowOnScroll`,
`EnableSecondaryContextMenu`, `ShowAllSectionsOnUserDrag`, `AutoRehide`
false for the run (F4, F9, F16) and restored after; signals only to a PID
whose image path and start time are Ice's (M1).

---

## 4. The protocol

`E = ~/IceReverse-evidence/<yyyyMMdd-HHmmss>-icerun/` (never copied into the
repo; nothing from it pasted into the conversation except counts and
case names). `DD = /private/tmp/claude-501/ice-main-build3` (the registered
build of M2). `APP = $DD/Build/Products/Debug/Ice.app`. All commands run
from the Bash tool as configured (no sandbox, M4); the manifest records it.

### Pre-run (no Ice; part of this plan's approval)

- **P1 Build.** On `main` at `2e0c553`: the iCloud duplicate check of the
  project memory (none allowed); `xcodebuild -project Ice.xcodeproj -scheme
  Ice -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath $DD
  build` into the **existing** derived data, so no new LaunchServices record
  appears (the build re-registers the same path) → `** BUILD SUCCEEDED **`;
  `codesign -dv` of Ice and `MenuBarItemService.xpc`: `adhoc,linker-signed`,
  `TeamIdentifier=not set`; sha256 of both executables into the manifest.
- **P2 `icewatch`** (section 5): tests green (red first); then, against the
  bar with no Ice: `icewatch dry-run --seconds 60` with three strips taken
  during it (to record the capture indicator's AX frame and show it trips
  nothing); `icewatch run` supervising `/bin/sleep 600` under the domain
  `com.icespike4.target` with one `--set`: `touch stop` → sleep killed, the
  domain restored and verified; the same for a SIGTERM to `icewatch`, for a
  stand-in controller process (`sleep`) being killed, for no `go` within the
  wait, and for the Bash background task that launched `icewatch` being
  stopped (`icewatch` must survive it and still stop and restore on `stop`);
  a changed non-allowlisted key trips T-prefs, an `NSStatusItem *` key does
  not; the log-flush latency of `/usr/bin/log stream` into a file measured
  with a scratch `logger` line. The real session-end path (the Claude
  process exiting) is the same process-exit source and is not exercised;
  the deadman backs it.
- **P3 Restore check** (inside P2's run): the sacrificial domain holds a
  string, a Bool, a Data, a Date and a nested dictionary; after export, keys
  are changed and one is added; `defaults import` of the export must give
  exactly the exported dictionary back. If the import merges, the restore
  becomes `defaults delete` + `defaults import`, re-checked the same way.
  Afterwards `defaults delete com.icespike4.target`.
- **P4 Observers**: `mbdiscover` release build; `axprobe2` (read-only) into
  the scratchpad, printing Ice's PID next to the CGS window list.

### Phase 0 — gates and snapshots (read-only; right before the launch)

1. **Gates**, each recorded; any failure stops here: no process from
   `/Applications/Ice.app/` and no process named `Ice`; no other menu bar
   manager running; `icewatch preflight` (non-prompting
   `AXIsProcessTrusted` and `CGPreflightScreenCaptureAccess` of a child of
   the same chain Ice will have) → both true (if Screen Recording is false:
   the layout pane cannot be read, G4's status line is dropped, the user is
   told before Phase 3); no `«` and no pill; **free-room reading ≥ 120 pt**
   (25 unusable + 33 icon + 41 indicator + margin; the ≈ 48 pt launch drain
   is an accepted transient).
2. **Snapshots** into `E/before/` (no capture was taken in the 10 s before
   the census): `mbdiscover --census-json`; one strip `screencapture -x -R
   0,0,1728,33`; `defaults export com.jordanbaird.Ice E/before/prefs.plist`
   (**the restore source**; the harness checks it exists and parses) and
   `com.apple.MenuBarAgent`; `com.apple.controlcenter`'s `NSStatusItem *`
   keys; for every process with an on-bar item whose
   `~/Library/Preferences/<id>.plist` exists, its `NSStatusItem *` keys
   (containers are never read); `defaults -currentHost read -globalDomain`
   `NSStatusItemSpacing` / `NSStatusItemSelectionPadding`; the Dock's
   `recent-apps` (bundle ids and URLs only); the `lsregister -dump` records
   for `com.jordanbaird.Ice`; the BTM record; existence of
   `~/Library/Saved Application State`, `~/Library/Caches/com.jordanbaird.Ice`,
   `~/Library/HTTPStorages/com.jordanbaird.Ice`; the DiagnosticReports listing.
3. The harness prints the **manual restore line** for the user —
   `defaults import com.jordanbaird.Ice <E>/before/prefs.plist` — and the rule
   "no logout, restart, sleep or lock until the harness reports the restore
   verified".
4. Start `/usr/bin/log stream --level debug --style ndjson --predicate
   'processImagePath CONTAINS "ice-main-build3/Build/Products/Debug/Ice.app/"'`
   → `E/ice-log.ndjson` (Ice and its XPC service), and a second stream
   `process == "tccd"` → `E/tccd.ndjson` (to make M3 measured); both checked
   alive (process up, file header written) before step 6.

### Phase 1 — launch and settle (≈ 60 s; no user action)

5. `icewatch run --app $APP --domain com.jordanbaird.Ice --backup
   E/before/prefs.plist --set UseIceBar=false --set ShowOnClick=false
   --set ShowOnScroll=false --set EnableSecondaryContextMenu=false
   --set ShowAllSectionsOnUserDrag=false --set AutoRehide=false
   --log E/ice-log.ndjson --controller <claude pid> --evidence E --detach
   -- -SUEnableAutomaticChecks NO -SUAutomaticallyUpdate NO`. `--detach`
   starts it in a new session owned by launchd (Deviation 6) and returns at
   once; the harness follows `E/icewatch-status.json` and `E/icewatch.jsonl`.
   It **arms first** (section 5: backup checked, own process
   group, controller watched), **then** writes the six settings itself
   (U2(a)) and re-reads them, and from then on owes the restore on every
   exit path. It then waits for `E/go`, at most 15 min (no go → restore,
   exit).
6. The user gives the live **"go"** for the launch; the harness `touch E/go`.
7. `icewatch` spawns Ice, records every tick, and owns every stop. The
   harness reads its JSONL; it never signals Ice itself.
8. Expectations E1–E4 (section 7) read from the log; at +10 s `axprobe2`
   once ("the probe's view" of the CGS menu-bar window list with Ice
   running; F9's own-connection question stays INFERRED).
9. The harness shows the user a crop of the strip at +30 s with Ice's icon
   marked (taken only if no capture ran in the previous 10 s).

### Phase 2 — read-only UI (the user)

Allowed clicks, and nothing else: **right-click Ice's icon** → *Search Menu
Bar Items* · *Ice Settings…* · in Settings, the sidebar item **Menu Bar
Layout** · **Escape** to close the panel · **⌘W** to close Settings · in
Phase 3 only, a **left click on Ice's icon**. Do not touch: every control in
General, Advanced, Appearance, Hotkeys and About (Launch at login, spacing
Apply, toggles, links), *Show Hidden Section*, *Check for Updates…*, *Quit
Ice*, *Show Item* / Enter in the panel, any of the user's own items, ⌘-drag
anywhere in the bar, scrolling over the bar. A crash dialog is closed, never
*Reopen* or *Report*. A Permissions window is left alone (stop).

10. The user opens the search panel. The harness takes `icewatch
    dump-windows --pid <Ice>` (read-only AX text of Ice's windows) and a
    window screenshot (`screencapture -x -l <wid>`); the census is the
    recorder's tick at that moment. Escape.
11. The user opens *Ice Settings…* → *Menu Bar Layout*; dump + screenshot;
    **⌘W**. (Settings stays closed in Phase 3.)

### Phase 3 — two show / hide cycles (U3(a) only; the harness asks for a "go")

Times are **minimums**, measured afterwards from the recorder (the divider's
AX frame changes at each click). No harness strip, panel or Settings during
a prepare or verify window.

12. **Cycle 1.** Left-click Ice's icon (show). Hold ≥ 15 s, then open the
    search panel (dump + screenshot), Escape, left-click Ice's icon (hide).
    Wait ≥ 20 s.
13. **Prediction for cycle 2**, from the recorder's tick at cycle 1's panel:
    the roster (items with `midX` < the collapsed divider's `minX`), the
    reference candidates (F18), the room (≥ 41 pt) → predicted status
    `No items to check` / `Not checked: noReference` / `Not checked: noRoom`
    / "a verdict". Written into `E` before cycle 2.
14. **Cycle 2.** Show; hold ≥ 45 s; panel (dump + screenshot); Escape; hide;
    wait ≥ 25 s. Then Settings → Menu Bar Layout: dump + screenshot of the
    status line; ⌘W.
15. **Indeterminate → no more cycles** (not a failure): the divider has no
    usable frame while collapsed; no pass without a `hidden(…)` note between
    show + 1 s and the panel; the item topology changed (an app added or
    removed an item) during a hold; the Screen Recording gate of step 1 was
    false (status line not readable).

### Phase 4 — exit and restore

16. The user closes every Ice window. The harness `touch E/stop`: `icewatch`
    stops Ice (section 5), watches 30 s, stops Ice's XPC service if left,
    restores and verifies the domain, and exits. The harness waits for its
    exit code.
17. Stop both log streams. Repeat every Phase 0 snapshot into `E/after/`
    (census ≥ 10 s after the last capture) and compare (section 7, E9).

---

## 5. `icewatch` — supervisor, recorder, watchdog, restorer

Where: `docs/macos-27/probes/visibility`: a library target `IceWatchCore`
(standard library only: the trip rules, the stop and deadman state
machines, the settings-key filter, the log-line matcher) with a test target,
and an executable `icewatch` (AX reads through
`MenuBarDiscovery.LiveExtrasReader`; no capture, no AX write, no AX action,
no event). Not linked into Ice. Subcommands `preflight`, `dry-run`, `run`,
`dump-windows`.

**`run`, in order.** (1) **Arm**: checks the backup exists and parses, no
process from `/Applications/Ice.app` and no other `Ice` is running, the log
file is being written; runs detached (`--detach`: a new session owned by
launchd, outside the Bash task's process tree, Deviation 6) and ignores
SIGHUP, so neither stopping the task nor ending the session kills it before
it has restored; watches `--controller` (the Claude process) with a process-exit
source. (2) **Write** the `--set` keys (`defaults write <domain> <key> -bool
<value>`), re-read them, and record the **expected dictionary** = the backup
with those values applied — the baseline of T-prefs. From here every exit
path restores. (3) **Wait** for `E/go` (≤ 15 min). (4) **Spawn** the child by
explicit path (`posix_spawn`), stdout / stderr into `E`; record its PID and
start time.

**Each tick (0.2 s):** reads `MenuBarAgent`, Ice, and every process in the
watched set, each with the 0.25 s per-element timeout; records one JSONL
line (wall time, tick duration, every frame with owner, child index and
identifier; agent frames). A process's read is one of **ok**, **failed**
(error or timeout), **ok-missing** (read fine, item gone). **Every 1 s** it
re-enumerates the running apps (non-`.prohibited`, as discovery does) and
adds every process that now has an on-bar item to the watched set before the
next evaluation; a process joining or leaving the set, or a change in the
count of `MenuBarAgent`'s children other than the indicator or pill, is
recorded as a **topology change** (section 4 step 15).

**Trips** (evaluated only on ticks shorter than 0.5 s; Ice's items and
agent items are never the "item" side):

| trip | condition |
|---|---|
| T-fold | a `MenuBarAgent` frame 17.5 ± 0.5 pt wide on the bar **overlapped by any item by > 25 % of the narrower** (the recorded overflow signature) — one tick; or such a frame without overlap for two ticks |
| T-stack | two items overlapping by > 25 % of the narrower, two ticks |
| T-post | an ndjson line with subsystem `com.jordanbaird.Ice`, category `MenuBarItemManager`, message starting `Posting ` — one line |
| T-prefs | the domain, polled every 2 s (`defaults export <domain> -`, parsed; `Data` values that hold JSON compared as parsed JSON, since Ice re-encodes them at setup), differs from the **expected dictionary** of step (2) in any key outside the runtime allowlist `NSStatusItem *`, `NSWindow Frame *`, `NSSplitView Subview Frames *` — a key added, removed or changed; `SU*` changes are **not** allowed (Sparkle is meant to write nothing) |
| T-ice | a process from `/Applications/Ice.app`, or a second process from `APP` |
| T-controller | the controller exited |
| T-dead | the deadman: 30 min, extended 15 min by `touch E/extend`, hard cap 60 min |

Recorded, never tripping: a failed read; an item that went missing or
parked with its process alive (an app may hide its own item); items moving
along the bar; the pill; the capture indicator; processes launching or
quitting. The harness looks at these between cycles (section 4 step 15).

**Stop** (a trip, `E/stop`, SIGTERM / SIGINT to `icewatch`, or the child's
own exit): if the child is alive and its `proc_pidpath` and start time are
still the spawned ones → SIGTERM; after 1 s → SIGKILL; confirm Ice's PID has
no AX items left; keep recording 30 s; SIGTERM any process whose image is
inside `APP` (the XPC service), path checked the same way. Then **restore**:
only if no `com.jordanbaird.Ice` process runs, `defaults import <domain>
<backup>`, export again, compare as parsed dictionaries; on a mismatch,
`defaults delete` + import once more and compare; still different →
`RESTORE-FAILED` in `E` and a distinct exit code. Exit code per outcome.

**`dump-windows --pid`**: `AXUIElementCreateApplication(pid)` → `AXWindows`
→ recursive `AXRole` / `AXValue` / `AXTitle` / `AXDescription` /
`AXIdentifier`, 0.25 s timeout, depth ≤ 40, ≤ 5 000 nodes; read-only.

**Tests (red first):** each trip on its own tick count and not before; a
failed read never trips; ok-missing and parked do not trip; Ice's and agent
items never form the item side; a moved item, a pill-width and an
indicator-width agent frame do not trip; a slow tick skips evaluation; the
log matcher ignores other subsystems, categories and malformed or partial
lines; the settings filter ignores `NSStatusItem` / `NSWindow` /
`NSSplitView` keys and nothing else (`SU*` trips); the expected dictionary is
the backup plus the `--set` values, and JSON `Data` compares parsed; the
stop machine sends TERM, KILL after 1 s, never to a PID whose path or start
time changed, and restores only when no Ice runs; an abort before `go`
restores; a process joining the on-bar set is watched from the next tick and
recorded as a topology change; the deadman extends and caps.

DoD: tests green; P2 passes.

---

## 6. Stops, and what is not a stop

**Stop** (`icewatch` stops Ice; Phase 4 continues from its restore): any
trip; any system prompt (TCC, notifications, screen-capture
re-authorisation) — **not answered**; Ice's Permissions window, or E1 reading
"Failed required permissions checks" — nothing in it clicked; an unexpected
Ice alert; a crash (dialog closed, report copied into `E`); no "Finished
setting up app state" and no boundary note within 15 s of "Starting
MenuBarItemService connection" (recorded as "not reached" for G1–G4); the
user says stop.

**Recorded, not a stop:** any status-line text of F14; `noReference`,
`noRoom`, `preflight`, `noBaseline`; an empty Hidden list in cycle 1; the
divider parked while expanded; the icon's position; items shifting; the
capture indicator; a Debug `assert` at `ControlItem.swift:91` would be a
crash (stop) recorded as a Debug-only candidate (F19).

**If the bar does not come back after exit:** nothing is retried; the user
is told which item (by role) and decides; quitting and reopening the owning
app is theirs to do.

---

## 7. Acceptance (pre-registered)

| # | expectation | how |
|---|---|---|
| E1 | `Passed all permissions checks` (both grants, M3) or `Passed required permissions checks` | `ice-log.ndjson` |
| E2 | within 15 s of `Starting MenuBarItemService connection`: `Finished setting up app state`; the XPC outcome recorded as success (no `Start request returned nil` / `…invalid response` / `Session failed with error` / `Session was cancelled with error` line from `MenuBarItemService.Connection`) or as the failure line seen; the service side (`Activating listener`, `Listener received start request`, `Failed to activate listener`) recorded | same |
| E3 | a boundary-note heartbeat `alwaysHidden(IceCore.BoundaryIssue.disabled)` about every 5 s; while idle `hidden(IceCore.BoundaryIssue.expanded)` or `…unusable` (divider parked). Pre-registered as making G3 / G4 unmeasurable: `…missing`, `…identifiersMissing`, `…ownReadFailed` | same |
| E4 | no `Posting ` line | same + T-post |
| E5 | G1: no "Loading menu bar items…" in the panel (steps 10, 12, 14) or the layout pane (steps 11, 14) | dumps + screenshots |
| E6 | G2: per section, the panel's names (right to left) = the tick's on-bar items of processes read ok, named as Ice names them (the app's name), plus Ice's icon; stacked and frameless items included; each difference explained (carried, dropped role, identity collision, `.prohibited`) | offline compare |
| E7 | G3: at each panel of Phase 3, with a pass that computed the boundary since show + 1 s, the panel's split = `DiscoveredCachePlan.make` over the tick (Ice's process as its own, Ice's icon included); a second check by hand: `midX ≥ divider.minX` → Visible. Otherwise "not measured" | offline compare |
| E8 | G4: the status line after cycle 2 = step 13's prediction; the number of `Hiding check for <private>: …` lines = roster ∩ cycle-2 Hidden (verdict texts as a multiset; per-item attribution is not observable) | dump + log |
| E9 | G5: the restore verified by `icewatch`; census order and widths back (shifts left of an item whose width changed allowed); no new or changed key in the user apps' `NSStatusItem *`, Control Center's, the spacing keys, BTM, LaunchServices (same records), the Dock's recents; no new saved state, cache, crash report; `MenuBarAnalytics.*` in `com.apple.MenuBarAgent` may differ | diffs |
| E10 | no trip | `icewatch` JSONL |

Any non-empty diff in E9 other than the allowed ones is reported to the user
with its responsible step; the harness writes nothing to fix it. If a Dock
recents entry for the build appears, the user removes it through the Dock
(right-click → Options → Remove from Dock).

---

## 8. After the run

- FINDINGS gets a MEASURED section for the first run; the ax-discovery plan's
  §1 and §4.4 are corrected where the run or the recon contradicts them
  (already known: `HIDEventManager` is not inert; the XPC `start()` is on the
  setup path; IceBar mode produces no status line; the text says "item(s)").
- A defect is fixed **test-first on a new local branch `wip/first-run`**
  (packages: unit tests; Ice: build + static checks, as T9); a re-run needs a
  new approval.
- Then `/simcodex`, the full test run and the evidence package. Commit,
  merge and push wait for the user.

## 9. Risks and rollback

| risk | response |
|---|---|
| a fold or loss shorter than one tick, or hiding in the no-fold band | not detectable live; strips before and after, and the check's own captures, are the only pixel evidence |
| a collapse / expand folds or loses an item | T-fold at its first sign, T-stack in two ticks → SIGTERM, SIGKILL 1 s later; 30 s post-exit record |
| the XPC `start()` stalls | 15 s → stop; no `sample` (it may raise a developer-tools prompt) |
| Ice crashes | the stop runs from the child's exit; the report copied into `E` |
| a system prompt | not answered; stop |
| the Bash session ends | `icewatch` runs detached (launchd-owned, own session; Deviation 6), sees the controller exit, stops Ice and restores |
| `icewatch` itself is killed with SIGKILL | the user's manual restore line (step 3); Ice is then quit by the user from its menu |
| the restore does not verify | delete + import once; else `RESTORE-FAILED`, the user is told, the export stays in `E` |
| the release Ice starts meanwhile | T-ice → stop; no restore while any `com.jordanbaird.Ice` runs |
| Settings leaves a Dock recents entry or saved state | Settings closed before exit; checked in E9; removal is the user's |

What the run can write outside `E` and the scratchpad: the shared domain
(restored and verified); the tccd / unified-log records any process makes;
the re-registration of the existing build path (P1); possibly a Dock recents
entry or saved state (checked, section 7).

## Appendix A — review record, round 1

Reviewers: Codex (C1–C17), Opus safety (S1–S11), validity (V1–V12),
executability (E1–E18). Rulings:

| finding | ruling |
|---|---|
| C1 the restore source had no path | **adopt** → explicit path, checked before launch |
| C2, S4, E1 nothing restores the domain if the session dies; the watchdog shares the session's fate | **adopt** → `icewatch` supervises Ice in its own process group, watches the controller, restores on every exit path; the manual line (step 3) |
| C3 `CODE_SIGNING_ALLOWED=NO` gives no ad-hoc signature | **reject**: MEASURED `flags=0x20002(adhoc,linker-signed)` on the last build; the expected fields are now stated (E18). Fed back to Codex |
| C4, C15 direct exec's trust is not shown for this binary; preflight it | **modify** → no separate preflight of Ice's binary: an untrusted Ice shows only its Permissions window (F1) — a stop; `icewatch preflight` checks the chain; "no TCC row written" (not "read"); tccd stream recorded. Fed back |
| C5 disagree with U2(a), isolate the domain | **reject** with reasons (section 3 U2): isolation changes the layout under test and still needs the run's settings; the restore is now automatic and verified. Fed back |
| C6 the new LaunchServices record contradicts G5 | **adopt** → build into the registered derived data; no new record |
| C7 disagree with U3(a), detection after the fact | **modify** → T-fold at the first overflow sign, SIGKILL after 1 s, the undetectable cases stated in U3; U3 stays the user's choice with (b) offered. Fed back |
| C8 new items not watched | **adopt** → rolling coverage; topology change ends the cycles (step 15) |
| C9 no Screen Recording gate | **adopt** → step 1 |
| C10 cycle 2 has no panel | **adopt** |
| C11 census not contemporaneous with the panel | **adopt** → the recorder's tick at the panel; the pass precondition from the log |
| C12, V8 a successful XPC start is not logged | **adopt** → E2 |
| C13, V7 E6 not operational | **adopt** |
| C14, V4 per-item log keys are private | **adopt** → counts and case multisets only |
| C16 the watchdog is over-engineered | **reject in part**: one tool is the smallest thing that restores after a dead session, records continuously and trips in < 1 s; no separate recorder, no second library |
| C17 indeterminate states recorded, not stopped | **adopt** → step 15 |
| S1, E8 Settings leaves a Dock recents entry | **adopt** → Settings twice, briefly, closed before exit; recents in the snapshots |
| S2 clicks inside Ice's windows can change the system | **adopt** → allowed-click list and do-not-touch list; T-prefs; spacing, Control Center keys snapshotted |
| S3, E5, V6 the room gate ignores the capture indicator; Ice's own 5 s capture | **adopt** → ≥ 120 pt; few strips; Settings closed in Phase 3 |
| S5, E7 saved state after a kill with windows open | **adopt** → windows closed before the stop; checked |
| S6, V3, E6 failed reads and apps hiding their own items false-trip; band hiding undetectable | **adopt** → three read states; missing / parked recorded only; stated in U3 and section 9 |
| S7, E13 `ShowAllSectionsOnUserDrag` | **adopt** |
| S8 signals to a bare PID; second Ice; import while Ice runs | **adopt** |
| S9 T-post matching and latency | **adopt** → subsystem + category + prefix; flush latency measured in P2 |
| S10, E16, V12 snapshot scope and comparison rules | **adopt** |
| S11 sandbox mode; `sample` may prompt; Permissions window stop | **adopt** → M4; no `sample`; section 6 |
| V1 G4 needs a reference, probably absent | **adopt** → F18, step 13 prediction, E8 by branch; variant (d) (moving the divider's preferred position) recorded for a later run, not this one |
| V2, E15 step 13 was not Ice's rule | **adopt** → E7 with `DiscoveredCachePlan.make` and the pass precondition |
| V5 F15 wrong for later cycles | **adopt** → F15 corrected; cycle 2 hold ≥ 45 s |
| V9 E3 alternatives | **adopt** |
| V10, E12 axprobe2 sees another connection's view | **adopt** → recorded as the probe's view |
| V11 the indicator's width is unknown against T-fold | **adopt** → T-fold keyed on the overflow signature; P2 records the indicator |
| E2 `log` is a zsh builtin | **adopt** → `/usr/bin/log`; liveness checked |
| E3 a turn-based harness cannot keep timings | **adopt** → the recorder; holds are minimums measured afterwards |
| E4 no reader for Ice's window text | **adopt** → `dump-windows`; screenshots; no Apple Events |
| E9 the watchdog started late | **adopt** → `icewatch` spawns Ice |
| E10 Debug `assert`s | **adopt** → F19, section 6 |
| E11 xpc / tccd context | **adopt in part** → the tccd stream |
| E14 unambiguous instructions | **adopt** → the icon crop; allowed clicks; crash dialog rule |
| E17 the deadman at conversational pace | **adopt** → 30 min + 15 min extensions, cap 60 |
| E18 build fetch and codesign fields | **adopt** → existing derived data; fields stated |

### Round 2 (Codex on v2)

| finding | ruling |
|---|---|
| C3, C4/C15, C7, C16 | **withdrawn** by Codex (it re-checked the signature itself; the untrusted path is a no-side-effect stop; the limits of U3 are stated and (b) offered; one supervisor is proportionate) |
| C5 re-raised with a new argument: the settings were written (step 5) before `icewatch` existed (step 7), so a session death in between left them unrestored | **Codex wins** → `icewatch` arms first and writes the settings itself (steps 5–7) |
| new P1: T-prefs had no defined baseline | **adopt** → the expected dictionary (backup + `--set`), an explicit allowlist, parsed comparison |
| new P1: a process that starts during the run was never read | **adopt** → re-enumeration every 1 s; topology changes recorded |
| new P2: the session-end path is not tested | **modify** → P2 tests the launching task being stopped and a stand-in controller dying; the real Claude-process exit uses the same mechanism and is not exercised; the deadman backs it |

The package-level "HARD RULE" quoted in `mbdiscover`'s header (run against
the real bar only as a one-off smoke check) is not in any plan; the
ax-discovery T6 ran it on the real bar several times with outputs kept in
the evidence directory. This plan does the same and asks the user to confirm
it in the approval.

## Appendix B — Jev on U1–U3

`jev-1.13.0`; request and response in
`~/IceReverse-evidence/20260924-firstrun-plan/jev/` (checked: no app names or
bundle ids of the user's apps). Six requirements (R1 the user's items end
exactly as they were; R2 no persistent change; R3 measure Loading and the
list; R4 measure the split and the check; R5 stoppable within seconds, and
restored even if the session dies; R6 test the build as the user runs it);
options described neutrally; one noul per option × requirement (near 0.5 =
undecided; a high noul is a consequence to state, not a veto).

| # | Jev's choice | p | = plan | nouls ≥ 0.4 |
|---|---|---|---|---|
| U1 | child of the supervisor | 1.00 | yes | launcher + grant × R2 **0.94**, × R6 0.64 |
| U2 | shared domain, restored | 0.99 | yes | new identity × R6 **0.96**, × R2 0.80, × R1 0.73, × R5 0.52 |
| U3 | cycles under the watchdog | 0.91 | yes | cycles × R1 **0.44** (undecided); skip × R4 **0.96** |

Stated consequence: U3(a) × R1 at 0.44 is the unmeasured collapse / expand
beside the user's items (section 0.3) — the cost the user is asked to accept
or decline.

## Deviations (ledger, written as they happen)

Format: trigger → what changed → reason.

1. Building `icewatch` (2026-09-24): `IceWatchCore` needs JSON and property
   lists → it imports Foundation (still no AppKit, no Accessibility), not
   "standard library only" as section 5 said → parsing ndjson and plists
   is the rule's input; hand-parsing them would be untested code of its own.
2. P3, MEASURED on `com.icespike4.target`: `defaults import` **merges** — a
   key added after the export survives it, while changed keys are restored;
   `defaults delete` + `defaults import` restores exactly (string, Bool,
   Data, Date, dictionary, integer) → the restore is import, compare, and on
   a difference delete + import + compare (as section 5 already allowed).
3. P2, MEASURED: `/usr/bin/log stream --style ndjson` writes one non-JSON
   header line first; a `logger` line reached the file in 0.02 s. The
   60 s dry run (290 ticks, median 14 ms, slowest 0.27 s) tripped nothing;
   two failed reads of one process were recorded, not tripped; during three
   strip captures the capture indicator did **not** appear in
   Accessibility, while the clock's AX x moved 3 pt (as FINDINGS records).
   The indicator's width therefore stays unmeasured; T-fold does not depend
   on it.
4. P2 scenarios found a defect: with the child at a `/tmp/…` path the
   identity check compared Foundation's `resolvingSymlinksInPath` spelling
   (`/tmp/…`) with `proc_pidpath`'s (`/private/tmp/…`), never matched, and so
   **never signalled the child** (four test children left running, killed
   by hand; the domain was restored in every scenario) → every path is now
   canonicalized with `realpath`, identity lives in `ChildIdentity` (tested;
   an unknown start time never matches). Also: a copied `/bin/sleep` is
   SIGKILLed outside `/bin`, and a stray `/bin/sleep` on the system tripped
   T-ice (correctly) → the scenarios use a scratch-built `sleep`.
5. Codex's review of `icewatch` (6 P0, 5 P1, 1 P2) → all adopted: repeated
   `--set` keys refused before any write; the restore waits for **every** Ice
   (recognised by bundle id, `IceProcesses`, covering the other local builds
   and the XPC services) and retries until it has restored, writing
   `RESTORE-PENDING` after 10 s, never exiting unrestored; the child needs a
   known start time to be signalled; XPC services re-checked (path and start
   time) right before each signal and stopped at the **end** of the
   post-exit watch; `defaults` runs bounded (10 s, then killed); no AX tick
   while TERM / KILL is in progress; the log is read only from arming on;
   `setpgid` checked; `MenuBarAgent` child-count changes recorded as topology;
   `--interval` bounded to [0.05, 1] s.
6. P2, MEASURED: stopping a Bash background task sends SIGTERM and, about a
   second later, SIGKILL to **every process in its tree**, whatever their
   process group — `setpgid` protects nothing. An attached `icewatch` got
   the SIGTERM, began its stop, and was killed during the 30 s watch, so
   the sacrificial domain stayed changed (cleaned by hand) → `run --detach`
   re-runs `icewatch` with `POSIX_SPAWN_SETSID`; the launcher exits and
   launchd adopts it (MEASURED: ppid 1, own session and group, **still
   trusted for Accessibility and screen capture**, so Ice as its child
   inherits the terminal's grants). Re-run: the launching task stopped,
   `icewatch` and its child survived, a later `stop` ended the child,
   watched 30 s and restored the domain exactly. The plan's "own process
   group" claim (section 5, section 9) is replaced accordingly.
7. Codex's second review of `icewatch` (all round-1 items resolved except
   two, plus one new P1) → adopted: after the import is verified the
   processes are scanned again and, if an Ice appeared during the import,
   the restore waits and runs again (a scan cannot exclude a concurrent
   launch; no lock exists); after a trip sends TERM the tick returns at
   once (no further AX work); options are parsed strictly (`Options`:
   unknown options, a valued option without its value, and repeats of
   non-repeatable options are refused before anything is written).
   Regression: a dangling `--set` and a misspelt option exit 21 with
   nothing written; an arm failure (empty log) writes nothing; a detached
   run wrote, stopped, watched and restored exactly. IceWatchCore 44 tests.
8. First run, 2026-09-24 09:15 (evidence `~/IceReverse-evidence/20260924-091543-icerun`):
   Phase 0 passed (free room 156.5 pt, no `«`, no pill, both grants, log
   streams live); `icewatch` then **refused to arm** — "the domain no
   longer equals the backup: SULastCheckTime" — and wrote nothing (all six
   settings verified unchanged). Cause, MEASURED: `defaults export <d> -`
   writes XML, whose dates keep whole seconds (27 vs 27.115129), so it never
   equals the binary backup; P2's dates were whole seconds, which hid it →
   `DefaultsTool.export` now exports a binary plist to a scratch file.
   Regression on the sacrificial domain with a sub-second date: armed,
   wrote, ran, stopped, restored exactly. **Ice was not launched.** The user
   then paused the run; the log streams were stopped and
   `com.jordanbaird.Ice` checked equal to its export.
9. The run, 2026-09-25 09:22 (evidence `~/IceReverse-evidence/20260925-092244-icerun`):
   after Phase 1 the user asked the harness to do the clicks ("你來操作 點擊吧"),
   against the constraint "no mouse or keyboard events" → a scratch tool
   (`iceop`, kept in `E`) did only this: a right or left click posted at
   Ice's icon after two checks (the newest recorder tick < 1.5 s old has no
   other process's item frame at the point -- Ice's own divider, whose AX
   frame spans the icon once it sits on the bar, is exempt since a click
   there opens the same menu -- and an AX hit test at the point returns an
   element of Ice's PID); menu items and the Settings window's close button
   by `AXPress`; the Settings sidebar row by a click after the same hit test;
   Escape posted to Ice's PID only. Not `AXPress` on the icon: Ice picks the
   click type from `NSApp.currentEvent` (`ControlItem.swift:460-501`), so an
   AX press could toggle a section. Nothing of the user's was clicked.
10. Unplanned collapse / expand cycles at 09:25:30–34 (three) and 09:33:29–34
   (two), not posted by the harness (its operations are timestamped in `E`);
   the user does not remember clicking. They gave the Phase 2 status line
   `Not checked: noBaseline` (each collapse < 1.4 s) and are counted in the
   "collapse / expand beside the user's items" result.
11. Cycle 1's hold was extended to 48 s (≥ the ≈ 31 s prepare bound) so the
   panel screenshot could not fall inside a prepare (section 4 step 12 and
   "no harness strip … during a prepare" read together); the cycle 2
   prediction was written to `E/prediction-cycle2.txt` before cycle 2's show
   and matched (status line and per-item verdicts).
