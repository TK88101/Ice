#!/usr/bin/env python3
"""L2 and L3 of plan 2026-11-13-zh-hant on the daily Ice, by automation only."""
import json, os, subprocess, sys, time
sys.path.insert(0, "/Users/ibridgezhao/Documents/IceReverse/docs/macos-27/probes/visibility")
import zh_check as z

CATALOG = "/Users/ibridgezhao/Documents/IceReverse/Ice/Resources/Localizable.xcstrings"
EVIDENCE = os.path.expanduser("~/IceReverse-evidence/20261113-zh")
DOMAIN = "io.github.tk88101.Ice"


def ice_pid():
    out = subprocess.run(["/usr/bin/pgrep", "-f", "/Applications/Ice.app/Contents/MacOS/Ice"], capture_output=True).stdout.split()
    return int(out[0]) if out else None


def stored():
    done = subprocess.run(["/usr/bin/defaults", "read", DOMAIN, "AppleLanguages"], capture_output=True)
    return done.stdout.decode().split() if done.returncode == 0 else None


def open_general(pid):
    subprocess.run(["/usr/bin/open", "-a", "/Applications/Ice.app"])
    rows = z.wait_rows(pid)
    for name in ("General", "一般"):
        row = next((r for r in rows if r["role"] == "AXStaticText" and r.get("value") == name and r["depth"] >= 8), None)
        if row:
            x, y, w, h = row["frame"]
            z.drive("click", x + w / 2, y + h / 2, "--expect", "pid:%d" % pid)
            time.sleep(1.2)
            return z.drive("axdump", pid)["rows"]
    raise SystemExit("no General pane")


def choose_language(pid, label):
    rows = open_general(pid)
    for i, r in enumerate(rows):
        if r["role"] == "AXStaticText" and r.get("value") in ("Language", "語言"):
            popup = next(x for x in rows[i:i + 4] if x["role"] == "AXPopUpButton")
            break
    else:
        raise SystemExit("no Language picker")
    x, y, w, h = popup["frame"]
    z.drive("click", x + w / 2, y + h / 2, "--expect", "pid:%d" % pid)
    time.sleep(0.8)
    menu = next(m for m in z.drive("windows", pid)["windows"] if m["onScreen"] and m["layer"] == 101)
    mx, my, mw, mh = menu["bounds"]
    for offset in range(6, int(mh), 4):
        hit = z.drive("hit", mx + mw / 2, my + offset)
        if hit.get("pid") == pid and hit.get("chain", [{}])[0].get("title") == label:
            z.drive("click", mx + mw / 2, my + offset, "--expect", "pid:%d" % pid)
            time.sleep(1.0)
            return
    raise SystemExit("no %s entry" % label)


def relaunch(pid):
    rows = z.drive("axdump", pid)["rows"]
    button = next(r for r in rows if r["role"] == "AXButton" and r.get("title") in ("Relaunch Ice", "重新啟動 Ice"))
    x, y, w, h = button["frame"]
    z.drive("click", x + w / 2, y + h / 2, "--expect", "pid:%d" % pid)
    deadline = time.time() + 30
    while time.time() < deadline:
        new = ice_pid()
        if new and new != pid:
            time.sleep(6)
            return new
        time.sleep(0.5)
    raise SystemExit("Ice did not relaunch")


def main():
    os.makedirs(EVIDENCE, exist_ok=True)
    log = {}
    pid = ice_pid()
    choose_language(pid, "繁體中文")
    log["stored after choosing"] = stored()
    pid = relaunch(pid)
    log["L2 pid"] = pid
    subprocess.run(["/usr/bin/osascript", "-e", 'tell application id "io.github.tk88101.Ice" to close every window'], capture_output=True)
    l2 = subprocess.run([sys.executable, "-I", z.__file__, str(pid), CATALOG, os.path.join(EVIDENCE, "l2")])
    log["L2 exit"] = l2.returncode
    choose_language(pid, "跟隨系統")
    log["stored after System"] = stored()
    pid = relaunch(pid)
    rows = open_general(pid)
    texts = set(z.texts_of(rows))
    log["L3 English"] = {w: (w in texts) for w in ("General", "Language", "System", "一般", "語言")}
    json.dump(log, open(os.path.join(EVIDENCE, "l2l3.json"), "w"), ensure_ascii=False, indent=2)
    print(json.dumps(log, ensure_ascii=False, indent=2))


main()
