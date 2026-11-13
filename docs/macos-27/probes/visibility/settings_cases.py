"""The settings pass's cases (plan 2026-11-12-settings-cleanup, sections 3 and 9).

    settings_cases.py <run> <case>...        run cases, one after another
    settings_cases.py <run> --list

Each case starts the lab copy with its settings, drives the bar, and writes
<run>/<case>.json: `pass`, `fail` (with the failed checks) or `notRun`.
"""
import base64
import json
import os
import plistlib
import subprocess
import sys
import threading
import time

from settings_lab import (
    ALL_MODS, ALL_MODS_NAMES, BAR_Y, KEY_F13, KEY_F14, KEY_F15, KEY_F16, KEY_F17,
    PARK, Failed, Lab, NotRun, drive_path, hotkey_data, is_hidden_rest, mid_x, record, uptime, verdict,
)

SCREEN_WIDTH = 1728
ESCAPE = 53


def clamped_mid(target_x, width):
    """Where a panel of that width centred on `target_x` ends up on the screen."""
    left = min(max(target_x - width / 2, 0), SCREEN_WIDTH - width)
    return left + width / 2


def near(a, b, tolerance=2.0):
    return a is not None and b is not None and abs(a - b) <= tolerance


def panel_mid(lab):
    panel = lab.panel()
    return (mid_x(panel["bounds"]), panel["bounds"][2]) if panel else (None, None)


def menu_windows(lab):
    """Ice's on-screen windows at a menu's level."""
    return [w for w in lab.windows() if w["onScreen"] and w["layer"] == 101]


# --- General -------------------------------------------------------------------------------

def g0(run):
    """Show Ice icon."""
    checks, facts = [], {}
    with Lab(run, "G0-off", {"ShowIceIcon": False}, expect_hidden=False) as lab:
        time.sleep(12)
        snapshot = lab.snapshot()
        facts["off"] = {key: snapshot.get(key) for key in ("status", "lengthApplied", "isIceBarOffered", "iconPlacement")}
        facts["off"]["roster"] = len(snapshot["roster"])
        checks.append(("off: no icon on the bar", lab.own_item("Ice.ControlItem.Visible") is None))
        checks.append(("off: the member is hidden all the same", is_hidden_rest(snapshot)))
        lab.click_empty(hold=1.0)
        checks.append(("off: a click on empty bar shows the IceBar", lab.wait_shown(True)))
    with Lab(run, "G0-on", {"ShowIceIcon": True}) as lab:
        checks.append(("on: the icon is on the bar", lab.own_item("Ice.ControlItem.Visible") is not None))
    return dict(verdict(checks), facts=facts)


def g2(run):
    """IceBar location."""
    checks, facts = [], {}
    expected = {"dynamic": ("pointer", "icon"), "pointer": ("pointer", "parked"), "icon": ("icon", "icon")}
    for value, name in ((0, "dynamic"), (1, "pointer"), (2, "icon")):
        with Lab(run, "G2-" + name, {"IceBarLocation": value}) as lab:
            icon_x = lab.icon_x()
            empty_x = lab.click_empty(hold=1.5)
            lab.wait_shown(True)
            by_click, width = panel_mid(lab)
            lab.close_bar()
            # With the pointer away from the bar: what the icon's own action shows.
            lab.wait_idle()
            process = lab.drive_started("move", PARK[0], PARK[1], "--hold", 2.5)
            time.sleep(0.8)
            lab.send("bar open")
            lab.wait_shown(True)
            by_command, width2 = panel_mid(lab)
            lab.drive_ended(process)
            lab.close_bar()
            targets = {"pointer": empty_x, "icon": icon_x, "parked": PARK[0]}
            facts[name] = {"icon": icon_x, "click": empty_x, "byClick": by_click, "byCommand": by_command, "width": width}
            first, second = expected[name]
            checks.append(("%s: opened by a click on empty bar, it is under the %s" % (name, first),
                           width is not None and near(by_click, clamped_mid(targets[first], width))))
            checks.append(("%s: opened with the pointer away, it is under the %s" % (name, second),
                           width2 is not None and near(by_command, clamped_mid(targets[second], width2))))
    return dict(verdict(checks), facts=facts)


def g3(run):
    """Show on click."""
    checks, facts = [], {}
    with Lab(run, "G3-on") as lab:
        x = lab.click_empty(hold=1.0)
        checks.append(("on: a click on empty bar shows", lab.wait_shown(True)))
        lab.click_empty(x, hold=0.5)
        checks.append(("on: a second click closes", lab.wait_shown(False)))
        other = lab.item(lab.visible_id)
        lab.click_at(mid_x(other["frame"]), other["pid"], hold=1.0)
        shown = lab.wait_shown(True, 2.0)
        facts["shownByClickOnAnotherItem"] = shown
        checks.append(("on: a click on another app's item does not show", not shown))
        lab.helper_command(0, "closemenu")
        if shown:
            lab.close_bar()
        time.sleep(0.5)
        lab.click_at(lab.icon_x(), lab.pid, hold=1.0)
        checks.append(("a click on Ice's icon shows", lab.wait_shown(True)))
        lab.close_bar()
    with Lab(run, "G3-off", {"ShowOnClick": False}) as lab:
        lab.click_empty(hold=1.0)
        checks.append(("off: a click on empty bar does not show", not lab.wait_shown(True, 2.0)))
        lab.click_at(lab.icon_x(), lab.pid, hold=1.0)
        checks.append(("off: Ice's icon still shows", lab.wait_shown(True)))
    return dict(verdict(checks), facts=facts)


def hover_time(lab, x, limit=4.0):
    """Seconds from the pointer arriving on empty bar to the panel; None when it never came."""
    lab.wait_idle()
    process = lab.drive_started("move", x, BAR_Y, "--tap", "hid", "--hold", limit)
    started = time.time()
    seen = None
    while time.time() - started < limit:
        if lab.panel() is not None:
            seen = time.time() - started
            break
        time.sleep(0.03)
    lab.drive_ended(process)
    return seen


def g4(run):
    """Show on hover, and its delay (V4)."""
    checks, facts = [], {}
    times = {}
    for delay in (0.0, 1.0):
        name = "G4-delay%d" % int(delay * 10)
        with Lab(run, name, {"ShowOnHover": True, "ShowOnClick": False, "ShowOnHoverDelay": delay}) as lab:
            lab.drive("move", PARK[0], PARK[1], "--tap", "hid")
            x = lab.empty_x()
            times[delay] = hover_time(lab, x)
            checks.append(("on, delay %.1f s: resting on empty bar shows" % delay, times[delay] is not None))
            if times[delay] is not None:
                lab.drive("move", PARK[0], PARK[1], "--tap", "hid", "--hold", 1.0)
                checks.append(("on, delay %.1f s: leaving the bar closes" % delay, lab.wait_shown(False, 4.0)))
    facts["secondsToShown"] = {str(k): v for k, v in times.items()}
    if None not in times.values():
        difference = times[1.0] - times[0.0]
        facts["delayDifference"] = difference
        checks.append(("the delay setting delays by 1 s (within 0.35)", abs(difference - 1.0) <= 0.35))
    else:
        checks.append(("the delay setting delays by 1 s (within 0.35)", False))
    with Lab(run, "G4-item", {"ShowOnHover": True, "ShowOnClick": False, "ShowOnHoverDelay": 0.0}) as lab:
        other = lab.item(lab.visible_id)
        checks.append(("on: resting on another app's item does not show", hover_time(lab, mid_x(other["frame"]), 2.5) is None))
    with Lab(run, "G4-off", {"ShowOnHover": False, "ShowOnClick": False}) as lab:
        checks.append(("off: resting on empty bar does not show", hover_time(lab, lab.empty_x(), 2.5) is None))
    return dict(verdict(checks), facts=facts)


def g5(run):
    """Show on scroll."""
    checks, facts = [], {}
    with Lab(run, "G5-on", {"ShowOnScroll": True, "ShowOnClick": False}) as lab:
        x = lab.empty_x()
        lab.drive("scroll", x, BAR_Y, 30, "--expect", "empty", "--hold", 1.0)
        up_shows = lab.wait_shown(True, 2.0)
        if not up_shows:
            lab.drive("scroll", x, BAR_Y, -30, "--expect", "empty", "--hold", 1.0)
        facts["positiveShows"] = up_shows
        checks.append(("on: a scroll on the bar shows", lab.wait_shown(True, 2.0)))
        lab.drive("scroll", x, BAR_Y, -30 if up_shows else 30, "--expect", "empty", "--hold", 1.0)
        checks.append(("on: the opposite scroll closes", lab.wait_shown(False, 2.0)))
    with Lab(run, "G5-off", {"ShowOnScroll": False, "ShowOnClick": False}) as lab:
        x = lab.empty_x()
        lab.drive("scroll", x, BAR_Y, 30, "--expect", "empty", "--hold", 1.0)
        first = lab.wait_shown(True, 1.5)
        lab.drive("scroll", x, BAR_Y, -30, "--expect", "empty", "--hold", 1.0)
        checks.append(("off: no scroll shows", not first and not lab.wait_shown(True, 1.5)))
    return dict(verdict(checks), facts=facts)


