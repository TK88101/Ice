"""The settings pass's runner (plan 2026-11-12-settings-cleanup, section 2).

Starts a lab-identity copy of Ice from a scratch build, with a case's settings
written before launch, one sacrificial helper right of Ice's divider (a
visible item that is not Ice's) and one left of it (the member Ice hides),
reads Ice's report and drives the bar through `settingsdrive`.

Nothing here targets Ice by name or bundle id: the copy is started by path and
signalled by the pid this process started. The release Ice's settings are
exported at `begin` and compared at `finish`; the lab domain and the helpers'
domains are deleted there. Evidence stays in
~/IceReverse-evidence/<run id>-s6/.

    settings_lab.py begin <Ice.app>          stage the copy, print the run directory
    settings_lab.py finish <run>             tear down, compare the release settings
The cases are in settings_cases.py.
"""
import json
import os
import plistlib
import signal
import subprocess
import sys
import time

# The three S6_* overrides are test-settings.sh's: stub helpers, a throwaway
# evidence directory and a stand-in for the release's domain.
SHARED = os.environ.get("S6_SHARED", "/Users/Shared/IceReverse-lab")
EVIDENCE = os.environ.get("S6_EVIDENCE", os.path.expanduser("~/IceReverse-evidence"))
RELEASE_DOMAIN = os.environ.get("S6_RELEASE_DOMAIN", "com.jordanbaird.Ice")
LAB_PREFIX = "com.icespike4.lab."
HELPER_DOMAINS = ("com.icespike4.target", "com.icespike4.protected")
IDLE_WAIT_SECONDS = 600
BAR_Y = 16
# A point of the screen that is off the bar and off the IceBar.
PARK = (700, 600)

# Every key a case may set; all are deleted before a case writes its own.
SETTING_KEYS = (
    "ShowIceIcon", "IceIcon", "CustomIceIconIsTemplate", "UseIceBar", "IceBarLocation",
    "ShowOnClick", "ShowOnHover", "ShowOnScroll", "AutoRehide", "RehideStrategy",
    "RehideInterval", "ItemSpacingOffset", "Hotkeys", "EnableAlwaysHiddenSection",
    "ShowAllSectionsOnUserDrag", "SectionDividerStyle", "HideApplicationMenus",
    "EnableSecondaryContextMenu", "ShowOnHoverDelay", "TempShowInterval",
    "MenuBarAppearanceConfigurationV2",
)

# What every case starts from unless it says otherwise: IceBar mode, a click
# opens, nothing closes by itself.
BASE_SETTINGS = {
    "UseIceBar": True,
    "ShowOnClick": True,
    "ShowOnHover": False,
    "ShowOnScroll": False,
    "AutoRehide": False,
    "EnableAlwaysHiddenSection": False,
}

# Ice's modifier bits (Modifiers.swift) and the key codes used for hotkeys.
MOD_CONTROL, MOD_OPTION, MOD_SHIFT, MOD_COMMAND = 1, 2, 4, 8
ALL_MODS = MOD_CONTROL | MOD_OPTION | MOD_SHIFT | MOD_COMMAND
ALL_MODS_NAMES = "ctrl,opt,shift,cmd"
KEY_F13, KEY_F14, KEY_F15, KEY_F16, KEY_F17 = 105, 107, 113, 106, 64


class NotRun(Exception):
    """The case could not be run (no idle Mac, a refused press): never a pass."""


class Failed(Exception):
    """A step that must work did not."""


# --- pure helpers (settings_lab_test.py) ---------------------------------------------------

def parse_report(text):
    """The report's complete lines as objects; a torn last line is left out."""
    lines = text.split("\n")
    if lines and lines[-1] != "":
        lines = lines[:-1]
    return [json.loads(line) for line in lines if line]


def last_snapshot(events):
    for event in reversed(events):
        if event.get("event") == "snapshot":
            return event
    return None


def is_hidden_rest(snapshot, members=1):
    """Ice rests with `members` hidden and the IceBar offered."""
    return bool(
        snapshot
        and snapshot.get("lengthApplied")
        and snapshot.get("isIceBarOffered")
        and len(snapshot.get("roster", [])) == members
    )


def hotkey_data(key_code, modifiers):
    """A KeyCombination as Ice stores it: JSON of [key code, modifier bits]."""
    return json.dumps([key_code, modifiers], separators=(",", ":")).encode()


