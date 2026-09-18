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