def g6(run):
    """Automatically rehide: smart, timed, focused app, off."""
    checks, facts = [], {}

    def opened(lab):
        lab.send("bar open")
        if not lab.wait_shown(True):
            raise Failed("the IceBar did not open")

    def click_front_window(lab, front):
        window = front["window"]
        lab.click_at(window[0] + window[2] / 2, front["pid"], y=window[1] + window[3] / 2, hold=0.5)

    def bring_front(lab, front):
        """A click in the pass's own window: the change of front app a person makes."""
        click_front_window(lab, front)
        time.sleep(0.8)
        return lab.front_pid() == front["pid"]

    with Lab(run, "G6-smart", {"AutoRehide": True, "RehideStrategy": 0}) as lab:
        owner_front = lab.front_pid()
        front = lab.start_front()
        try:
            # The app the owner works in is the active one: the smart rule
            # asks, a quarter of a second after the click, whether the clicked
            # window's app is active, and an app that the click itself brings
            # forward may not be yet (it was not, in one run of two).
            checks.append(("smart: the pass's own app is in front", bring_front(lab, front)))
            lab.park()
            opened(lab)
            time.sleep(2.0)
            checks.append(("smart: it stays while nothing is clicked", lab.shown()))
            click_front_window(lab, front)
            checks.append(("smart: a click in the front app's window closes it", lab.wait_shown(False, 3.0)))
        finally:
            lab.activate(owner_front)
    with Lab(run, "G6-timed", {"AutoRehide": True, "RehideStrategy": 1, "RehideInterval": 2.0}) as lab:
        lab.park()
        opened(lab)
        # The timer starts with a pointer move below the bar.
        lab.drive("move", PARK[0] + 40, PARK[1], "--hold", 0.2)
        started = time.time()
        closed = lab.wait_shown(False, 6.0)
        facts["timedSeconds"] = time.time() - started if closed else None
        checks.append(("timed, 2 s: it closes 1.5 to 4.5 s after the pointer moved off the bar",
                       closed and 1.5 <= facts["timedSeconds"] <= 4.5))
    with Lab(run, "G6-focused", {"AutoRehide": True, "RehideStrategy": 2}) as lab:
        owner_front = lab.front_pid()
        front = lab.start_front()
        try:
            time.sleep(1.0)
            lab.activate(owner_front)
            lab.park()
            before = lab.front_pid()
            opened(lab)
            time.sleep(10.0)
            checks.append(("focused app: with no change of front app it stays 10 s", lab.shown() and lab.front_pid() == before))
            checks.append(("focused app: the pass's own app comes to the front", bring_front(lab, front)))
            checks.append(("focused app: the change closes it", lab.wait_shown(False, 3.0)))
        finally:
            lab.activate(owner_front)
    with Lab(run, "G6-off", {"AutoRehide": False}) as lab:
        owner_front = lab.front_pid()
        front = lab.start_front()
        try:
            time.sleep(1.0)
            lab.activate(owner_front)
            lab.park()
            opened(lab)
            lab.drive("move", PARK[0] + 40, PARK[1], "--hold", 0.2)
            time.sleep(4.0)
            checks.append(("off: it stays after the pointer left", lab.shown()))
            checks.append(("off: the pass's own app comes to the front by a click in its window", bring_front(lab, front)))
            time.sleep(1.5)
            checks.append(("off: it stays after that click and change of front app", lab.shown()))
        finally:
            lab.activate(owner_front)
    return dict(verdict(checks), facts=facts)


# --- Advanced ------------------------------------------------------------------------------

def v3(run):
    """Secondary context menu."""
    checks, facts = [], {}

    def menu_after(lab, right=False, mods=None):
        before = len(menu_windows(lab))
        arguments = ["click", lab.empty_x(), BAR_Y, "--expect", "empty", "--hold", 1.5]
        if right:
            arguments.append("--right")
        if mods:
            arguments += ["--mods", mods]
        lab.wait_idle()
        process = lab.drive_started(*arguments)
        seen = False
        started = time.time()
        while time.time() - started < 2.5:
            if len(menu_windows(lab)) > before:
                seen = True
                break
            time.sleep(0.1)
        lab.drive_ended(process)
        if seen:
            lab.drive("key", ESCAPE)
            time.sleep(0.5)
        return seen

    with Lab(run, "V3-on", {"EnableSecondaryContextMenu": True}) as lab:
        checks.append(("on: a right-click on empty bar opens Ice's small menu", menu_after(lab, right=True)))
        checks.append(("on: a Control-click on empty bar opens it too", menu_after(lab, mods="ctrl")))
        checks.append(("on: neither showed the IceBar", not lab.shown()))
    with Lab(run, "V3-off", {"EnableSecondaryContextMenu": False}) as lab:
        checks.append(("off: a right-click opens nothing", not menu_after(lab, right=True)))
    return dict(verdict(checks), facts=facts)


def u1(run):
    """Use Ice Bar off: does anything hide?"""
    checks, facts = [], {}
    with Lab(run, "U1", {"UseIceBar": False}, expect_hidden=False) as lab:
        time.sleep(8)

        def reading(label):
            member = lab.item(lab.member_id)
            divider = lab.own_item("Ice.ControlItem.Hidden")
            frame = member["frame"] if member else None
            on_bar = bool(frame and 0 <= frame[0] and frame[0] + frame[2] <= SCREEN_WIDTH and frame[1] < 40)
            path = lab.shot("member-" + label, (frame[0] - 20, 0, frame[2] + 40, 34)) if on_bar else None
            facts[label] = {"member": frame, "divider": divider["frame"] if divider else None, "memberOnBar": on_bar, "shot": path}
            return on_bar

        hidden_at_rest = not reading("rest")
        lab.click_at(lab.icon_x(), lab.pid, hold=1.0)
        time.sleep(2.0)
        shown_after_click = reading("afterClick")
        lab.click_at(lab.icon_x(), lab.pid, hold=1.0)
        time.sleep(2.0)
        hidden_again = not reading("afterSecondClick")
        checks.append(("the member is off the bar while the section is hidden", hidden_at_rest))
        checks.append(("a click on the icon brings it back", shown_after_click))
        checks.append(("a second click hides it again", hidden_again))
    return dict(verdict(checks), facts=facts)


CASES = {"G0": g0, "G2": g2, "G3": g3, "G4": g4, "G5": g5, "G6": g6, "V3": v3, "U1": u1}


# --- Hotkeys -------------------------------------------------------------------------------

HOTKEYS = {
    "ToggleHiddenSection": KEY_F13,
    "SearchMenuBarItems": KEY_F14,
    "EnableIceBar": KEY_F15,
    "ToggleApplicationMenus": KEY_F16,
    "ToggleAlwaysHiddenSection": KEY_F17,
}


def stored_hotkeys(actions=HOTKEYS):
    return {"Hotkeys": {action: hotkey_data(code, ALL_MODS) for action, code in actions.items()}}


def press_hotkey(lab, action):
    lab.drive("key", HOTKEYS[action], "--mods", ALL_MODS_NAMES)


def titled_windows(lab):
    return [w for w in lab.windows() if w["onScreen"] and w["bounds"][2] > 100 and w["bounds"][3] > 100]


def h1(run):
    """Hotkey: toggle the hidden section."""
    checks = []
    with Lab(run, "H1", stored_hotkeys()) as lab:
        lab.park()
        press_hotkey(lab, "ToggleHiddenSection")
        checks.append(("the hotkey shows the IceBar", lab.wait_shown(True)))
        press_hotkey(lab, "ToggleHiddenSection")
        checks.append(("again: it closes", lab.wait_shown(False)))
    return dict(verdict(checks), facts={})