def settings_plist(settings):
    """The defaults to import: Python values as their plist types."""
    return plistlib.dumps(settings, fmt=plistlib.FMT_XML)


def merged_settings(case_settings):
    merged = dict(BASE_SETTINGS)
    merged.update(case_settings or {})
    return merged


def panel_of(windows):
    """The IceBar's panel among a process's windows, when it is on screen."""
    for window in windows:
        if window.get("title") == "Ice Bar" and window.get("onScreen") and window["bounds"][2] > 1:
            return window
    return None


def mid_x(rect):
    return rect[0] + rect[2] / 2


def is_lab_id(bundle_id):
    return bundle_id.startswith(LAB_PREFIX) and bundle_id.endswith(".s6")


def running_ice(ps_lines):
    """Any Ice, release or lab copy, among `ps -o comm=` lines."""
    return [
        line for line in ps_lines
        if "/Ice.app/Contents/MacOS/" in line or os.path.basename(line.strip()).startswith("IceLab")
    ]


def verdict(checks):
    """`pass` when every check holds; the failed checks' names otherwise."""
    failed = [name for name, holds in checks if not holds]
    return {
        "result": "pass" if not failed else "fail",
        "failed": failed,
        "checks": [[name, bool(holds)] for name, holds in checks],
    }


# --- the session ---------------------------------------------------------------------------

def sh(*args, check=True):
    done = subprocess.run(list(args), capture_output=True)
    if check and done.returncode != 0:
        raise Failed("%s: %s" % (" ".join(args[:3]), done.stderr.decode(errors="replace")[:300]))
    return done.stdout.decode(errors="replace")


def own_processes():
    return sh("/bin/ps", "-U", str(os.getuid()), "-o", "comm=").splitlines()


def drive_path():
    return os.environ.get("S6_DRIVE", os.path.expanduser("~/.cache/icereverse-s6/settingsdrive"))


def export_prefs(domain, path):
    done = subprocess.run(["/usr/bin/defaults", "export", domain, path], capture_output=True)
    if done.returncode == 0 and os.path.exists(path):
        sh("/usr/bin/plutil", "-convert", "xml1", path)
    else:
        with open(path, "w") as handle:
            handle.write("")


