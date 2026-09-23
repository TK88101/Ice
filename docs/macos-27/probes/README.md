# Probes

One-shot programs that produced the measurements in `../FINDINGS.md`. They are not
part of the build — nothing here is in an Xcode target, and `.swiftlint.yml` only
covers `Ice`. Keep them so the findings can be re-checked rather than re-argued.

```sh
swiftc -O <probe>.swift -o /tmp/<probe> && /tmp/<probe>
```

Build products must not land in this repo: it lives under `~/Documents`, which is
iCloud-managed, and the extended attributes that get attached there make `codesign`
reject the result. For the same reason `swift test` in `Packages/IceCore` needs
`--scratch-path` pointing outside `~/Documents`.

| probe | answers | side effects |
|---|---|---|
| `axprobe2.swift` | Does Ice's private-API discovery path return anything? | none |
| `axspike1.swift` | Full AX attribute surface, settability, identity stability, per-item window number | none |
| `axorder.swift` | Does the menu bar reorder itself when left alone? | none |
| `axspike2.swift` | Does `NSStatusItem.length` still push items out of the bar? | creates **its own** status items and resizes them; screenshots the strip |
| `helper.swift` | Source of the two sacrificial helper apps | one status item per process |
| `verify3.swift` | Are the helpers up, identifiable and stable? | none |
| `watch3.swift` | Polls the helpers at 5Hz and reports any order change | none |
| `inject3.swift` | Can a coordinate-only synthetic drag move another process's item? | **injects mouse events**; moves the cursor for ~2s then restores it |

`axspike2.swift` carries the accumulated edits from its final run — three probes
plus a spacer, screenshots at each width. Read it before running it.

Two instruments that did **not** work, recorded so they are not tried again:

- A `CGEventTap` in an unsigned binary sees mouse events but **not** modifier
  state. It reported zero `flagsChanged` events across 90 s of real use. Do not
  use a tap to confirm that a Command-drag happened; poll positions instead.
- `MBSystemItemIdentifier.stringValue` cannot be called through `dlsym` with a
  `@convention(c)` cast — it segfaults. The case list in `../FINDINGS.md` came
  from disassembly, not from calling it.

To rebuild the helper apps, see the `build()` shell function reconstructed from
`helper.swift`: compile into `<Name>.app/Contents/MacOS/<Name>`, add an
`Info.plist` with a unique `CFBundleIdentifier` ending in `.target` or `.anchor`
and `LSUIElement` true, then `codesign --force --sign -`.

## safewidth/

A SwiftPM package rather than a one-shot file, because this measurement needs a
guard that protects the user's items while it runs. `SafeWidthCore` is pure logic
with its own tests (IceCore's rule: no AppKit, AX, CoreGraphics or ImageIO);
`swctl` is the only part that touches the screen; `swhelper` and `swfront` are the
sacrificial menu bar items and the frontmost app whose menu width is the
experiment's variable.

```sh
./safewidth/build.sh /tmp/safewidth        # builds outside ~/Documents, signs the apps
/tmp/safewidth/apps/swctl b0 --git <rev>   # baseline with nothing of ours in the bar
/tmp/safewidth/apps/swctl calibrate --b0 ~/IceReverse-evidence/<run>
/tmp/safewidth/apps/swctl c    --config mid  --apps … --calibration …   # instrument + null control
/tmp/safewidth/apps/swctl o0   --apps … --calibration …                 # order-dependence replication
/tmp/safewidth/apps/swctl scan --config mid  --apps … --calibration …   # coarse jump scan -> brackets
/tmp/safewidth/apps/swctl o1   --widths … --apps … --calibration …      # protocol check at the transitions
/tmp/safewidth/apps/swctl m    --config mid --brackets hide:16:24,… --apps … --calibration …
```

Results and their run ids: `safewidth/RESULTS.md`. Raw evidence stays in
`~/IceReverse-evidence/<run id>/` — the strips show which apps are installed, so
they are deliberately not committed.

Two things this package learned the hard way, both in `RESULTS.md`:

- The menu bar is translucent over **the window under it**, not just the
  wallpaper, and the wallpaper changes during the day. A reference capture is
  only valid for the run that took it, with the same app in front.
- An app with no windows cannot hold the front once anything else launches, so
  `swfront` keeps a small window in a corner.

## visibility/

The pixel detector's probes (plans `2026-09-19-visibility-adapter.md` and
`2026-09-23-ax-discovery.md`), a SwiftPM package like `safewidth/`. It links
IceCore, MenuBarCapture and MenuBarDiscovery; the detector's rules live in
IceCore and are never changed from here.

| target | what it is | side effects |
|---|---|---|
| `vzreplay` | offline replay of recorded strips (2026-09-19 T9) | none |
| `vzhelper` | the sacrificial status items: `--role` (2026-09-19), or `--items 1\|2 --identifiers none\|a,b --glyphs target\|reference\|alt`, `--mimic-nodivider` (Ice's `.noDivider` shown state, reached as Ice reaches it, never expanded), `--autosave` (step 10 only); stdin commands `hide`, `show`, `frames`, `selfread`, `quit` | one or two status items under `com.icespike4.target` / `.protected` |
| `VZGlyphs` | the helpers' stroked glyphs, shared so the dry run can check them | none |
| `vizprobe` | the live harness: `--dry-run` and `live` (2026-09-19); `discover` and `verify` (2026-09-23 section 6), each with its own `--dry-run` | launches helpers, captures the bar; never moves, clicks or resizes anything of the user's |

```sh
./visibility/build.sh                         # -> /private/tmp/claude-501/visibility-live/apps
cd /private/tmp/claude-501/visibility-live/apps
./vizprobe discover --dry-run --apps .        # read-only: bundles, glyphs (+ a twin control), preflight, one discovery pass, step-2 room
./vizprobe discover --apps .                  # steps 1, 2, 4, 9, 10a, 10b, 7, 8, 11 (D9 and D10 first)
./vizprobe verify --apps .                    # steps 1, 2, 3, 5, 6, 11
```

Both live stages check the bundle ids and that no helper is already running
before anything else, delete and verify-empty a helper's defaults domain before
every launch, check for `«` or a privacy pill before and after every launch and
at every safety check, and stop on any unexpected verdict, quitting every
helper (also on the watchdog, SIGINT, SIGTERM and SIGHUP). Evidence goes to
`~/IceReverse-evidence/<run id>/`, outside the repo: captures show the user's
bar. Results: `../FINDINGS.md`, "Discovery through Accessibility, in detail".