def h3(run):
    """Hotkey: search menu bar items; and a click on a result (known dead)."""
    checks, facts = [], {}
    with Lab(run, "H3", stored_hotkeys()) as lab:
        owner_front = lab.front_pid()
        try:
            before = len(titled_windows(lab))
            press_hotkey(lab, "SearchMenuBarItems")
            time.sleep(1.5)
            panels = titled_windows(lab)
            checks.append(("the hotkey opens the search panel", len(panels) > before))
            if len(panels) > before:
                panel = max(panels, key=lambda w: w["bounds"][2] * w["bounds"][3])["bounds"]
                centre = (panel[0] + panel[2] / 2, panel[1] + panel[3] / 2)

                def member_row():
                    """The member's result when it is inside the list's visible part."""
                    rows = lab.rows()
                    areas = [row["frame"] for row in rows if row["role"] == "AXScrollArea"]
                    for row in rows:
                        if row["role"] == "AXStaticText" and row.get("value") == "Target" and areas:
                            frame, area = row["frame"], areas[0]
                            if area[1] <= frame[1] and frame[1] + frame[3] <= area[1] + area[3]:
                                return frame
                    return None

                frame = member_row()
                for _ in range(6):
                    if frame is not None:
                        break
                    lab.drive("scroll", centre[0], centre[1], -60, "--expect", "pid:%d" % lab.pid, "--hold", 0.3)
                    time.sleep(0.5)
                    frame = member_row()
                checks.append(("the member is listed in the panel", frame is not None))
                if frame is not None:
                    lab.click_at(frame[0] + frame[2] / 2, lab.pid, y=frame[1] + frame[3] / 2, hold=0.3)
                    time.sleep(2.0)
                    member = lab.item(lab.member_id)
                    menus = [w for w in lab.read("windows", member["pid"])["windows"] if w["onScreen"] and w["layer"] == 101]
                    facts["memberMenuOpenedByClick"] = bool(menus)
                    checks.append(("a click on the member's result opens its menu", bool(menus)))
                    lab.helper_command(1, "closemenu")
                lab.drive("key", ESCAPE)
        finally:
            lab.activate(owner_front)
    return dict(verdict(checks), facts=facts)


def h4(run):
    """Hotkey: enable the Ice Bar (toggles the setting)."""
    checks, facts = [], {}
    with Lab(run, "H4", stored_hotkeys()) as lab:
        facts["before"] = lab.default("UseIceBar")
        press_hotkey(lab, "EnableIceBar")
        time.sleep(1.5)
        facts["after"] = lab.default("UseIceBar")
        checks.append(("the hotkey turns Use Ice Bar off", facts["before"] == "1" and facts["after"] == "0"))
        press_hotkey(lab, "EnableIceBar")
        time.sleep(1.5)
        facts["again"] = lab.default("UseIceBar")
        checks.append(("again: on", facts["again"] == "1"))
    return dict(verdict(checks), facts=facts)


def h5(run):
    """Hotkey: toggle application menus."""
    checks, facts = [], {}

    def menus(lab):
        read = lab.read("menus")
        return {"owner": read["owner"], "titles": len(read["titles"])}

    with Lab(run, "H5", stored_hotkeys()) as lab:
        owner_front = lab.front_pid()
        front = lab.start_front()
        try:
            window = front["window"]
            lab.click_at(window[0] + window[2] / 2, front["pid"], y=window[1] + window[3] / 2, hold=0.3)
            time.sleep(1.0)
            facts["before"] = menus(lab)
            press_hotkey(lab, "ToggleApplicationMenus")
            time.sleep(2.0)
            facts["hidden"] = menus(lab)
            checks.append(("the hotkey takes the front app's menu titles off the bar",
                           facts["hidden"]["owner"] == lab.state["ice_id"] and facts["hidden"]["titles"] < facts["before"]["titles"]))
            press_hotkey(lab, "ToggleApplicationMenus")
            time.sleep(2.0)
            facts["back"] = menus(lab)
            checks.append(("again: they are back", facts["back"] == facts["before"]))
        finally:
            lab.activate(owner_front)
    return dict(verdict(checks), facts=facts)


CASES.update({"H1": h1, "H3": h3, "H4": h4, "H5": h5})


# --- The IceBar itself, and arranging -------------------------------------------------------

def b1(run):
    """A click on a cell of the IceBar opens that item's menu (the positive control for H3)."""
    checks = []
    with Lab(run, "B1") as lab:
        lab.park()
        lab.send("bar open")
        checks.append(("the IceBar opens", lab.wait_shown(True)))
        panel = lab.panel()["bounds"]
        member = lab.item(lab.member_id)
        lab.click_at(panel[0] + panel[2] / 2, lab.pid, y=panel[1] + panel[3] / 2, hold=0.3)
        time.sleep(1.5)
        checks.append(("a click on the member's cell opens its menu", lab.menu_open(member["pid"])))
        lab.helper_command(1, "closemenu")
    return dict(verdict(checks), facts={})


def divider_frame(lab):
    """The hidden divider at standard length, as Ice's last pass read it."""
    return lab.snapshot()["hiddenDivider"]["frame"]


def d1(run):
    """Hold Command on the bar: the hidden items come back; let go: hidden again; take one out."""
    checks, facts = [], {}
    with Lab(run, "D1") as lab:
        member = lab.item(lab.member_id)
        point = (mid_x(member["frame"]), BAR_Y)

        def owner_at_member():
            return lab.read("hit", point[0], point[1]).get("pid")

        # Not by pixels: on the owner's bar a notch app's overlay covers that
        # stretch. By who answers there: Ice's spacer while hidden, the member
        # itself when it is back.
        facts["hitWhileHidden"] = "member" if owner_at_member() == member["pid"] else "other"
        lab.wait_idle()
        process = lab.drive_started("command", lab.empty_x(), BAR_Y, 3.5)
        retired = lab.holds(lambda s: not s["lengthApplied"], 2.5)
        time.sleep(0.8)
        facts["hitWhileCommand"] = "member" if owner_at_member() == member["pid"] else "other"
        lab.drive_ended(process)
        checks.append(("while Command is held on the bar the length is given back", retired))
        checks.append(("and the member is back on the bar (it answers at its place; hidden, it did not)",
                       facts["hitWhileHidden"] == "other" and facts["hitWhileCommand"] == "member"))
        checks.append(("3 s after Command is let go it is hidden again, the roster unchanged", lab.holds(is_hidden_rest, 4.0)))
        # Take it out: Command down, wait for the members, drag it right of the divider.
        divider = divider_frame(lab)
        other = lab.item(lab.visible_id)
        drop_x = (mid_x(divider) + mid_x(other["frame"])) / 2
        facts["takeOut"] = {"from": mid_x(member["frame"]), "to": drop_x}
        lab.drive("drag", mid_x(member["frame"]), BAR_Y, drop_x, BAR_Y, "--expect", "pid:%d" % member["pid"],
                  "--command-first", 1.6, "--seconds", 0.8)
        checks.append(("dragged right of the divider, it leaves the roster", lab.holds(lambda s: len(s["roster"]) == 0, 8.0)))
        after = lab.item(lab.member_id)
        facts["after"] = after["frame"]
        checks.append(("and stands right of the divider", after["frame"][0] > divider_frame(lab)[0]))
    return dict(verdict(checks), facts=facts)


def d2(run, cycles=10):
    """A quick drag into the hidden section is never lost; a slow one takes it out again."""
    checks, facts = [], {"cycles": []}
    with Lab(run, "D2", fresh_visible=True) as lab:
        origin = lab.report_origin()
        moved = lab.item(lab.visible_id)
        for index in range(cycles):
            cycle = {}
            divider = divider_frame(lab)
            now = lab.item(lab.visible_id)["frame"]
            seen = len(lab.events())
            # Quick, at a random phase of Ice's one-second sampling.
            time.sleep((index * 0.37) % 1.0)
            result = lab.drive("drag", mid_x(now), BAR_Y, divider[0] - 8, BAR_Y, "--expect", "pid:%d" % moved["pid"],
                               "--command-first", 0.12, "--seconds", 0.25)
            started, ended = result["postedAt"] - origin, result["endedAt"] - origin
            cycle["dragSeconds"] = ended - started
            hidden = lab.holds(lambda s: is_hidden_rest(s, 2), 6.0)
            events = lab.events()[seen:]
            retires = [e["t"] for e in events if e["event"] == "length" and e.get("applied") is None]
            gains = [e["t"] for e in events if e["event"] == "roster" and len(e["members"]) == 2]
            cycle["retireAfterStart"] = retires[0] - started if retires else None
            cycle["rosterGainAfterEnd"] = gains[0] - ended if gains else None
            cycle["hiddenWithBoth"] = hidden
            cycle["cells"] = len(lab.snapshot()["cells"])
            # Out again, slowly, as a person takes one out.
            divider = divider_frame(lab)
            member = lab.item(lab.member_id)["frame"]
            hidden_item = lab.item(lab.visible_id)["frame"]
            lab.drive("drag", mid_x(hidden_item), BAR_Y, divider[0] + divider[2] + 14, BAR_Y, "--expect", "pid:%d" % moved["pid"],
                      "--command-first", 1.6, "--seconds", 0.8)
            cycle["takenOut"] = lab.holds(lambda s: is_hidden_rest(s, 1), 8.0)
            cycle["memberFrame"] = member
            facts["cycles"].append(cycle)
            if not cycle["takenOut"]:
                break
        done = facts["cycles"]
        checks.append(("%d cycles ran" % cycles, len(done) == cycles and all(c["takenOut"] for c in done)))
        checks.append(("every quick drag was followed by a retire within 1.2 s of its start",
                       all(c["retireAfterStart"] is not None and c["retireAfterStart"] <= 1.2 for c in done)))
        checks.append(("every dropped item joined the roster and the IceBar within 6 s",
                       all(c["hiddenWithBoth"] and c["cells"] == 2 for c in done)))
    return dict(verdict(checks), facts=facts)


