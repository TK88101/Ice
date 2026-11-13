#!/bin/zsh
# D6 of plan 2026-11-13-zh-hant: every localizable key has a zh-Hant value.
#   check-zh-hant.sh <derived data dir of a Debug build> <IceCore scratch dir>
# Keys: what the compiler extracted (*.stringsdata of the Ice target), the
# hand list (zh-hant-hand-keys.txt) and IceCore's OwnerMessage.allTemplates
# (dumped by its test). Also: no English literal left in the UI sinks outside
# String(localized:) / LocalizedStringKey. Exit 0 when complete.
set -euo pipefail
here=${0:A:h}
root=${here:h:h:h}
dd=${1:?derived data dir}
scratch=${2:?IceCore scratch dir}
dump=$(mktemp -t zh-templates)
ICE_DUMP_TEMPLATES=$dump swift test --package-path "$root/Packages/IceCore" --scratch-path "$scratch" \
    --filter "OwnerMessage" > /dev/null
/usr/bin/python3 -I - "$root" "$dd" "$dump" <<'PY'
import glob, json, os, re, sys
root, dd, dump = sys.argv[1:]
objects = glob.glob(os.path.join(dd, "Build/Intermediates.noindex/Ice.build/*/Ice.build/Objects-normal/*/*.stringsdata"))
if not objects:
    sys.exit("check-zh-hant: no .stringsdata under " + dd)
keys = set()
for path in objects:
    for entries in json.load(open(path)).get("tables", {}).values():
        keys.update(entry["key"] for entry in entries)
hand = [line.rstrip("\n") for line in open(os.path.join(root, "docs/plans/checks/zh-hant-hand-keys.txt"))
        if line.strip() and not line.startswith("#")]
keys.update(hand)
keys.update(json.load(open(dump)))
catalog = json.load(open(os.path.join(root, "Ice/Resources/Localizable.xcstrings")))["strings"]
failures = []
for key in sorted(keys):
    unit = catalog.get(key, {}).get("localizations", {}).get("zh-Hant", {}).get("stringUnit", {})
    if not unit.get("value") or unit.get("state") != "translated":
        failures.append("untranslated: " + repr(key))
# NSMenuItem titles sit on their own line (`title: "..."`); an item tag's title is
# inline and not shown. A sink with no letter in it ("", "|") is not text.
sinks = re.compile(r'(^\s*title: "[A-Za-z]|\.title = "[A-Za-z]|messageText = "|informativeText = "|Text\(verbatim: "[A-Za-z])')
# D2's "not translated" list: panels with no title bar, the language's own name,
# and the updater, which is off on macOS 27.
allowed = {'self.title = "Ice Bar"', 'self.title = "Menu Bar Overlay"', 'Text(verbatim: "English")',
           'title: "A new update is available"'}
for path in glob.glob(os.path.join(root, "Ice/**/*.swift"), recursive=True):
    for number, line in enumerate(open(path), 1):
        stripped = line.strip()
        if stripped.startswith("//") or not sinks.search(line):
            continue
        if any(token in stripped for token in allowed):
            continue
        failures.append("English literal in a UI sink: %s:%d: %s" % (os.path.relpath(path, root), number, stripped))
for failure in failures:
    print(failure)
print("check-zh-hant: %d keys, %d failures" % (len(keys), len(failures)))
sys.exit(1 if failures else 0)
PY