def begin(ice_app):
    """Stages the lab copy; returns the run's state."""
    if running_ice(own_processes()):
        raise NotRun("an Ice is already running")
    run_id = time.strftime("%Y%m%d-%H%M%S")
    run = os.path.join(EVIDENCE, run_id + "-s6")
    os.makedirs(os.path.join(run, "stage"), mode=0o700)
    ice_id = "%sr%s.s6" % (LAB_PREFIX, run_id)
    ice_name = "IceLab%ss6" % run_id.replace("-", "")
    app = os.path.join(run, "stage", "Ice.app")
    sh("/usr/bin/ditto", "--", ice_app, app)
    sh("/bin/chmod", "-R", "u+w", app)
    info = os.path.join(app, "Contents", "Info.plist")
    sh("/usr/libexec/PlistBuddy", "-c", "Set :CFBundleIdentifier %s" % ice_id, info)
    os.rename(os.path.join(app, "Contents", "MacOS", "Ice"), os.path.join(app, "Contents", "MacOS", ice_name))
    sh("/usr/libexec/PlistBuddy", "-c", "Set :CFBundleExecutable %s" % ice_name, info)
    sh("/usr/bin/codesign", "--force", "--deep", "--sign", "-", app)
    sh("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    export_prefs(RELEASE_DOMAIN, os.path.join(run, "prefs-before.plist"))
    version = sh("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", info).strip()
    state = {
        "run": run, "run_id": run_id, "ice_id": ice_id, "ice_name": ice_name, "app": app,
        "source": ice_app, "version": version,
    }
    with open(os.path.join(run, "state.json"), "w") as handle:
        json.dump(state, handle, indent=1)
    return state


def load_state(run):
    with open(os.path.join(run, "state.json")) as handle:
        return json.load(handle)


def finish(run):
    """Tears the session down; returns what the Mac is left with."""
    state = load_state(run)
    left_running = [line for line in own_processes() if state["ice_name"] in line or "/vzhelper" in line]
    for domain in (state["ice_id"],) + HELPER_DOMAINS:
        subprocess.run(["/usr/bin/defaults", "delete", domain], capture_output=True)
    remaining = subprocess.run(["/usr/bin/defaults", "read", state["ice_id"]], capture_output=True)
    export_prefs(RELEASE_DOMAIN, os.path.join(run, "prefs-after.plist"))
    with open(os.path.join(run, "prefs-before.plist"), "rb") as before, open(os.path.join(run, "prefs-after.plist"), "rb") as after:
        same = before.read() == after.read()
    sh("/bin/rm", "-rf", "--", os.path.join(run, "stage"))
    spacing = [
        key for key in ("NSStatusItemSpacing", "NSStatusItemSelectionPadding")
        if subprocess.run(["/usr/bin/defaults", "-currentHost", "read", "-globalDomain", key], capture_output=True).returncode == 0
    ]
    result = {
        "leftRunning": left_running,
        # A deleted domain reads as an empty dictionary for a while.
        "labDomainEmpty": remaining.returncode != 0 or remaining.stdout.decode().split() == ["{", "}"],
        "releaseSettingsUnchanged": same,
        "spacingKeysPresent": spacing,
    }
    with open(os.path.join(run, "finish.json"), "w") as handle:
        json.dump(result, handle, indent=1)
    return result


# --- one launch ----------------------------------------------------------------------------

class Lab:
    """One launch of the lab copy with a case's settings."""

    def __init__(self, run, name, settings=None, member=True, arguments=(), expect_hidden=True,
                 fresh_visible=False, keep_settings=False):
        self.state = load_state(run)
        self.dir = os.path.join(run, name)
        self.settings = merged_settings(settings)
        self.member = member
        self.arguments = list(arguments)
        self.expect_hidden = expect_hidden
        self.keep_settings = keep_settings
        self.ice = None
        self.helpers = []
        self.report_path = os.path.join(self.dir, "report.jsonl")
        self.started_uptime = None
        # macOS remembers a status item's place by its autosave name, in a
        # store of its own: a member that a case dragged would come back where
        # it was dropped. So the member is new at every launch and lands
        # leftmost, left of Ice's divider. The visible helper keeps its name
        # (and its place right of the divider) unless the case drags it.
        stamp = time.strftime("%H%M%S")
        self.member_id = "vz-s6-m-%s-%s" % (self.state["run_id"], stamp)
        self.visible_id = "vz-s6-v-%s%s" % (self.state["run_id"], "-" + stamp if fresh_visible else "")

    # lifecycle

    def __enter__(self):
        os.makedirs(self.dir, mode=0o700, exist_ok=True)
        if running_ice(own_processes()):
            raise NotRun("an Ice is already running")
        self.write_settings()
        try:
            # In every launch: one without it moves where the system remembers
            # Ice's divider, and the next launch finds this helper left of it
            # (sessions 20261112-201934-s6 and -202047-s6).
            self.start_helper("Protected.app", self.visible_id, "reference")
            self.start_ice()
            if self.member:
                self.wait(lambda s: s.get("hiddenDivider") is not None, 20, "Ice's divider on the bar")
                time.sleep(1.5)
                self.start_helper("Target.app", self.member_id, "target")
                if self.expect_hidden:
                    self.wait(is_hidden_rest, 40, "the member hidden")
                    time.sleep(1.0)
                    roster = [member["identifier"] for member in self.snapshot()["roster"]]
                    if roster != [self.member_id]:
                        raise NotRun("the helpers did not land as the case needs")
        except BaseException:
            self.stop()
            raise
        return self

    def __exit__(self, *_):
        self.stop()
        return False

    def write_settings(self):
        # A fresh identity at every launch: no setting and no remembered
        # position of an earlier case (a case that drags an item would
        # otherwise leave it where the next case does not expect it).
        domain = self.state["ice_id"]
        if self.keep_settings:
            # The launch after a case changed settings in the window: as stored.
            return
        for stale in (domain,) + HELPER_DOMAINS:
            subprocess.run(["/usr/bin/defaults", "delete", stale], capture_output=True)
        path = os.path.join(self.dir, "settings.plist")
        with open(path, "wb") as handle:
            handle.write(settings_plist(self.settings))
        sh("/usr/bin/defaults", "import", domain, path)

    def start_ice(self):
        executable = os.path.join(self.state["app"], "Contents", "MacOS", self.state["ice_name"])
        environment = dict(os.environ, OS_ACTIVITY_DT_MODE="YES")
        self.started_uptime = uptime()
        with open(self.report_path, "wb") as report, open(os.path.join(self.dir, "report.log"), "wb") as log:
            self.ice = subprocess.Popen(
                [executable, "-IceLabReport", "YES", "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"] + self.arguments,
                stdin=subprocess.PIPE, stdout=report, stderr=log, env=environment,
            )
        deadline = time.time() + 15
        while time.time() < deadline:
            if os.path.getsize(self.report_path) > 0:
                return
            if self.ice.poll() is not None:
                raise Failed("Ice ended at once (%s)" % self.ice.returncode)
            time.sleep(0.1)
        raise Failed("Ice wrote no report")

    def start_helper(self, app, identifier, glyph):
        log_path = os.path.join(self.dir, "helper-%s.log" % identifier)
        arguments = [
            os.path.join(SHARED, "apps", app, "Contents", "MacOS", "vzhelper"), "--controller", str(os.getpid()),
            "--items", "1", "--identifiers", identifier, "--glyphs", glyph, "--autosave", identifier,
            "--menu", "--lifetime", "900",
        ]
        with open(log_path, "wb") as log:
            helper = subprocess.Popen(arguments, stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
        self.helpers.append(helper)
        deadline = time.time() + 10
        while time.time() < deadline:
            with open(log_path) as log:
                if log.read().startswith("up "):
                    return helper
            time.sleep(0.1)
        raise Failed("helper %s did not come up" % app)

    def stop(self):
        if self.ice is not None and self.ice.poll() is None:
            # Signalled by the pid this process started, never by name.
            self.ice.send_signal(signal.SIGTERM)
            try:
                self.ice.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.ice.kill()
        for helper in self.helpers:
            if helper.poll() is None:
                try:
                    helper.stdin.write(b"quit\n")
                    helper.stdin.flush()
                    helper.wait(timeout=5)
                except (OSError, subprocess.TimeoutExpired):
                    helper.kill()
        self.helpers = []
        time.sleep(1.0)

    # reading

    @property
    def pid(self):
        return self.ice.pid

    def events(self):
        with open(self.report_path) as handle:
            return parse_report(handle.read())

    def snapshot(self):
        return last_snapshot(self.events())

    def wait(self, predicate, seconds, what):
        deadline = time.time() + seconds
        while time.time() < deadline:
            if self.ice.poll() is not None:
                raise Failed("Ice ended while waiting for %s" % what)
            snapshot = self.snapshot()
            if snapshot is not None and predicate(snapshot):
                return snapshot
            time.sleep(0.25)
        raise Failed("timed out waiting for %s" % what)

    def holds(self, predicate, seconds):
        """Whether the predicate becomes true within `seconds`."""
        try:
            self.wait(predicate, seconds, "")
            return True
        except Failed:
            return False

    def read(self, *arguments):
        return json.loads(sh(drive_path(), *[str(a) for a in arguments]))

    def windows(self):
        return self.read("windows", self.pid)["windows"]

    def panel(self):
        return panel_of(self.windows())

    def shown(self):
        snapshot = self.snapshot()
        return bool(snapshot and snapshot.get("isIceBarPresented") and self.panel() is not None)

    def wait_shown(self, want, seconds=3.0):
        deadline = time.time() + seconds
        while time.time() < deadline:
            if self.shown() == want:
                return True
            time.sleep(0.15)
        return self.shown() == want

    def items(self):
        return self.read("items")["items"]

    def item(self, identifier):
        found = [item for item in self.items() if item["identifier"] == identifier]
        return found[0] if len(found) == 1 else None

    def own_item(self, identifier):
        found = [item for item in self.items() if item["pid"] == self.pid and item["identifier"] == identifier]
        return found[0] if len(found) == 1 else None

    def icon_x(self):
        icon = self.own_item("Ice.ControlItem.Visible")
        if icon is None or icon["frame"] is None:
            raise Failed("Ice's icon is not on the bar")
        return mid_x(icon["frame"])

    def empty_x(self):
        """A point of empty bar space right of the notch, left of the items."""
        return self.read("gap", 960)["x"]

    def report_origin(self):
        """The uptime at which the report's clock reads 0, from its next line."""
        size = os.path.getsize(self.report_path)
        deadline = time.time() + 8
        while time.time() < deadline:
            if os.path.getsize(self.report_path) > size:
                now = uptime()
                return now - self.events()[-1]["t"]
            time.sleep(0.01)
        raise Failed("the report stopped")

    def menu_open(self, pid):
        """Whether that process has a menu on screen."""
        return any(w["onScreen"] and w["layer"] == 101 for w in self.read("windows", pid)["windows"])

    def default(self, key):
        done = subprocess.run(["/usr/bin/defaults", "read", self.state["ice_id"], key], capture_output=True)
        return done.stdout.decode().strip() if done.returncode == 0 else None

    def shot(self, name, rect):
        path = os.path.join(self.dir, name + ".png")
        sh("/usr/sbin/screencapture", "-x", "-R", "%d,%d,%d,%d" % tuple(rect), path)
        return path

    # input

    def drive(self, *arguments):
        """A guarded input command; waits for an idle Mac, never forces."""
        deadline = time.time() + IDLE_WAIT_SECONDS
        while True:
            done = subprocess.run([drive_path()] + [str(a) for a in arguments], capture_output=True)
            try:
                result = json.loads(done.stdout.decode().strip().splitlines()[-1])
            except (ValueError, IndexError):
                raise Failed("settingsdrive said nothing (%s)" % done.returncode)
            self.log_step(arguments, result)
            if result.get("result") == "done":
                return result
            reason = str(result.get("reason"))
            if "hardwareInput" in reason and time.time() < deadline:
                time.sleep(6)
                continue
            raise NotRun("%s: %s" % (arguments[0], reason))

    def drive_started(self, *arguments):
        """Starts an input command and returns at once; `drive_ended` collects it."""
        return subprocess.Popen([drive_path()] + [str(a) for a in arguments], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def drive_ended(self, process, arguments=()):
        out, _ = process.communicate(timeout=60)
        try:
            result = json.loads(out.decode().strip().splitlines()[-1])
        except (ValueError, IndexError):
            raise Failed("settingsdrive said nothing (%s)" % process.returncode)
        self.log_step(arguments, result)
        if result.get("result") != "done":
            raise NotRun("%s" % result.get("reason"))
        return result

    def wait_idle(self):
        """Waits for a Mac nobody is using; `NotRun` when it never comes."""
        deadline = time.time() + IDLE_WAIT_SECONDS
        while time.time() < deadline:
            if self.read("idle")["hardwareIdle"] >= 6:
                return
            time.sleep(3)
        raise NotRun("the Mac was in use")

    def log_step(self, arguments, result):
        with open(os.path.join(self.dir, "steps.jsonl"), "a") as handle:
            handle.write(json.dumps({"t": time.time(), "uptime": uptime(), "args": [str(a) for a in arguments], "result": result}) + "\n")

    def click_empty(self, x=None, right=False, mods=None, hold=None):
        x = self.empty_x() if x is None else x
        extra = ["--right"] if right else []
        if mods:
            extra += ["--mods", mods]
        if hold:
            extra += ["--hold", hold]
        self.drive("click", x, BAR_Y, "--expect", "empty", *extra)
        return x

    def click_at(self, x, pid, y=BAR_Y, right=False, hold=None):
        extra = ["--right"] if right else []
        if hold:
            extra += ["--hold", hold]
        self.drive("click", x, y, "--expect", "pid:%d" % pid, *extra)

    def park(self):
        """Puts the pointer in the middle of the screen, off the bar and the panel."""
        self.drive("move", *PARK)

    # the pass's own front app

    def start_front(self):
        """Starts `settingsfront`; returns its pid and window (top-left points)."""
        log_path = os.path.join(self.dir, "front.log")
        binary = os.environ.get("S6_FRONT", os.path.expanduser("~/.cache/icereverse-s6/settingsfront"))
        with open(log_path, "wb") as log:
            front = subprocess.Popen([binary, "--controller", str(os.getpid())], stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
        self.helpers.append(front)
        deadline = time.time() + 10
        while time.time() < deadline:
            with open(log_path) as log:
                text = log.read()
            if text.startswith("up "):
                return json.loads(text[3:].splitlines()[0])
            time.sleep(0.1)
        raise Failed("settingsfront did not come up")

    def front_pid(self):
        return json.loads(sh(os.path.join(SHARED, "apps", "icewatch"), "front", check=False) or "{}").get("pid")

    def activate(self, pid):
        """Brings a process to the front; whether it is in front afterwards."""
        for _ in range(3):
            done = subprocess.run([os.path.join(SHARED, "apps", "icewatch"), "activate", "--pid", str(pid)], capture_output=True)
            if done.returncode == 0:
                time.sleep(0.6)
                return True
            time.sleep(1)
        return False

    def helper_command(self, index, command):
        helper = self.helpers[index]
        helper.stdin.write((command + "\n").encode())
        helper.stdin.flush()

    # Ice's own menus and windows

    def open_menus(self):
        return [w for w in self.windows() if w["onScreen"] and w["layer"] == 101]

    def menu_entries(self, menu):
        """An open menu's entries, top to bottom: title and a point inside each."""
        x, y, width, height = menu["bounds"]
        entries = []
        for offset in range(6, int(height), 6):
            found = self.read("hit", x + width / 2, y + offset)
            title = found["chain"][0].get("title") if found.get("pid") == self.pid else None
            if title and (not entries or entries[-1][0] != title):
                entries.append((title, (x + width / 2, y + offset)))
        return entries

    def choose(self, menu, title):
        """Clicks the entry of an open menu of Ice's that has that title."""
        for name, point in self.menu_entries(menu):
            if name == title:
                self.click_at(point[0], self.pid, y=point[1])
                return True
        return False

    def open_secondary_menu(self):
        self.click_empty(right=True, hold=0.4)
        deadline = time.time() + 3
        while time.time() < deadline:
            menus = self.open_menus()
            if menus:
                return menus[0]
            time.sleep(0.1)
        raise Failed("the secondary menu did not open")

    def open_settings(self):
        """Opens the settings window from the secondary context menu."""
        menu = self.open_secondary_menu()
        if not self.choose(menu, "Ice Settings…"):
            raise Failed("no Ice Settings… entry")
        deadline = time.time() + 8
        while time.time() < deadline:
            rows = self.rows()
            if any(row["role"] == "AXWindow" for row in rows) and len(rows) > 10:
                time.sleep(1.0)
                return self.rows()
            time.sleep(0.3)
        raise Failed("the settings window did not open")

    def rows(self):
        return self.read("axdump", self.pid)["rows"]

    def control_after(self, label, role, rows=None):
        """The first control of that role that follows the text `label` in a window."""
        rows = self.rows() if rows is None else rows
        for index, row in enumerate(rows):
            if row["role"] == "AXStaticText" and row.get("value") == label:
                for later in rows[index + 1:index + 6]:
                    if later["role"] == role:
                        return later
        return None

    def click_row(self, row, hold=0.3):
        frame = row["frame"]
        self.click_at(frame[0] + frame[2] / 2, self.pid, y=frame[1] + frame[3] / 2, hold=hold)

    def select_pane(self, name):
        """Clicks the settings sidebar's row of that name; returns the pane's rows."""
        for row in self.rows():
            if row["role"] == "AXStaticText" and row.get("value") == name and row["depth"] >= 8:
                self.click_row(row)
                time.sleep(1.2)
                return self.rows()
        raise Failed("no %s in the sidebar" % name)

    def texts(self, rows=None):
        """Every text a window shows: static texts, titles and descriptions."""
        found = []
        for row in (self.rows() if rows is None else rows):
            for key in ("value", "title", "description"):
                if isinstance(row.get(key), str) and row[key]:
                    found.append(row[key])
        return found

    def press(self, role, title, index=0):
        done = subprocess.run([drive_path(), "axpress", str(self.pid), role, title, str(index)], capture_output=True)
        return done.returncode == 0

    def send(self, command):
        self.ice.stdin.write((command + "\n").encode())
        self.ice.stdin.flush()

    def close_bar(self):
        self.send("bar close")
        self.wait_shown(False)


def uptime():
    return time.clock_gettime(time.CLOCK_UPTIME_RAW)


def record(run, case, result):
    with open(os.path.join(run, case + ".json"), "w") as handle:
        json.dump(result, handle, indent=1)
    return result


def main(arguments):
    if arguments[:1] == ["begin"] and len(arguments) == 2:
        print(begin(arguments[1])["run"])
        return 0
    if arguments[:1] == ["finish"] and len(arguments) == 2:
        result = finish(arguments[1])
        print(json.dumps(result))
        clean = not result["leftRunning"] and result["labDomainEmpty"] and result["releaseSettingsUnchanged"] and not result["spacingKeysPresent"]
        return 0 if clean else 1
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