def v15(run):
    """Divider style (V1) and showing the sections while dragging (V5): what a drag shows."""
    checks, facts = [], {}
    for style, style_name in ((0, "none"), (1, "chevron")):
        for show_all in (True, False):
            name = "V15-%s-%s" % (style_name, "all" if show_all else "notall")
            with Lab(run, name, {"SectionDividerStyle": style, "ShowAllSectionsOnUserDrag": show_all}) as lab:
                other = lab.item(lab.visible_id)
                x = mid_x(other["frame"])
                divider = divider_frame(lab)
                region = (divider[0] - 30, 2, 90, 28)
                rest = lab.shot("rest", region)
                lab.wait_idle()
                process = lab.drive_started("drag", x, BAR_Y, x + 5, BAR_Y, "--expect", "pid:%d" % other["pid"],
                                            "--pause", 2.5, "--return", "--seconds", 0.3)
                time.sleep(1.8)
                own = lab.own_item("Ice.ControlItem.Hidden")
                dragging = lab.shot("dragging", region)
                lab.drive_ended(process)
                facts[name] = {
                    "dividerWhileDragging": own["frame"] if own else None,
                    "rest": lab.read("mean", rest)["mean"],
                    "dragging": lab.read("mean", dragging)["mean"],
                    "shots": [rest, dragging],
                }
                checks.append(("%s: afterwards the member is hidden again" % name, lab.holds(is_hidden_rest, 6.0)))
    widths = {name: (value["dividerWhileDragging"] or [0, 0, None])[2] for name, value in facts.items()}
    facts["widths"] = widths
    checks.append(("the two styles differ while dragging (show all on)", widths["V15-none-all"] != widths["V15-chevron-all"]))
    checks.append(("show all on and off differ while dragging (style none)", widths["V15-none-all"] != widths["V15-none-notall"]))
    return dict(verdict(checks), facts=facts)


CASES.update({"B1": b1, "D1": d1, "D2": d2, "V15": v15})


# --- Menu Bar Appearance --------------------------------------------------------------------

def srgb_profile():
    import os
    with open(os.path.expanduser(os.environ.get("S6_SRGB", "~/.cache/icereverse-s6/srgb.icc.b64"))) as handle:
        return handle.read().strip()


def colour(red, green, blue, alpha=1.0):
    """An IceColor as Ice stores it."""
    return {"components": [red, green, blue, alpha], "colorSpace": srgb_profile()}


def partial(tint=None, gradient=None, border=None, border_width=1.0, shadow=False):
    stops = [{"color": colour(*c), "location": l} for c, l in (gradient or [((0, 0, 0), 0.0), ((0, 0, 0), 1.0)])]
    return {
        "hasShadow": shadow,
        "hasBorder": border is not None,
        "borderColor": colour(*(border or (0, 0, 0))),
        "borderWidth": border_width,
        "tintKind": 2 if gradient else (1 if tint else 0),
        "tintColor": colour(*(tint or (0, 0, 0))),
        "tintGradient": {"stops": stops},
    }


ROUND, SQUARE = 1, 0


def appearance(static=None, shape=0, inset=True, dynamic=False, light=None, dark=None, caps=(ROUND, ROUND)):
    full = {"leadingEndCap": caps[0], "trailingEndCap": caps[1]}
    configuration = {
        "lightModeConfiguration": light or partial(),
        "darkModeConfiguration": dark or partial(),
        "staticConfiguration": static or partial(),
        "shapeKind": shape,
        "fullShapeInfo": full,
        "splitShapeInfo": {"leading": full, "trailing": full},
        "isInset": inset,
        "isDynamic": dynamic,
    }
    return {"MenuBarAppearanceConfigurationV2": json.dumps(configuration).encode()}


RED, GREEN, BLUE = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)
# Regions of the screen, in points: over the front app's menus; the stretch
# between the menus and the notch; the bar's top rows; its bottom rows; just
# under the bar; the bar's first corner.
REGIONS = {
    "menus": (60, 8, 240, 16),
    "middle": (480, 8, 200, 16),
    "top": (480, 0, 200, 2),
    "bottom": (480, 29, 200, 4),
    # With the inset a shape's lower edge is 3.5 pt above the bar's.
    "edge": (480, 22, 200, 10),
    "under": (480, 33, 200, 4),
    "corner": (0, 0, 4, 4),
}


def bar_colours(run, name, settings):
    """The mean colour of each region with Ice running under those settings."""
    with Lab(run, name, settings, member=False) as lab:
        time.sleep(5.0)
        colours = {}
        for region, rect in REGIONS.items():
            colours[region] = lab.read("mean", lab.shot(region, rect))["mean"][:3]
        colours["panels"] = len([w for w in lab.windows() if w["onScreen"] and w["bounds"][2] >= SCREEN_WIDTH - 2 and w["bounds"][3] < 100])
        return colours


def shift(colours, base, region):
    """How far a region's colour moved from the untouched bar's, per channel."""
    return [round(a - b, 1) for a, b in zip(colours[region], base[region])]


def dominant(delta, channel, margin=8.0):
    """That channel rose by `margin` more than each of the others."""
    return all(delta[channel] - delta[other] >= margin for other in range(3) if other != channel)


def a_all(run):
    """Tint, shape, border, shadow, inset, dynamic: the bar's pixels under each."""
    checks, facts = [], {}
    base = bar_colours(run, "A0-none", {})
    facts["none"] = base
    checks.append(("nothing configured: no overlay panel", base["panels"] == 0))

    def measured(name, settings):
        colours = bar_colours(run, name, settings)
        facts[name] = {region: shift(colours, base, region) for region in REGIONS}
        facts[name]["panels"] = colours["panels"]
        return facts[name]

    solid = measured("A1-solid", appearance(partial(tint=RED)))
    checks.append(("solid tint: an overlay panel is up", solid["panels"] >= 1))
    checks.append(("solid tint: the bar turns toward the tint, menus and middle alike",
                   dominant(solid["menus"], 0) and dominant(solid["middle"], 0)))
    gradient = measured("A1-gradient", appearance(partial(gradient=[(BLUE, 0.0), (GREEN, 1.0)])))
    checks.append(("gradient tint: its first colour leads at the bar's start", dominant(gradient["menus"], 2, 4.0)))
    full = measured("A2-full", appearance(partial(tint=RED), shape=1))
    checks.append(("full shape, round caps: tinted inside, the corner outside it is not",
                   dominant(full["middle"], 0) and not dominant(full["corner"], 0)))
    split = measured("A2-split", appearance(partial(tint=RED), shape=2))
    # On macOS 27 a split shape was drawn exactly as the full one (run
    # 20261112-200049-s6), so it is not offered and a stored one is the full.
    facts["splitDrawnAsFull"] = all(abs(a - b) <= 1.0 for region in REGIONS for a, b in zip(split[region], full[region]))
    checks.append(("a stored split shape is drawn as the full one", facts["splitDrawnAsFull"]))
    flush = measured("A6-notinset", appearance(partial(tint=RED), shape=1, inset=False))
    square = measured("A9-square", appearance(partial(tint=RED), shape=1, inset=False, caps=(SQUARE, SQUARE)))
    checks.append(("end caps: square ones tint the bar's corner, round ones do not",
                   dominant(square["corner"], 0) and not dominant(flush["corner"], 0)))
    checks.append(("inset: the bar's top rows are tinted without it and not with it",
                   dominant(flush["top"], 0) and not dominant(full["top"], 0)))
    thin = measured("A3-border1", appearance(partial(border=GREEN, border_width=1.0), shape=1))
    thick = measured("A7-border3", appearance(partial(border=GREEN, border_width=3.0), shape=1))
    checks.append(("border: its colour is on the bar's bottom rows, not in its middle",
                   dominant(thick["bottom"], 1) and not dominant(thick["middle"], 1)))
    checks.append(("border width: 3 pt puts more of it there than 1 pt", thick["edge"][1] > thin["edge"][1] + 5))
    blue = measured("A7-borderblue", appearance(partial(border=BLUE, border_width=3.0), shape=1))
    checks.append(("border colour: another colour is drawn as that colour", dominant(blue["bottom"], 2)))
    # A pair of launches one after the other: what is under the bar's edge is
    # the window below it, which changes over minutes.
    plain = bar_colours(run, "A4-noshadow", {})
    shadowed = bar_colours(run, "A4-shadow", appearance(partial(shadow=True)))
    facts["A4-shadow"] = {"under": shift(shadowed, plain, "under"), "panels": shadowed["panels"]}
    checks.append(("shadow: the rows under the bar are darker than without it", sum(facts["A4-shadow"]["under"]) < -6))
    dynamic = measured("A5-dynamic", appearance(dynamic=True, light=partial(tint=GREEN), dark=partial(tint=BLUE)))
    import subprocess
    dark = subprocess.run(["/usr/bin/defaults", "read", "-g", "AppleInterfaceStyle"], capture_output=True).stdout.decode().strip() == "Dark"
    facts["systemIsDark"] = dark
    checks.append(("dynamic: the value for the system's appearance is the one drawn", dominant(dynamic["middle"], 2 if dark else 1)))
    return dict(verdict(checks), facts=facts)


