#!/usr/bin/env python3
"""The lab matrix's judge (plan 2026-10-07-icebar-preference-hiding, S4 design).

Pure: it reads what a scenario run left in its directory and decides. Run by
run-lab.sh as `python3 -I lab-tool.py ...`, tested by test_lab_tool.py on
synthetic input. Nothing here starts a process or touches the bar.

A scenario run's directory holds:
  report-1.jsonl [report-2.jsonl]  Ice's lab report, one per start (D1)
  steps.jsonl                      what the runner did and saw, one JSON object a line
  expected.json                    {"scenario", "members": [...], "blockers": [...], "added"?}

  lab-tool.py check <report>                       exit 0 complete, 3 damaged (Ice stopped)
  lab-tool.py await <report> <predicate> [args]    exit 0 holds now, 1 not yet, 3 damaged
  lab-tool.py wait <report> <seconds> <pid> <predicate> [args]
                                                   waits in this one process: exit 0 held, 1 timed out, 3 damaged, 4 the pid ended
  lab-tool.py bracket <report>                     the latest snapshot's member frames and conditions
  lab-tool.py selfread-frames <line> <identifier>  a helper's items' frames, as JSON
  lab-tool.py judge <run directory>                the verdict, as JSON; exit 0 pass, 1 otherwise
  lab-tool.py clean <evidence directory> <round>   exit 0 when that round is clean (D5's stop rule)
  lab-tool.py report <evidence directory>          the matrix report; exit 0 only when S4's DoD is met
  lab-tool.py order                                the scenarios in the order a round runs them
"""
import json
import os
import sys
import time

MARKER = "IceLabReport-start-v1"
TARGET = "com.icespike4.target"

# LabReportSnapshot.keys, in order (IceCore). test-lab.sh compares the two lists.
SNAPSHOT_KEYS = [
    "phase", "status", "lengthSet", "lengthApplied", "calibratedHiddenLength", "isIceBarOffered",
    "isIceBarPresented", "isInteracting", "roster", "blockers", "cells", "cacheVisible", "cacheHidden",
    "cacheAlwaysHidden", "iconPlacement", "hiddenBoundaryUsable", "icon", "hiddenDivider",
    "alwaysHiddenDivider", "completeness", "pass", "checks", "chevronListed",
]

# The matrix, in the order a round runs it (D2: `noref` before the references
# start). kind: what the run must end as. `inverted-moved` is not run (D4).
SCENARIOS = {
    "noref": {"kind": "unverified"},
    "sparse": {"kind": "verified"},
    "k2": {"kind": "verified"},
    "k4": {"kind": "verified"},
    "k8": {"kind": "verified"},
    "press": {"kind": "verified"},
    "addremove": {"kind": "verified"},
    "crowded": {"kind": "unverified"},
    "fresh-off": {"kind": "verified"},
    "fresh-on": {"kind": "verified", "clauses": ["t2d"]},
    "placed-off": {"kind": "verified"},
    "placed-on": {"kind": "verified", "clauses": ["t2d"]},
    "front-short": {"kind": "verified"},
    "front-long": {"kind": "bestEffort"},
    "relaunch": {"kind": "verified"},
    "positional": {"kind": "blocked"},
    "inverted": {"kind": "blocked"},
    "drawn": {"kind": "failed"},
    "incomplete": {"kind": "blocked"},
    "inverted-moved": {"kind": "notRun"},
}
ORDER = list(SCENARIOS)
# Judged and reported every round, never a reason by itself to stop the rounds (D4).
KNOWN_OPEN = {"t2d"}
ROUNDS = 3
# Whose last status is not their kind (Codex, T4 code review round 1):
# `incomplete` must leave `blocked` once the stall ends; `drawn` re-cycles up
# to three times, so a run may end in the middle of a cycle.
ENDS_ELSEWHERE = {"incomplete", "drawn"}
# Exempt from the `«`-at-start setup clause (S4 design, corrected while
# building): `crowded` sets up the `«` itself; the two blocked ones are judged
# on no check.
NO_CHECK_AT_START = {"crowded", "positional", "inverted"}


class Damaged(Exception):
    """A report that cannot be trusted: never a pass (D1, Transport)."""


