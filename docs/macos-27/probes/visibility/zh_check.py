#!/usr/bin/env python3
"""L2 of plan 2026-11-13-zh-hant: reads Ice's Settings panes and its two
right-click menus over Accessibility and reports any text that is not
Traditional Chinese from the catalog.

    zh_check.py <ice pid> <catalog .xcstrings> <evidence dir>

Built on settingsdrive (`axdump`, `hit`, `windows`, `items`, `gap`, guarded
`click` and `key`), the settings pass's hands: input goes only to empty menu
bar space (`--expect empty`) and to Ice's own windows and icon (`--expect
pid:<ice>`). Settings is opened by a reopen of Ice (`open -a`), which Ice
answers by opening it. Screenshots go to the evidence dir, never the repo.
Exit 0 when nothing English is left.
"""
import json
import os
import re
import subprocess
import sys
import time

BAR_Y = 16
DRIVE = os.environ.get("S6_DRIVE", os.path.expanduser("~/.cache/icereverse-s6/settingsdrive"))
# The panes Ice offers on macOS 27 (the layout pane is not offered there).
PANES = ["一般", "選單列外觀", "快速鍵", "進階", "關於"]
# Names that stay as they are (plan D5), and texts that are not language.
KEPT = {"Ice", "Ice Bar", "English", "BETA", "macOS", "Ice Cube"}
# The About pane's legal notice (Info.plist), kept as written: names and a licence.
LEGAL = re.compile(r"^Copyright ©")
NOT_LANGUAGE = re.compile(r"^[\d\s.,:;%·•+\-–—×/()«»|⌘⌥⌃⇧↩⎋⇥]*$")


def catalog_values(path):
    """Every zh-Hant value of the catalog, and every English key."""
    strings = json.load(open(path))["strings"]
    values, keys = set(), set(strings)
    for unit in strings.values():
        value = unit.get("localizations", {}).get("zh-Hant", {}).get("stringUnit", {}).get("value")
        if value:
            values.add(value)
    return values, keys


def is_chinese(text):
    return any("一" <= character <= "鿿" for character in text)


def untranslated(texts, keys, kept=KEPT, foreign=()):
    """The texts that are an English catalog key, or English words with no
    Chinese in them, minus product names, other apps' names and non-language."""
    found = []
    for text in texts:
        text = text.strip()
        if not text or text in kept or text in foreign or NOT_LANGUAGE.match(text) or LEGAL.match(text) or is_chinese(text):
            continue
        if text in keys or re.search(r"[A-Za-z]{3,}", text):
            found.append(text)
    return sorted(set(found))


IDLE_WAIT_SECONDS = 3600


def drive(*arguments):
    """One settingsdrive call; an input refused because the owner is using
    the Mac is tried again every 2 s, up to IDLE_WAIT_SECONDS, never forced."""
    deadline = time.time() + IDLE_WAIT_SECONDS
    while True:
        done = subprocess.run([DRIVE] + [str(a) for a in arguments], capture_output=True)
        lines = done.stdout.decode().strip().splitlines()
        result = json.loads(lines[-1]) if lines else {}
        if result.get("result") != "refused" or time.time() > deadline:
            return result
        time.sleep(2)


def texts_of(rows):
    found = []
    for row in rows:
        for key in ("value", "title", "description", "help"):
            if isinstance(row.get(key), str) and row[key]:
                found.append(row[key])
    return found


def wait_rows(pid, minimum=10, seconds=8):
    deadline = time.time() + seconds
    while time.time() < deadline:
        rows = drive("axdump", pid).get("rows", [])
        if any(row["role"] == "AXWindow" for row in rows) and len(rows) >= minimum:
            time.sleep(1.0)
            return drive("axdump", pid).get("rows", [])
        time.sleep(0.3)
    raise SystemExit("zh_check: Settings did not open")


def capture(path, bounds):
    x, y, width, height = bounds
    subprocess.run(["/usr/sbin/screencapture", "-x", "-R", "%d,%d,%d,%d" % (x, y, width, height), path])


def menu_texts(pid, out, name):
    """The entries of the menu Ice has open, read by hit test, then closed."""
    deadline = time.time() + 3
    menu = None
    while time.time() < deadline and menu is None:
        menus = [w for w in drive("windows", pid).get("windows", []) if w["onScreen"] and w["layer"] == 101]
        menu = menus[0] if menus else None
        time.sleep(0.1)
    if menu is None:
        raise SystemExit("zh_check: the %s menu did not open" % name)
    capture(os.path.join(out, name + ".png"), menu["bounds"])
    x, y, width, height = menu["bounds"]
    entries = []
    for offset in range(6, int(height), 6):
        found = drive("hit", x + width / 2, y + offset)
        title = found.get("chain", [{}])[0].get("title") if found.get("pid") == pid else None
        if title and (not entries or entries[-1] != title):
            entries.append(title)
    drive("key", 53)
    time.sleep(0.5)
    return entries


def main():
    pid, catalog, out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    _, keys = catalog_values(catalog)
    foreign = {item.get("title") for item in drive("items").get("items", []) if item.get("pid") != pid}
    report = {}

    subprocess.run(["/usr/bin/open", "-a", "/Applications/Ice.app"])
    rows = wait_rows(pid)
    for pane in PANES:
        row = next((r for r in rows if r["role"] == "AXStaticText" and r.get("value") == pane and r["depth"] >= 8), None)
        if row is None:
            report[pane] = {"error": "not in the sidebar"}
            continue
        x, y, width, height = row["frame"]
        drive("click", x + width / 2, y + height / 2, "--expect", "pid:%d" % pid)
        time.sleep(1.2)
        rows = drive("axdump", pid).get("rows", [])
        window = next((r for r in rows if r["role"] == "AXWindow"), None)
        if window:
            capture(os.path.join(out, "pane-%s.png" % pane), window["frame"])
        texts = texts_of(rows)
        report[pane] = {"texts": sorted(set(texts)), "untranslated": untranslated(texts, keys, foreign=foreign)}

    gap = drive("gap", 960).get("x")
    drive("click", gap, BAR_Y, "--expect", "empty", "--right", "--hold", 0.4)
    entries = menu_texts(pid, out, "secondary-menu")
    report["secondary menu"] = {"texts": entries, "untranslated": untranslated(entries, keys)}

    icon = next((i for i in drive("items").get("items", []) if i.get("pid") == pid
                 and i.get("identifier") == "Ice.ControlItem.Visible"), None)
    if icon:
        x, y, width, height = icon["frame"]
        drive("click", x + width / 2, BAR_Y, "--expect", "pid:%d" % pid, "--right")
        entries = menu_texts(pid, out, "icon-menu")
        report["icon menu"] = {"texts": entries, "untranslated": untranslated(entries, keys)}
    else:
        report["icon menu"] = {"error": "Ice's icon not read"}

    json.dump(report, open(os.path.join(out, "zh_check.json"), "w"), ensure_ascii=False, indent=2)
    left = {name: part.get("untranslated") or part.get("error") for name, part in report.items()
            if part.get("untranslated") or part.get("error")}
    print(json.dumps(left, ensure_ascii=False, indent=2) if left else "zh_check: nothing English left")
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main())