CASES.update({"A": a_all})


# --- Through the settings window ------------------------------------------------------------

def checkbox_value(lab, label):
    row = lab.control_after(label, "AXCheckBox")
    return None if row is None else int(row.get("value", -1))


def g1(run):
    """Launch at login: the system takes the registration and gives it up again."""
    checks, facts = [], {}
    try:
        with Lab(run, "G1-on", {}, member=False) as lab:
            owner_front = lab.front_pid()
            try:
                lab.open_settings()
                facts["atStart"] = checkbox_value(lab, "Launch at login")
                lab.click_row(lab.control_after("Launch at login", "AXCheckBox"))
                time.sleep(2.0)
                facts["afterClick"] = checkbox_value(lab, "Launch at login")
                checks.append(("the toggle goes on", facts["atStart"] == 0 and facts["afterClick"] == 1))
            finally:
                lab.activate(owner_front)
        with Lab(run, "G1-relaunched", {}, member=False) as lab:
            owner_front = lab.front_pid()
            try:
                lab.open_settings()
                facts["afterRelaunch"] = checkbox_value(lab, "Launch at login")
                checks.append(("after Ice is started again the system still says on", facts["afterRelaunch"] == 1))
            finally:
                lab.activate(owner_front)
    finally:
        # Whatever happened above, the registration is given up.
        with Lab(run, "G1-off", {}, member=False) as lab:
            owner_front = lab.front_pid()
            try:
                lab.open_settings()
                if checkbox_value(lab, "Launch at login") == 1:
                    lab.click_row(lab.control_after("Launch at login", "AXCheckBox"))
                    time.sleep(2.0)
                facts["atEnd"] = checkbox_value(lab, "Launch at login")
                checks.append(("switched off, the system says off", facts["atEnd"] == 0))
            finally:
                lab.activate(owner_front)
    return dict(verdict(checks), facts=facts)


def h6(run):
    """The hotkey recorder: a combination pressed into it is stored and fires."""
    checks, facts = [], {}
    with Lab(run, "H6") as lab:
        owner_front = lab.front_pid()
        try:
            rows = lab.select_pane("Hotkeys") if lab.open_settings() else None
            lab.click_row(lab.control_after("Toggle the hidden section", "AXButton", rows))
            time.sleep(0.8)
            lab.drive("key", KEY_F13, "--mods", ALL_MODS_NAMES)
            time.sleep(1.5)
            stored = lab.default("Hotkeys") or ""
            facts["stored"] = "ToggleHiddenSection" in stored and "5b3130352c31355d" in stored.replace(" ", "")
            checks.append(("the pressed combination is stored for the action", facts["stored"]))
            facts["recorderShows"] = [text for text in lab.texts() if "F13" in text][:2]
        finally:
            lab.activate(owner_front)
        lab.park()
        press_hotkey(lab, "ToggleHiddenSection")
        checks.append(("and it shows the IceBar", lab.wait_shown(True)))
    return dict(verdict(checks), facts=facts)


def a8(run):
    """The appearance editor's reset."""
    checks, facts = [], {}
    with Lab(run, "A8", appearance(partial(tint=RED), shape=1), member=False) as lab:
        owner_front = lab.front_pid()
        try:
            lab.open_settings()
            rows = lab.select_pane("Menu Bar Appearance")
            facts["tintBefore"] = (lab.control_after("Tint", "AXPopUpButton", rows) or {}).get("value")
            resets = [row for row in rows if row["role"] == "AXButton" and "Reset" in (row.get("title", "") + row.get("description", ""))]
            facts["resetButtons"] = len(resets)
            checks.append(("the pane shows the stored tint and a reset", facts["tintBefore"] == "Solid" and len(resets) >= 1))
            if resets:
                lab.click_row(resets[0])
                time.sleep(1.5)
                # It asks first: the alert's own Reset is the one that was not there before.
                before = {tuple(row["frame"]) for row in resets}
                confirm = [row for row in lab.rows() if row["role"] == "AXButton" and "frame" in row
                           and "Reset" in (row.get("title", "") + row.get("description", "")) and tuple(row["frame"]) not in before]
                facts["asksFirst"] = len(confirm) >= 1
                if confirm:
                    lab.click_row(confirm[0])
                    time.sleep(1.5)
                rows = lab.rows()
                facts["tintAfter"] = (lab.control_after("Tint", "AXPopUpButton", rows) or {}).get("value")
                facts["shapeAfter"] = (lab.control_after("Shape Kind", "AXPopUpButton", rows) or {}).get("value")
                checks.append(("after it the tint and the shape are none", facts["tintAfter"] == "None" and facts["shapeAfter"] == "None"))
        finally:
            lab.activate(owner_front)
    return dict(verdict(checks), facts=facts)


def red_png(side=36):
    """A plain red square as PNG bytes."""
    import struct
    import zlib

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    row = b"\x00" + b"\xff\x00\x00\xff" * side
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", side, side, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * side)) + chunk(b"IEND", b""))


def g0b(run):
    """A custom icon, as itself and as a template."""
    import base64
    checks, facts = [], {}
    image = {"data": {"_0": base64.b64encode(red_png()).decode()}}
    icon = json.dumps({"name": "Custom", "hidden": image, "visible": image}).encode()
    for template in (False, True):
        name = "G0b-template" if template else "G0b-colour"
        with Lab(run, name, {"IceIcon": icon, "CustomIceIconIsTemplate": template}, member=False) as lab:
            time.sleep(3.0)
            own = lab.own_item("Ice.ControlItem.Visible")
            frame = own["frame"]
            mean = lab.read("mean", lab.shot("icon", (frame[0], frame[1], frame[2], frame[3])))["mean"][:3]
            facts[name] = {"frame": frame, "mean": mean}
    colour_mean, template_mean = facts["G0b-colour"]["mean"], facts["G0b-template"]["mean"]
    checks.append(("as itself the icon is drawn in its own colour (red over blue)", colour_mean[0] - colour_mean[2] > 40))
    checks.append(("as a template it is not", abs(template_mean[0] - template_mean[2]) < 25))
    checks.append(("and the two differ", max(abs(a - b) for a, b in zip(colour_mean, template_mean)) > 15))
    return dict(verdict(checks), facts=facts)


CASES.update({"G1": g1, "H6": h6, "A8": a8, "G0b": g0b})


# --- The cut build: what is left, what is gone ------------------------------------------------

PANES = {
    "General": {
        "present": ["Launch at login", "Ice icon", "Location", "Show on click", "Show on hover", "Show on scroll", "Automatically rehide"],
        "absent": ["Show Ice icon", "Use Ice Bar", "Menu bar item spacing", "Apply"],
    },
    "Menu Bar Appearance": {
        "present": ["Use dynamic appearance", "Tint", "Shadow", "Border", "Shape Kind"],
        "absent": [],
    },
    "Hotkeys": {
        "present": ["Toggle the hidden section", "Toggle application menus"],
        "absent": ["Search menu bar items", "Enable the Ice Bar", "Toggle the always-hidden section", "Menu Bar Items"],
    },
    "Advanced": {
        "present": ["Enable secondary context menu", "Show on hover delay", "Permissions"],
        "absent": ["Enable the always-hidden section", "Show all sections when ⌘ Command + dragging menu bar items",
                   "Section divider style", "Hide app menus when showing menu bar items", "Temporarily shown item delay",
                   "Menu Bar Sections"],
    },
    "About": {"present": ["Version 1.0", "Acknowledgements", "Quit Ice"], "absent": ["Check for Updates", "Contribute", "Report a Bug", "Support Ice"]},
}