# --- reading ------------------------------------------------------------------

def load_report(path, final=True):
    """The report's lines. While Ice runs (final=False) an unfinished last line
    is left for later; once it has stopped, a line that does not parse, a gap or
    step back in `seq`, an unfinished last line or a missing `start` is damage."""
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError as error:
        raise Damaged(f"unreadable report: {error.strerror}")
    pieces = data.split(b"\n")
    trailing = pieces.pop()
    if trailing and final:
        raise Damaged("the report's last line is unfinished")
    events = parse_lines(pieces, first_seq=1)
    if final and not events:
        raise Damaged("the report is empty")
    check_start(events)
    return events


SNAPSHOT_LINE_KEYS = set(SNAPSHOT_KEYS) | {"event", "seq", "t"}


def parse_lines(pieces, first_seq):
    """Complete lines, numbered from `first_seq`: each must be an event whose
    `seq` is its line number, a snapshot with exactly the pinned keys."""
    events = []
    for number, piece in enumerate(pieces, start=first_seq):
        try:
            event = json.loads(piece.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            raise Damaged(f"line {number} is not JSON")
        if not isinstance(event, dict) or not isinstance(event.get("event"), str):
            raise Damaged(f"line {number} is not an event")
        if event.get("seq") != number:
            raise Damaged(f"line {number} carries seq {event.get('seq')!r}")
        if event["event"] == "snapshot" and set(event) != SNAPSHOT_LINE_KEYS:
            raise Damaged(f"snapshot {number} has other keys than the pinned ones")
        if event["event"] == "start" and number != 1:
            raise Damaged("a second start line")
        events.append(event)
    return events


def check_start(events):
    if events and (events[0]["event"] != "start" or events[0].get("marker") != MARKER):
        raise Damaged("the report does not begin with Ice's start line")


def load_steps(path):
    steps = []
    try:
        with open(path) as handle:
            for number, line in enumerate(handle, start=1):
                if not line.strip():
                    continue
                try:
                    entry = json.loads(line)
                except ValueError:
                    raise Damaged(f"steps line {number} is not JSON")
                if not isinstance(entry, dict) or not isinstance(entry.get("step"), str):
                    raise Damaged(f"steps line {number} is not a step")
                steps.append(entry)
    except FileNotFoundError:
        pass
    return steps


def load_expected(path):
    with open(path) as handle:
        expected = json.load(handle)
    if expected.get("scenario") not in SCENARIOS:
        raise Damaged(f"unknown scenario {expected.get('scenario')!r}")
    return expected


# --- what a report says ---------------------------------------------------------

def of(events, name):
    return [event for event in events if event["event"] == name]


def snapshots(events):
    return of(events, "snapshot")


def latest_snapshot(events):
    found = snapshots(events)
    return found[-1] if found else None


def ids(entries):
    return sorted(entry["identifier"] for entry in entries)


def statuses(events, since=0):
    return [event for event in of(events, "status") if event["seq"] > since]


def first_status(events, prefix, since=0):
    return next((event for event in statuses(events, since) if event["status"].startswith(prefix)), None)


def lengths(events, since=0):
    return [event for event in of(events, "length") if event["seq"] > since]


def applied_lengths(events, since=0):
    """Length events that gave the divider a length."""
    return [event for event in lengths(events, since) if event.get("applied") is not None]


def first_retire(events, since):
    return next((event for event in lengths(events, since) if event.get("applied") is None), None)


def snapshot_before(events, seq):
    found = [event for event in snapshots(events) if event["seq"] < seq]
    return found[-1] if found else None


def snapshot_at_or_before(events, cut):
    """The snapshot the runner had at a step. A step's `seq` is a cut of the
    report (`mark` in run-lab.sh: the lines it held then): a line with
    `seq <= cut` was written before the step, one with `seq > cut` after it."""
    found = [event for event in snapshots(events) if event["seq"] <= cut]
    return found[-1] if found else None


def snapshot_after(events, seq):
    return next((event for event in snapshots(events) if event["seq"] > seq), None)


def step(steps, name, **match):
    return next((entry for entry in steps if entry["step"] == name and all(entry.get(k) == v for k, v in match.items())), None)


def kind_of(events):
    """What the run ended as, by its last status."""
    found = statuses(events)
    if not found:
        return "none"
    text = found[-1]["status"]
    if text == "verified":
        return "verified"
    for prefix, kind in (("blocked(", "blocked"), ("failed(", "failed"), ("notVerified(", "unverified")):
        if text.startswith(prefix):
            return kind
    return "off"


# --- predicates for `await` (the runner waits on them) ------------------------------

def predicate_holds(events, name, args):
    latest = latest_snapshot(events)
    since = int(args[0]) if args and args[0].isdigit() else 0
    if name == "started":
        return bool(events)
    if name == "status":  # <since> <prefix>
        return first_status(events, args[1], since) is not None
    if name == "verified":  # <since>
        return first_status(events, "verified", since) is not None
    if name == "rest":
        return bool(latest and latest["lengthApplied"])
    if name == "blockers":  # <since> <count>
        return bool(latest and latest["seq"] > since and len(latest["blockers"]) == int(args[1]))
    if name == "length-null":  # <since>
        return first_retire(events, since) is not None
    if name == "any-length":  # <since>
        return bool(applied_lengths(events, since))
    if name == "stacked":
        return bool(
            latest
            and latest["iconPlacement"] is None
            and not latest["status"].startswith("blocked(")
            and any(member["condition"] == "stacked" for member in latest["roster"])
        )
    if name == "divider-unusable":
        return bool(latest and "dividerUnusable" in latest["status"])
    raise SystemExit(f"lab-tool: unknown predicate {name}")


def selfread_frames(line, identifier):
    """The frames of a helper's own items with this identifier, from its
    `selfread` reply (vzhelper), in the order Accessibility lists them."""
    kind, _, body = line.partition(" ")
    if kind != "selfread":
        return []
    try:
        children = json.loads(body).get("children", [])
    except (ValueError, AttributeError):
        return []
    return [child["frame"] for child in children if isinstance(child, dict) and child.get("identifier") == identifier and isinstance(child.get("frame"), list)]


def bracket_key(events):
    """The latest snapshot's members, frames and conditions, for `crowded`'s
    bracketed reading (D4): two equal keys around the `«` read."""
    latest = latest_snapshot(events)
    if latest is None:
        return ""
    return json.dumps([[m["identifier"], m["condition"], m["frame"]] for m in latest["roster"]], sort_keys=True)


# --- the oracles --------------------------------------------------------------------

class Verdict:
    def __init__(self, scenario):
        self.scenario = scenario
        self.result = "pass"
        self.reasons = []
        self.clauses = {}
        self.kind = None

    def fail(self, reason):
        if self.result == "pass":
            self.result = "fail"
        self.reasons.append(reason)

    def not_established(self, reason):
        if self.result in ("pass", "fail"):
            self.result = "notEstablished"
        self.reasons.insert(0, f"setup: {reason}")

    def clause(self, name, holds, reason):
        self.clauses[name] = "pass" if holds else "fail"
        if not holds:
            self.fail(f"{name}: {reason}")

    def json(self):
        return {"scenario": self.scenario, "result": self.result, "kind": self.kind, "clauses": self.clauses, "reasons": self.reasons}


def setup_roster(verdict, events, expected, before_seq):
    """The roster Ice was about to hide is exactly the members the runner
    started, all of them ours, and Ice's icon right of its divider (D3)."""
    snap = snapshot_before(events, before_seq) if before_seq else latest_snapshot(events)
    if snap is None:
        verdict.not_established("no snapshot before the length was applied")
        return None
    roster = snap["roster"]
    foreign = sum(member["namespace"] != TARGET for member in roster)
    if foreign:
        verdict.not_established(f"{foreign} roster member(s) not ours")
    elif ids(roster) != sorted(expected["members"]):
        verdict.not_established(f"roster of {len(roster)} member(s), expected {len(expected['members'])}")
    if snap["iconPlacement"] is not None:
        verdict.not_established(f"Ice's icon placement {snap['iconPlacement']}")
    return snap


def chevron_at_start(verdict, steps):
    entry = step(steps, "chevronAtStart")
    if entry and entry.get("listed"):
        verdict.not_established("« listed when the scenario began: a baseline refuses with a fold present (L2)")


def verified_rest(verdict, events, members, since=0):
    """`sparse`'s oracle (D4): verified, cells = roster = members, every member
    checked absent, a length standing. Returns the verified status event."""
    status = first_status(events, "verified", since)
    if status is None:
        found = statuses(events, since)
        verdict.fail(f"never verified (last status: {found[-1]['status'] if found else 'none'})")
        return None
    snap = snapshot_after(events, status["seq"])
    if snap is None or snap["status"] != "verified":
        verdict.fail("no snapshot taken while verified")
        return status
    members = sorted(members)
    if ids(snap["roster"]) != members:
        verdict.fail("the verified roster is not the members")
    if ids(snap["cells"]) != ids(snap["roster"]):
        verdict.fail("the IceBar's cells are not the roster")
    if any(cell["disabled"] for cell in snap["cells"]):
        verdict.fail("a cell is disabled")
    outcomes = {check["identifier"]: check["outcome"] for check in snap["checks"]}
    for name in members:
        if outcomes.get(name) != "hidden":
            verdict.fail(f"member {name}'s check is {outcomes.get(name, 'missing')}, not hidden")
    if not snap["lengthApplied"] or snap["calibratedHiddenLength"] is None:
        verdict.fail("no length standing while verified")
    else:
        set_before = [event for event in of(events, "length") if event["seq"] < snap["seq"]]
        if not set_before or set_before[-1].get("applied") != snap["calibratedHiddenLength"]:
            verdict.fail("the standing length is not the last one set")
    return status


def first_length_seq(events):
    found = applied_lengths(events)
    return found[0]["seq"] if found else None


def standard_setup(verdict, events, expected):
    length_seq = first_length_seq(events)
    if length_seq is None:
        verdict.fail("no length was applied")
    return setup_roster(verdict, events, expected, length_seq), length_seq


def judge_sparse(verdict, run):
    events = run.report(1)
    standard_setup(verdict, events, run.expected)
    verified_rest(verdict, events, run.expected["members"])


def judge_press(verdict, run):
    events = run.report(1)
    standard_setup(verdict, events, run.expected)
    if verified_rest(verdict, events, run.expected["members"]) is None:
        return
    opened = [event for event in of(events, "bar") if event["action"] == "open"]
    if not opened or opened[0]["answer"] != "sent":
        verdict.fail(f"bar open was {opened[0]['answer'] if opened else 'not answered'}")
    elif not any(snap["isIceBarPresented"] for snap in snapshots(events) if snap["seq"] > opened[0]["seq"]):
        verdict.fail("the IceBar was never presented after bar open")
    for name in run.expected["members"]:
        answer = next((event["answer"] for event in of(events, "press") if event["identifier"] == name), None)
        if answer != "sent":
            verdict.fail(f"press {name}: {answer or 'not answered'}")
        seen = step(run.steps, "menuOpen", member=name)
        if not seen or not seen.get("seen"):
            verdict.fail(f"press {name}: the helper's menu did not open within 2 s")
    latest = latest_snapshot(events)
    if latest and any(cell["disabled"] for cell in latest["cells"]):
        verdict.fail("a cell is disabled after the presses")


def judge_addremove(verdict, run):
    events, steps = run.report(1), run.steps
    standard_setup(verdict, events, run.expected)
    if len(run.expected["members"]) != 2 or "added" not in run.expected:
        verdict.fail("the runner did not reach the add and the removal")
        return
    first, second = sorted(run.expected["members"])
    third = run.expected["added"]
    if verified_rest(verdict, events, [first, second]) is None:
        return
    added, removed = step(steps, "added"), step(steps, "removed")
    if not added or not removed:
        verdict.fail("the runner did not reach the add and the removal")
        return
    # Added: a pass at a hiding length freezes the roster, so the length goes first.
    retired = first_retire(events, added["seq"])
    taken = next((event for event in of(events, "roster") if event["seq"] > added["seq"] and third in ids(event["members"])), None)
    if taken is None or retired is None or retired["seq"] > taken["seq"]:
        verdict.fail("added: the length was not retired before the roster took the third")
    if verified_rest(verdict, events, [first, second, third], since=added["seq"]) is None:
        return
    # Removed: the exited member is dropped at any length (G1), then the length goes.
    dropped = next((event for event in of(events, "roster") if event["seq"] > removed["seq"] and second not in ids(event["members"])), None)
    retired = first_retire(events, removed["seq"])
    if dropped is None or retired is None or retired["seq"] < dropped["seq"]:
        verdict.fail("removed: the roster did not drop the second before the length was retired")
    verified_rest(verdict, events, [first, third], since=removed["seq"])


def judge_noref(verdict, run):
    events = run.report(1)
    standard_setup(verdict, events, run.expected)
    if first_status(events, "verified"):
        verdict.fail("verified without a reference")
    status = next((e for e in statuses(events) if e["status"].startswith("notVerified(") and "noReference" in e["status"]), None)
    if status is None:
        verdict.fail("never notVerified with noReference")
        return
    at = snapshot_after(events, status["seq"])
    if at is None or not at["lengthApplied"] or not at["isIceBarOffered"]:
        verdict.fail("not at a rest with the IceBar offered while notVerified(noReference)")


def judge_crowded(verdict, run):
    events, steps = run.report(1), run.steps
    witness = step(steps, "witness")
    length_seq = first_length_seq(events)
    if not witness or not witness.get("ok"):
        verdict.not_established((witness or {}).get("why", "no bracketed witness"))
    elif length_seq is not None and witness["seq"] >= length_seq:
        verdict.not_established("a length came before the bracketed witness")
    if length_seq is None:
        verdict.fail("no length was applied")
        return
    setup_roster(verdict, events, run.expected, length_seq)
    status = next((e for e in statuses(events, length_seq) if e["status"].startswith("notVerified(") and "stacked:" in e["status"]), None)
    at = snapshot_after(events, status["seq"]) if status else None
    if at is None or not at["lengthApplied"]:
        verdict.clause("12", False, "never notVerified(stacked) at a rest")
    else:
        verdict.clause("12", ids(at["roster"]) == sorted(run.expected["members"]), "the roster does not hold both members")
    later = step(steps, "chevronAtRest")
    if later is None:
        verdict.clause("6", False, "no « reading 15 s into the rest")
    else:
        changed = [event for event in lengths(events, length_seq) if event["seq"] <= later["seq"]]
        verdict.clause("6", bool(later.get("listed")) and not changed, "« not listed 15 s into the rest, or a length changed meanwhile")


def judge_fresh(verdict, run, report_number=1):
    events = run.report(report_number)
    _, length_seq = standard_setup(verdict, events, run.expected)
    if length_seq is None:
        return
    standard = [e for e in snapshots(events) if e["seq"] < length_seq and e["hiddenBoundaryUsable"] and not e["lengthSet"] and e["roster"]]
    if not standard:
        verdict.fail("no snapshot at standard length with the boundary usable")
    else:
        last = standard[-1]
        if sorted(ids(last["cacheHidden"]) + ids(last["cacheAlwaysHidden"])) != ids(last["roster"]):
            verdict.fail("the cache's hidden and always-hidden sections are not the roster")
        if "t2d" in SCENARIOS[run.scenario].get("clauses", []):
            hidden, always = last["hiddenDivider"], last["alwaysHiddenDivider"]
            holds = bool(hidden and always and hidden["frame"] and always["frame"] and always["frame"][0] < hidden["frame"][0])
            verdict.clause("t2d", holds, "the always-hidden divider is not left of the hidden one")
    verified_rest(verdict, events, run.expected["members"])


def judge_placed(verdict, run):
    if not os.path.exists(run.path("report-2.jsonl")):
        verdict.fail("no second start")
        return
    judge_fresh(verdict, run, report_number=2)


def judge_front(verdict, run, long_menus):
    events, steps = run.report(1), run.steps
    standard_setup(verdict, events, run.expected)
    verified = verified_rest(verdict, events, run.expected["members"])
    if verified is None:
        return
    marks = {name: step(steps, name) for name in ("front", "back")}
    for name, entry in marks.items():
        if not entry or not entry.get("ok"):
            verdict.not_established(f"could not bring the {'menus helper' if name == 'front' else 'Terminal'} forward")
            return
    if lengths(events, verified["seq"]):
        verdict.fail("a length changed after the first verified")
    after = statuses(events, verified["seq"])
    if any(event["status"].startswith(("blocked(", "failed(")) for event in after):
        verdict.fail("blocked or failed after the first verified")
    if long_menus:
        last = after[-1]["status"] if after else "verified"
        verdict.kind = "verified" if last == "verified" else ("unverified" if last.startswith("notVerified(") else "other")
        if verdict.kind == "other":
            verdict.fail(f"ended {last}")
        return
    for name, entry in marks.items():
        changed = first_status(events, "notVerified(", entry["seq"])
        if changed is None or "layoutChanged:" not in changed["status"]:
            verdict.fail(f"{name}: no layoutChanged status")
        elif first_status(events, "verified", changed["seq"]) is None:
            verdict.fail(f"{name}: not verified again")


def judge_relaunch(verdict, run):
    first = run.report(1)
    standard_setup(verdict, first, run.expected)
    verified_rest(verdict, first, run.expected["members"])
    if not os.path.exists(run.path("report-2.jsonl")):
        verdict.fail("no second start")
        return
    if verified_rest(verdict, run.report(2), run.expected["members"]) is None:
        verdict.reasons.append("(the second start)")


def blocked_common(verdict, events, needle):
    if applied_lengths(events):
        verdict.fail("a length was applied")
    if any(snap["isIceBarOffered"] for snap in snapshots(events)):
        verdict.fail("the IceBar was offered")
    if not any(e["status"].startswith("blocked(") and needle in e["status"] for e in statuses(events)):
        verdict.fail(f"never blocked({needle}...)")


def judge_positional(verdict, run):
    events, steps = run.report(1), run.steps
    latest = latest_snapshot(events)
    blockers = ids(latest["blockers"]) if latest else []
    if blockers != sorted(run.expected["blockers"]):
        verdict.not_established(f"{len(blockers)} blocker(s), expected {len(run.expected['blockers'])}")
    blocked_common(verdict, events, "positional:")
    opened = [event for event in of(events, "bar") if event["action"] == "open"]
    if not opened or not opened[0]["answer"].startswith("refused"):
        verdict.fail("bar open was not refused")
    before, after = step(steps, "frames", when="before"), step(steps, "frames", when="after")
    if not before or not after or not before["frames"] or len(before["frames"]) != len(after["frames"]):
        verdict.fail("the items' frames were not read before and after")
    elif any(abs(a - b) > 1 for x, y in zip(before["frames"], after["frames"]) for a, b in zip(x, y)):
        verdict.fail("an item moved")


def judge_inverted(verdict, run):
    events = run.report(1)
    if not any(snap["iconPlacement"] == "iconLeftOfDivider" for snap in snapshots(events)):
        verdict.not_established("Ice's icon was never read left of its divider")
    blocked_common(verdict, events, "iconLeftOfDivider")


def judge_drawn(verdict, run):
    events = run.report(1)
    if not events[0].get("holdLength"):
        verdict.not_established("the report does not hold lengths")
    if first_status(events, "verified"):
        verdict.fail("verified while lengths were held")
    if first_status(events, "failed(drawn:") is None:
        verdict.fail("never failed(drawn:...)")


def judge_incomplete(verdict, run):
    events, steps = run.report(1), run.steps
    stall, resumed, settled = step(steps, "stall"), step(steps, "resumed"), step(steps, "settled")
    if not stall or not resumed or not settled:
        verdict.fail("the runner did not reach the stall, its end and 30 s after")
        return
    rest = snapshot_at_or_before(events, stall["seq"])
    if rest is None or not rest["lengthApplied"]:
        verdict.not_established("not at a rest when the stall began")
    blocked = first_status(events, "blocked(discoveryIncomplete", stall["seq"])
    if blocked is None or blocked["seq"] > resumed["seq"]:
        verdict.fail("never blocked(discoveryIncomplete) during the stall")
        return
    retired = first_retire(events, stall["seq"])
    if rest and rest["lengthApplied"] and (retired is None or retired["seq"] > blocked["seq"]):
        verdict.fail("the length was not retired before blocked")
    before = [event for event in statuses(events) if event["seq"] <= settled["seq"]]
    if before and before[-1]["status"].startswith("blocked("):
        verdict.fail("still blocked 30 s after the stall ended")


JUDGES = {
    "noref": judge_noref, "sparse": judge_sparse, "k2": judge_sparse, "k4": judge_sparse, "k8": judge_sparse,
    "press": judge_press, "addremove": judge_addremove, "crowded": judge_crowded,
    "fresh-off": judge_fresh, "fresh-on": judge_fresh, "placed-off": judge_placed, "placed-on": judge_placed,
    "front-short": lambda verdict, run: judge_front(verdict, run, long_menus=False),
    "front-long": lambda verdict, run: judge_front(verdict, run, long_menus=True),
    "relaunch": judge_relaunch, "positional": judge_positional, "inverted": judge_inverted,
    "drawn": judge_drawn, "incomplete": judge_incomplete,
}


class ReportReader:
    """`load_report(final=False)` for a report that grows: only the complete
    lines added since the last read are parsed (the runner's waits)."""

    def __init__(self, path):
        self.path = path
        self.offset = 0
        self.events = []

    def read(self):
        try:
            with open(self.path, "rb") as handle:
                handle.seek(self.offset)
                data = handle.read()
        except FileNotFoundError:
            return self.events
        end = data.rfind(b"\n") + 1
        if end:
            chunk = data[:end]
            self.offset += end
            self.events.extend(parse_lines(chunk.split(b"\n")[:-1], first_seq=len(self.events) + 1))
            check_start(self.events)
        return self.events


def wait(path, seconds, pid, name, args, interval=0.5, clock=time.monotonic, sleep=time.sleep, alive=None):
    """Waits for a predicate in one process (D5): 0 held, 1 timed out, 3 a
    damaged report, 4 the pid ended first."""
    alive = alive or process_alive
    reader = ReportReader(path)
    deadline = clock() + seconds
    while True:
        try:
            if predicate_holds(reader.read(), name, args):
                return 0
        except Damaged:
            return 3
        if not alive(pid):
            return 4
        if clock() >= deadline:
            return 1
        sleep(interval)


def process_alive(pid):
    if pid <= 0:  # no process to watch (os.kill would signal a process group)
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


class Run:
    def __init__(self, directory):
        self.directory = directory
        self.expected = load_expected(self.path("expected.json"))
        self.scenario = self.expected["scenario"]
        self.steps = load_steps(self.path("steps.jsonl"))
        self._reports = {}

    def path(self, name):
        return os.path.join(self.directory, name)

    def report(self, number):
        if number not in self._reports:
            self._reports[number] = load_report(self.path(f"report-{number}.jsonl"))
        return self._reports[number]


def judge(directory):
    try:
        run = Run(directory)
    except (Damaged, OSError, ValueError) as error:
        verdict = Verdict(os.path.basename(directory))
        verdict.result = "aborted"
        verdict.reasons.append(str(error))
        return verdict
    verdict = Verdict(run.scenario)
    if SCENARIOS[run.scenario]["kind"] == "notRun":
        verdict.result = "notRun"
        verdict.reasons.append("needs a Command-drag of Ice's icon: moved to S5 by the owner, 2026-10-09 (S4 design D4)")
        return verdict
    try:
        events = run.report(1)
        if run.scenario != "drawn" and (events[0].get("holdLength") or any(e.get("held") for e in of(events, "length"))):
            verdict.fail("lengths were held in a scenario that must apply them")
        if run.scenario not in NO_CHECK_AT_START:
            chevron_at_start(verdict, run.steps)
        JUDGES[run.scenario](verdict, run)
        if verdict.kind is None:
            last = run.report(2) if os.path.exists(run.path("report-2.jsonl")) else events
            verdict.kind = kind_of(last)
        wanted = SCENARIOS[run.scenario]["kind"]
        accepted = {"bestEffort": {"verified", "unverified"}}.get(wanted, {wanted})
        if run.scenario not in ENDS_ELSEWHERE and verdict.kind not in accepted:
            verdict.fail(f"ended {verdict.kind}, expected {wanted}")
    except Damaged as error:
        verdict.result = "aborted"
        verdict.reasons.append(str(error))
    aborted = step(run.steps, "aborted")
    if aborted:
        verdict.result = "aborted"
        verdict.reasons.insert(0, f"the runner: {aborted.get('why', 'aborted')}")
    return verdict


# --- the matrix report ------------------------------------------------------------

def known_open_only(verdict):
    """A failure that is only a known-open clause (D4: T2d)."""
    failed = [name for name, state in verdict.get("clauses", {}).items() if state == "fail"]
    return (
        verdict["result"] == "fail"
        and bool(failed)
        and all(name in KNOWN_OPEN for name in failed)
        and all(reason.split(":")[0] in KNOWN_OPEN for reason in verdict["reasons"])
    )


def round_is_clean(verdicts):
    """Every scenario passed, known-open clauses aside (D5's stop rule)."""
    for name in ORDER:
        if SCENARIOS[name]["kind"] == "notRun":
            continue
        verdict = verdicts.get(name)
        if verdict is None or not (verdict["result"] == "pass" or known_open_only(verdict)):
            return False
    return True


def matrix(evidence):
    rounds = {}
    for entry in sorted(os.listdir(evidence)):
        path = os.path.join(evidence, entry, "verdict.json")
        number, _, name = entry.partition("-")
        if not number.isdigit() or name not in SCENARIOS or not os.path.exists(path):
            continue
        try:
            with open(path) as handle:
                verdict = json.load(handle)
        except ValueError:
            verdict = {"scenario": name, "result": "aborted", "kind": None, "clauses": {}, "reasons": ["an unreadable verdict"]}
        rounds.setdefault(int(number), {})[name] = verdict
    return rounds


def report(evidence):
    rounds = matrix(evidence)
    lines = []
    met = len(rounds) >= ROUNDS
    for number in sorted(rounds):
        verdicts = rounds[number]
        lines.append(f"-- round {number}: {'clean' if round_is_clean(verdicts) else 'not clean'}")
        for kind in ("verified", "unverified", "bestEffort", "blocked", "failed", "notRun"):
            names = [name for name in ORDER if SCENARIOS[name]["kind"] == kind and name in verdicts]
            if names:
                lines.append(f"   expected {kind}: " + ", ".join(f"{name} {verdicts[name]['result']}" for name in names))
        for name in ORDER:
            verdict = verdicts.get(name)
            if verdict and verdict["result"] not in ("pass", "notRun"):
                lines.append(f"   {name}: {verdict['result']}: " + "; ".join(verdict["reasons"][:4]))
            if SCENARIOS[name]["kind"] != "notRun" and (verdict is None or verdict["result"] != "pass"):
                met = False
    t2d_open = any(v.get("clauses", {}).get("t2d") == "fail" for r in rounds.values() for v in r.values())
    if met:
        lines.append("S4 DoD: met (every scenario passed in three rounds); scenario 14's second half is S5's (the owner's decision, 2026-10-09)")
    else:
        lines.append("S4 DoD: not met" + (" (T2d open)" if t2d_open else ""))
    print("\n".join(lines))
    return 0 if met else 1


# --- the command line -------------------------------------------------------------

def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    command, rest = argv[1], argv[2:]
    if command == "check":
        try:
            load_report(rest[0])
        except Damaged as error:
            print(error)
            return 3
        return 0
    if command == "wait":
        return wait(rest[0], float(rest[1]), int(rest[2]), rest[3], rest[4:])
    if command == "await":
        try:
            events = load_report(rest[0], final=False)
        except Damaged as error:
            print(error)
            return 3
        return 0 if predicate_holds(events, rest[1], rest[2:]) else 1
    if command == "bracket":
        try:
            print(bracket_key(load_report(rest[0], final=False)))
        except Damaged:
            print("")
        return 0
    if command == "selfread-frames":
        print(json.dumps(selfread_frames(rest[0], rest[1])))
        return 0
    if command == "judge":
        verdict = judge(rest[0])
        print(json.dumps(verdict.json(), sort_keys=True))
        return 0 if verdict.result == "pass" else 1
    if command == "clean":
        return 0 if round_is_clean(matrix(rest[0]).get(int(rest[1]), {})) else 1
    if command == "report":
        return report(rest[0])
    if command == "order":
        print(" ".join(ORDER))
        return 0
    raise SystemExit(f"lab-tool: unknown command {command}")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