def t6_panes(run):
    """Every pane of the settings window: exactly what is offered on macOS 27."""
    checks, facts = [], {}
    stored = dict(appearance(partial(tint=RED), shape=2))
    with Lab(run, "T6-panes", stored, member=False) as lab:
        owner_front = lab.front_pid()
        try:
            rows = lab.open_settings()
            sidebar = [row.get("value") for row in rows if row["role"] == "AXStaticText" and row["depth"] >= 8]
            facts["sidebar"] = sidebar
            checks.append(("the sidebar has the five panes and no layout pane",
                           sidebar == ["General", "Menu Bar Appearance", "Hotkeys", "Advanced", "About"]))
            for pane, expected in PANES.items():
                rows = lab.select_pane(pane)
                texts = [text for row in rows if row["depth"] < 8 for text in lab.texts([row])]
                missing = [text for text in expected["present"] if text not in texts]
                extra = [text for text in expected["absent"] if text in texts]
                facts[pane] = {"missing": missing, "extra": extra}
                checks.append(("%s: what is offered is there" % pane, not missing))
                checks.append(("%s: what is not offered is not" % pane, not extra))
                if pane == "Menu Bar Appearance":
                    shape = (lab.control_after("Shape Kind", "AXPopUpButton", rows) or {}).get("value")
                    facts["storedSplitShownAs"] = shape
                    checks.append(("a stored split shape is shown as Full", shape == "Full"))
        finally:
            lab.activate(owner_front)
    return dict(verdict(checks), facts=facts)


def t6_menus(run):
    """Ice's own menu and the secondary menu: their entries, and that they do what they say."""
    checks, facts = [], {}
    with Lab(run, "T6-menus", {"EnableSecondaryContextMenu": True}) as lab:
        owner_front = lab.front_pid()
        try:
            lab.click_at(lab.icon_x(), lab.pid, right=True, hold=0.4)
            time.sleep(0.8)
            menus = lab.open_menus()
            entries = [title for title, _ in lab.menu_entries(menus[0])] if menus else []
            facts["iconMenu"] = entries
            checks.append(("the icon's menu: settings, show the hidden section, quit; no search",
                           entries == ["Ice Settings…", "Show Hidden Section", "Quit Ice"]))
            if menus and lab.choose(menus[0], "Show Hidden Section"):
                checks.append(("Show Hidden Section shows the IceBar", lab.wait_shown(True)))
                lab.close_bar()
            menu = lab.open_secondary_menu()
            facts["secondaryMenu"] = [title for title, _ in lab.menu_entries(menu)]
            before = len(titled_windows(lab))
            checks.append(("the secondary menu has the appearance editor and the settings",
                           facts["secondaryMenu"] == ["Edit Menu Bar Appearance…", "Ice Settings…"]))
            if lab.choose(menu, "Edit Menu Bar Appearance…"):
                time.sleep(1.5)
                checks.append(("Edit Menu Bar Appearance… opens the editor", len(titled_windows(lab)) > before))
        finally:
            lab.activate(owner_front)
    return dict(verdict(checks), facts=facts)


def t6_removed(run):
    """Every removed setting stored at its old value, every removed hotkey stored: none has an effect."""
    checks, facts = [], {}
    stored = {
        "ShowIceIcon": False, "UseIceBar": False, "EnableAlwaysHiddenSection": True, "SectionDividerStyle": 1,
        "ShowAllSectionsOnUserDrag": False, "HideApplicationMenus": True, "ItemSpacingOffset": 8.0, "TempShowInterval": 3.0,
    }
    stored.update(stored_hotkeys())
    with Lab(run, "T6-removed", stored) as lab:
        # Reaching here means the member was hidden: IceBar mode is in effect with "Use Ice Bar" stored off.
        checks.append(("Use Ice Bar stored off: the member is hidden all the same", is_hidden_rest(lab.snapshot())))
        checks.append(("Show Ice icon stored off: the icon is on the bar", lab.own_item("Ice.ControlItem.Visible") is not None))
        checks.append(("the always-hidden section stored on: no divider of it", lab.own_item("Ice.ControlItem.AlwaysHidden") is None))
        # Not the divider style: on a domain that never ran Ice, Ice's own
        # migration writes that key at launch, on every system.
        facts["storedAfterLaunch"] = {key: lab.default(key) for key in ("UseIceBar", "ShowIceIcon", "EnableAlwaysHiddenSection", "ShowAllSectionsOnUserDrag")}
        checks.append(("what was stored for them is left as it was",
                       facts["storedAfterLaunch"] == {"UseIceBar": "0", "ShowIceIcon": "0", "EnableAlwaysHiddenSection": "1", "ShowAllSectionsOnUserDrag": "0"}))
        lab.park()
        before = len(titled_windows(lab))
        press_hotkey(lab, "SearchMenuBarItems")
        time.sleep(1.5)
        checks.append(("the search hotkey, stored: no panel", len(titled_windows(lab)) == before))
        press_hotkey(lab, "EnableIceBar")
        time.sleep(1.5)
        checks.append(("the Ice Bar hotkey, stored: the member stays hidden", is_hidden_rest(lab.snapshot())))
        press_hotkey(lab, "ToggleAlwaysHiddenSection")
        checks.append(("the always-hidden hotkey, stored: nothing shown", not lab.wait_shown(True, 1.5)))
        press_hotkey(lab, "ToggleHiddenSection")
        checks.append(("the hidden section's hotkey, kept: it shows the IceBar", lab.wait_shown(True)))
        lab.close_bar()
        owner_front = lab.front_pid()
        front = lab.start_front()
        try:
            window = front["window"]
            other = lab.item(lab.visible_id)
            x = mid_x(other["frame"])
            lab.wait_idle()
            process = lab.drive_started("drag", x, BAR_Y, x + 5, BAR_Y, "--expect", "pid:%d" % other["pid"],
                                        "--pause", 5.0, "--return", "--seconds", 0.3)
            # The press comes a second or more after the start (the driver
            # first proves whose item is under the point): the divider is read
            # until it changes or the pause is nearly over.
            deadline = time.time() + 4.0
            divider = lab.own_item("Ice.ControlItem.Hidden")
            while time.time() < deadline and divider and divider["frame"][2] == 18:
                time.sleep(0.2)
                divider = lab.own_item("Ice.ControlItem.Hidden")
            lab.drive_ended(process)
            facts["dividerWhileDragging"] = divider["frame"] if divider else None
            checks.append(("divider style and show-all stored at their other values: a drag shows the divider as with the defaults (5 pt)",
                           bool(divider) and divider["frame"][2] == 5))
            lab.holds(is_hidden_rest, 6.0)
            titles = lab.read("menus")
            lab.send("bar open")
            lab.wait_shown(True)
            time.sleep(1.5)
            checks.append(("Hide app menus stored on: showing the IceBar leaves the front app's menus",
                           lab.read("menus")["owner"] == titles["owner"] and len(lab.read("menus")["titles"]) == len(titles["titles"])))
            lab.close_bar()
            del window
        finally:
            lab.activate(owner_front)
    return dict(verdict(checks), facts=facts)


def c1(run):
    """Every kept setting away from its default at once."""
    checks, facts = [], {}
    settings = {
        "ShowOnHover": True, "ShowOnScroll": True, "ShowOnClick": True, "IceBarLocation": 1, "AutoRehide": True,
        "RehideStrategy": 1, "RehideInterval": 3.0, "EnableSecondaryContextMenu": False, "ShowOnHoverDelay": 0.5,
    }
    settings.update(stored_hotkeys({"ToggleHiddenSection": KEY_F13}))
    settings.update(appearance(partial(tint=BLUE, border=GREEN, border_width=2.0, shadow=True), shape=1))
    with Lab(run, "C1", settings) as lab:
        lab.drive("move", PARK[0], PARK[1], "--tap", "hid")
        x = lab.empty_x()
        seen = hover_time(lab, x, 3.0)
        facts["hoverSeconds"] = seen
        checks.append(("hover shows it, after the delay", seen is not None and 0.3 <= seen <= 1.2))
        middle, width = panel_mid(lab)
        checks.append(("under the pointer", width is not None and near(middle, clamped_mid(x, width))))
        lab.drive("move", PARK[0], PARK[1], "--tap", "hid", "--hold", 0.5)
        checks.append(("leaving closes it", lab.wait_shown(False, 5.0)))
        lab.click_empty(x, hold=0.6)
        checks.append(("a click shows it", lab.wait_shown(True)))
        lab.click_empty(x, hold=0.3)
        checks.append(("a click closes it", lab.wait_shown(False)))
        lab.park()
        press_hotkey(lab, "ToggleHiddenSection")
        checks.append(("the hotkey shows it", lab.wait_shown(True)))
        lab.drive("move", PARK[0] + 40, PARK[1], "--hold", 0.2)
        started = time.time()
        closed = lab.wait_shown(False, 7.0)
        facts["timedSeconds"] = time.time() - started if closed else None
        checks.append(("the timed rehide closes it after its 3 s", closed and 2.0 <= facts["timedSeconds"] <= 6.0))
        before = len(lab.open_menus())
        lab.click_empty(x, right=True, hold=1.0)
        checks.append(("the secondary menu, off, stays away", len(lab.open_menus()) == before))
        colours = lab.read("mean", lab.shot("middle", REGIONS["middle"]))["mean"][:3]
        facts["bar"] = colours
        checks.append(("and the bar is tinted", colours[2] > colours[1] + 20))
    return dict(verdict(checks), facts=facts)


def p1(run):
    """Settings changed in the window are stored and in effect after Ice is started again."""
    checks, facts = [], {}
    with Lab(run, "P1-set", {"ShowOnHover": False, "ShowOnClick": True}) as lab:
        owner_front = lab.front_pid()
        try:
            lab.open_settings()
            lab.click_row(lab.control_after("Show on hover", "AXCheckBox"))
            lab.click_row(lab.control_after("Show on click", "AXCheckBox"))
            time.sleep(1.0)
            facts["inWindow"] = [checkbox_value(lab, "Show on hover"), checkbox_value(lab, "Show on click")]
            checks.append(("the two switches change in the window", facts["inWindow"] == [1, 0]))
        finally:
            lab.activate(owner_front)
    with Lab(run, "P1-again", keep_settings=True) as lab:
        facts["stored"] = [lab.default("ShowOnHover"), lab.default("ShowOnClick")]
        checks.append(("both are stored", facts["stored"] == ["1", "0"]))
        lab.click_empty(hold=0.8)
        checks.append(("show on click, off: a click shows nothing", not lab.wait_shown(True, 2.0)))
        lab.drive("move", PARK[0], PARK[1], "--tap", "hid")
        checks.append(("show on hover, on: resting on the bar shows the IceBar", hover_time(lab, lab.empty_x(), 3.0) is not None))
    return dict(verdict(checks), facts=facts)


CASES.update({"T6-panes": t6_panes, "T6-menus": t6_menus, "T6-removed": t6_removed, "C1": c1, "P1": p1})


# --- The limits left by the settings pass (plan 2026-11-13-untested-limits) ------------------

RETURN = 36
KEY_G = 5
# The driver's click: the button goes down this long after `postedAt`.
CLICK_DOWN_AFTER = 0.15
# Ice's smart rehide asks whether the clicked app is active this long after the click.
SMART_REHIDE_DELAY = 0.25


def stored_icon(lab):
    """The stored Ice icon, from an export of the lab domain (`defaults read` cuts long data)."""
    path = os.path.join(lab.dir, "prefs-%d.plist" % int(time.time() * 1000))
    subprocess.run(["/usr/bin/defaults", "export", lab.state["ice_id"], path], capture_output=True)
    if not os.path.exists(path):
        return None
    with open(path, "rb") as handle:
        data = plistlib.load(handle).get("IceIcon")
    return json.loads(data) if data else None


def icon_bytes(icon, side):
    """The image data of one side of a stored custom icon, or None."""
    encoded = ((icon or {}).get(side) or {}).get("data", {}).get("_0")
    return base64.b64decode(encoded) if encoded else None


def key_to_ice(lab, code, mods=None):
    """A key, only while Ice's lab copy is the front app: a key goes wherever the focus is."""
    if lab.front_pid() != lab.pid:
        raise Failed("Ice is not the front app; no key is posted")
    lab.drive("key", code, *(["--mods", mods] if mods else []))


def chooser_buttons(lab):
    return [row for row in lab.rows() if row["role"] == "AXButton" and row.get("title") in ("Open", "開く")]


def wait_for(condition, seconds, step=0.2):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if condition():
            return True
        time.sleep(step)
    return bool(condition())


def l1(run):
    """The custom icon chosen through the file chooser."""
    checks, facts = [], {}
    with Lab(run, "L1", member=False) as lab:
        path = os.path.join(lab.dir, "chosen.png")
        with open(path, "wb") as handle:
            handle.write(red_png())
        owner_front = lab.front_pid()
        try:
            rows = lab.open_settings()
            picker = next((row for role in ("AXMenuButton", "AXPopUpButton", "AXButton")
                           for row in [lab.control_after("Ice icon", role, rows)] if row), None)
            if picker is None:
                raise Failed("no control after Ice icon")
            facts["pickerRole"] = picker["role"]
            lab.click_row(picker)
            menus = lab.open_menus() if wait_for(lambda: lab.open_menus(), 3.0, 0.1) else []
            chose = bool(menus) and lab.choose(menus[0], "Choose image…")
            checks.append(("the icon menu offers Choose image…", chose))
            opened = chose and wait_for(lambda: chooser_buttons(lab), 5.0, 0.3)
            checks.append(("the file chooser opens in Ice's lab copy", opened))
            if opened:
                def fields(rows):
                    return [tuple(row.get("frame") or ()) for row in rows if row["role"] == "AXTextField"]
                before = fields(lab.rows())
                key_to_ice(lab, KEY_G, "cmd,shift")
                time.sleep(1.2)
                after = fields(lab.rows())
                # The Go to field is the text field that was not there before the key
                # (the chooser's list shows each file name as a text field too).
                new = [index for index, frame in enumerate(after) if frame not in before]
                facts["goToField"] = new
                done = subprocess.run([drive_path(), "axset",
                                       str(lab.pid), "AXTextField", str(new[-1] if new else -1), path], capture_output=True)
                facts["axset"] = done.stdout.decode().strip()
                time.sleep(0.4)
                facts["goTo"] = path in [row.get("value") for row in lab.rows() if row["role"] == "AXTextField"]
                checks.append(("its Go to field takes the path", facts["goTo"]))
                key_to_ice(lab, RETURN)
                time.sleep(1.5)
                key_to_ice(lab, RETURN)
                facts["chooserLeft"] = wait_for(lambda: not chooser_buttons(lab), 4.0, 0.3)
                checks.append(("the chooser closes on Open", facts["chooserLeft"]))
        finally:
            if chooser_buttons(lab) and lab.front_pid() == lab.pid:
                lab.drive("key", ESCAPE)
            lab.activate(owner_front)
        icon = stored_icon(lab)
        facts["storedName"] = (icon or {}).get("name")
        checks.append(("the chosen file's bytes are stored as the custom icon",
                       facts["storedName"] == "Custom" and icon_bytes(icon, "visible") == red_png()))
        # Secondary: the icon on the bar in the file's own colour.
        time.sleep(1.0)
        frame = lab.own_item("Ice.ControlItem.Visible")["frame"]
        facts["drawn"] = lab.read("mean", lab.shot("icon-after", frame))["mean"][:3]
        checks.append(("and drawn on the bar in its own colour (red over blue)", facts["drawn"][0] - facts["drawn"][2] > 40))
    return dict(verdict(checks), facts=facts)


class FrontWatch:
    """The front app's pid, polled on a thread: when a click made another app active."""

    def __init__(self, lab):
        self.lab, self.samples, self.stopped = lab, [], threading.Event()
        self.thread = threading.Thread(target=self.poll, daemon=True)

    def poll(self):
        while not self.stopped.is_set():
            self.samples.append((uptime(), self.lab.front_pid()))
            time.sleep(0.02)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stopped.set()
        self.thread.join(2)

    def first(self, pid, after):
        found = [at for at, front in self.samples if front == pid and at >= after]
        return found[0] if found else None


def l2(run, tries=10):
    """Smart rehide: a click in another app's window, which that click brings to the front.

    The owner's front app stays the one in front until the click; `settingsfront`'s
    window floats above it, so the click lands in it (the driver checks the pid at the
    point). Each try records how long after the button went down `settingsfront` was
    front, so a try that closed is told apart from one that never met the race.
    """
    checks, facts = [], {"tries": []}
    with Lab(run, "L2", {"AutoRehide": True, "RehideStrategy": 0}) as lab:
        owner_front = lab.front_pid()
        front = lab.start_front()
        window = front["window"]
        try:
            for _ in range(tries):
                lab.activate(owner_front)
                lab.park()
                attempt = {"behind": lab.front_pid() != front["pid"]}
                lab.send("bar open")
                attempt["opened"] = lab.wait_shown(True)
                with FrontWatch(lab) as watch:
                    result = lab.drive("click", window[0] + window[2] / 2, window[1] + window[3] / 2,
                                       "--expect", "pid:%d" % front["pid"], "--hold", 0.2)
                    attempt["closed"] = lab.wait_shown(False, 2.0)
                    down = result["postedAt"] + CLICK_DOWN_AFTER
                    # A close may come before a slow app is front: watch on for it (Codex review).
                    wait_for(lambda: watch.first(front["pid"], down) is not None, 2.0, 0.05)
                active = watch.first(front["pid"], down)
                attempt["activeAfter"] = None if active is None else round(active - down, 3)
                facts["tries"].append(attempt)
                if not attempt["closed"]:
                    lab.close_bar()
                    lab.wait_shown(False, 2.0)
        finally:
            lab.activate(owner_front)
    ran = [t for t in facts["tries"] if t["behind"] and t["opened"] and t["activeAfter"] is not None]
    late = [t for t in ran if t["activeAfter"] > SMART_REHIDE_DELAY]
    facts["closed"] = "%d of %d" % (sum(t["closed"] for t in ran), len(ran))
    facts["lateActivations"] = len(late)
    checks.append(("every try ran as meant (app behind, IceBar open, the click brought it forward)", len(ran) == tries))
    checks.append(("the IceBar closed within 2 s every time", all(t["closed"] for t in ran)))
    return dict(verdict(checks), facts=facts)


def report_times(lab, identifier, origin):
    """From Ice's report: uptimes of each roster change and whether it holds `identifier`, and of each length."""
    rosters, lengths = [], []
    for event in lab.events():
        if event["event"] == "roster":
            rosters.append((origin + event["t"], any(m.get("identifier") == identifier for m in event["members"])))
        elif event["event"] == "length":
            lengths.append((origin + event["t"], event.get("applied")))
    return rosters, lengths


def follow(lab, identifier, pid, seconds=10.0):
    """Samples the item from now: on the bar (it answers at its place), in the roster, neither.

    `nowhere` counts only from the item's first appearance among the bar's items: before
    that it does not exist yet, which is no one's fault.
    """
    samples, start = [], uptime()
    while uptime() - start < seconds:
        rostered = any(member["identifier"] == identifier for member in lab.snapshot()["roster"])
        item, exists, on_bar = lab.item(identifier), False, False
        if item and item.get("frame"):
            exists = True
            x = mid_x(item["frame"])
            on_bar = 0 <= x <= SCREEN_WIDTH and lab.read("hit", x, BAR_Y).get("pid") == pid
        samples.append((uptime(), exists, rostered or on_bar))
        time.sleep(0.2)
    seen = [s for s in samples if s[1] or s[2]]
    tail = samples[samples.index(seen[0]):] if seen else []
    nowhere = sum(later[0] - earlier[0] for earlier, later in zip(tail, tail[1:]) if not earlier[2])
    return {"nowhere": round(nowhere, 2), "listedAtEnd": bool(samples and samples[-1][2]), "samples": len(samples)}


def l3(run, offsets=(1.9, 2.15, 2.35)):
    """A new item while Ice is blocked by its icon left of the divider, then the icon put back.

    The helper is started at an offset from the start of the drag that puts the icon back
    (negative: before it), so that in some tries the roster Ice holds at the drop cannot
    include it. What is asserted is the sequence: no length is applied after the drop on
    a roster without the new item, so the item is never pushed off unlisted.
    """
    checks, facts = [], {"tries": []}
    with Lab(run, "L3") as lab:
        origin = lab.report_origin()
        stamp = lambda: "vz-s6-n-%s-%s" % (lab.state["run_id"], time.strftime("%H%M%S"))
        identifier = stamp()
        helper = lab.start_helper("Target.app", identifier, "target")
        facts["controlAtRest"] = follow(lab, identifier, helper.pid)
        members = 2
        lab.wait(lambda s: is_hidden_rest(s, members), 20, "both members hidden")
        for offset in offsets:
            attempt = {"offset": offset}
            divider = divider_frame(lab)
            visible = lab.item(lab.visible_id)["frame"]
            lab.drive("drag", lab.icon_x(), BAR_Y, divider[0] - 10, BAR_Y, "--expect", "pid:%d" % lab.pid,
                      "--command-first", 1.6, "--seconds", 0.8)
            attempt["blocked"] = lab.holds(lambda s: "blocked" in str(s.get("status")), 8.0)
            time.sleep(1.0)
            identifier = stamp()
            back = ("drag", lab.icon_x(), BAR_Y, (mid_x(divider_frame(lab)) + mid_x(visible)) / 2, BAR_Y,
                    "--expect", "pid:%d" % lab.pid, "--command-first", 1.6, "--seconds", 0.8)
            if offset < 0:
                helper = lab.start_helper("Target.app", identifier, "target")
                time.sleep(-offset)
                result = lab.drive(*back)
            else:
                lab.wait_idle()
                process = lab.drive_started(*back)
                time.sleep(offset)
                helper = lab.start_helper("Target.app", identifier, "target")
                result = lab.drive_ended(process, back)
            drop = result["endedAt"]
            attempt.update(follow(lab, identifier, helper.pid))
            rosters, lengths = report_times(lab, identifier, origin)
            held = [has for at, has in rosters if at <= drop]
            attempt["rosterAtDropHadIt"] = bool(held and held[-1])
            first_with = next((at for at, has in rosters if has and at > drop), None)
            first_length = next((at for at, applied in lengths if applied is not None and at > drop), None)
            attempt["lengthAfterDrop"] = None if first_length is None else round(first_length - drop, 2)
            attempt["rosterWithItAfterDrop"] = None if first_with is None else round(first_with - drop, 2)
            attempt["unblocked"] = "blocked" not in str(lab.snapshot().get("status"))
            facts["tries"].append(attempt)
            members += 1
            # The next try must start from a hidden rest (Codex review).
            attempt["settledAfter"] = lab.holds(lambda s: is_hidden_rest(s, members), 20.0)
            if not attempt["settledAfter"]:
                break
    ran = [t for t in facts["tries"] if t["blocked"] and t["unblocked"] and t["settledAfter"]]
    stale = [t for t in ran if not t["rosterAtDropHadIt"]]
    facts["staleAtDrop"] = len(stale)
    checks.append(("each try went through blocked and out of it", len(ran) == len(offsets)))
    checks.append(("in at least one, the roster at the drop did not hold the new item (the condition)", len(stale) >= 1))
    checks.append(("then no length came before a roster with the new item",
                   all(t["lengthAfterDrop"] is None or (t["rosterWithItAfterDrop"] is not None
                       and t["rosterWithItAfterDrop"] <= t["lengthAfterDrop"]) for t in stale)))
    checks.append(("the new item was never pushed off unlisted (0.4 s of sampling slack)", all(t["nowhere"] <= 0.4 for t in ran)))
    checks.append(("and is listed in the end, every time", all(t["listedAtEnd"] for t in ran)))
    return dict(verdict(checks), facts=facts)


CASES.update({"L1": l1, "L2": l2, "L3": l3})


def run_case(run, name):
    try:
        result = CASES[name](run)
    except NotRun as error:
        result = {"result": "notRun", "reason": str(error)}
    except Failed as error:
        result = {"result": "fail", "failed": ["the case could not finish: %s" % error], "checks": []}
    result["case"] = name
    return record(run, name, result)


def main(arguments):
    if len(arguments) < 2:
        sys.stderr.write(__doc__)
        return 2
    run, names = arguments[0], arguments[1:]
    if names == ["--list"]:
        sys.stdout.write("\n".join(sorted(CASES)) + "\n")
        return 0
    worst = 0
    for name in names:
        if name not in CASES:
            sys.stderr.write("unknown case %s\n" % name)
            return 2
        result = run_case(run, name)
        summary = {key: result.get(key) for key in ("case", "result", "failed", "facts", "reason")}
        sys.stdout.write(json.dumps(summary) + "\n")
        sys.stdout.flush()
        worst = max(worst, 0 if result["result"] == "pass" else 1)
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
