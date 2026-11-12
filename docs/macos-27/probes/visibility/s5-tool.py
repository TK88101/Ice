#!/usr/bin/env python3
"""The owner's acceptance sitting's judge (plan 2026-11-12-s5-owner-acceptance, D7).

Pure: it reads what run-s5.sh left in the sitting's directory and decides.
Run by run-s5.sh as `python3 -I -B s5-tool.py ...`, tested by test_s5_tool.py on
synthetic input. Nothing here starts a process or touches the bar. The
report's reading and its damage rules are lab-tool.py's, loaded from beside
this file.

The sitting's directory holds:
  report.jsonl   Ice's lab report
  steps.jsonl    what the runner did and what the owner answered, one JSON
                 object a line: {"step", "seq", "t", ...}; `seq` is the
                 report's last line when the step was written

  s5-tool.py wait <report> <seconds> <pid> <predicate> [args]   exit 0 held, 1 timed out, 3 damaged, 4 the pid ended
  s5-tool.py check-start <report> <seconds>          exit 0 when C1 holds, else 1 with the reasons
  s5-tool.py check-helper <report> <cut> <helper> <seconds>   exit 0 when C2 holds, else 1 with the reasons
  s5-tool.py new-member <report> <cut> <helper>      the member that is not the helper, as JSON; exit 1 when none
  s5-tool.py store-diff <before> <after> <own...>    what changed outside the run's own keys, as JSON
  s5-tool.py verdict <directory>                     the verdict, as JSON; exit 0 pass, 1 otherwise
  s5-tool.py summary <verdict.json>                  the verdict in lines for the owner
"""
import importlib.util
import json
import os
import sys
import time
from typing import Any, Callable, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("labtool", os.path.join(HERE, "lab-tool.py"))
lab = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lab)

Event = dict[str, Any]
Key = dict[str, str]

# Seconds, by the report's clock: Ice's start to a settled snapshot (C1), the
# helper's start to its membership (C2). The runner's own wait for both
# (run-s5.sh's START_WAIT), which it records on its steps: this is only what
# stands when a step carries none.
START_WAIT = 120
CLAUSES = ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"]
SECTIONS = ["cacheAlwaysHidden", "cacheHidden", "cacheVisible"]
STORE_ENTRIES = "TrailingItemPreferredPositions"


# --- what a report says -----------------------------------------------------------

def key(entry: Event) -> Key:
    return {"namespace": entry["namespace"], "identifier": entry["identifier"]}


def keys(entries: list[Event]) -> list[Key]:
    return sorted((key(entry) for entry in entries), key=lambda k: (k["namespace"], k["identifier"]))


def is_complete(snap: Event) -> bool:
    return snap["completeness"] == "complete"


def is_settled(snap: Event) -> bool:
    """Complete, the divider settled at standard length: membership was
    evaluated against it."""
    return is_complete(snap) and bool(snap["hiddenBoundaryUsable"])


def start_snapshot(events: list[Event]) -> Optional[Event]:
    return next((snap for snap in lab.snapshots(events) if is_settled(snap)), None)


def ice_id(events: list[Event]) -> str:
    return events[0].get("bundleID") or ""


def owner_order(snap: Event, ice: str) -> list[Key]:
    """The owner's items in bar order: each section is sorted by frame
    (`DiscoveredCachePlan`); Ice's own and the helper's are left out."""
    return [key(item) for section in SECTIONS for item in snap[section] if item["namespace"] not in (ice, lab.TARGET)]


def time_at(events: list[Event], cut: int) -> float:
    return events[min(cut, len(events)) - 1]["t"] if cut > 0 else 0.0


def start_reasons(events: list[Event], limit: float = START_WAIT) -> list[str]:
    """Why C1 does not hold; empty when it does."""
    snap = start_snapshot(events)
    if snap is None or snap["t"] > limit:
        return [f"no complete snapshot with a settled divider within {limit:g} s of Ice's start"]
    ice, reasons = ice_id(events), []
    if snap["iconPlacement"] is not None:
        reasons.append(f"Ice's icon placement is {snap['iconPlacement']}")
    if snap["roster"]:
        reasons.append(f"{len(snap['roster'])} member(s) before the helper started")
    left = [item for section in SECTIONS[:2] for item in snap[section] if item["namespace"] != ice]
    if left:
        reasons.append(f"{len(left)} item(s) not Ice's left of the hidden divider at the start")
    return reasons


def helper_snapshot(events: list[Event], cut: int, limit: float) -> Optional[Event]:
    """The first complete snapshot after the helper's start that has a member."""
    end = time_at(events, cut) + limit
    return next((s for s in lab.snapshots(events) if s["seq"] > cut and is_complete(s) and s["roster"] and s["t"] <= end), None)


def is_ready(entry: Event) -> bool:
    return entry["condition"] == "ready" and bool(entry["pressable"])


def helper_reasons(events: list[Event], cut: int, helper: str, limit: float = START_WAIT) -> list[str]:
    """Why C2 does not hold; empty when it does."""
    snap = helper_snapshot(events, cut, limit)
    if snap is None:
        return [f"the helper did not become a member within {limit:g} s"]
    roster = snap["roster"]
    if keys(roster) != [{"namespace": lab.TARGET, "identifier": helper}]:
        return [f"the roster has {len(roster)} member(s), not the helper alone"]
    return [] if is_ready(roster[0]) else [f"the helper is {roster[0]['condition']}, not ready and pressable"]


def new_member(events: list[Event], cut: int, helper: str) -> Optional[Key]:
    """The member, after `cut`, that is not the helper: what the runner
    records as the owner's item (its `ownSeen` step)."""
    for snap in lab.snapshots(events):
        others = [entry for entry in snap["roster"] if key(entry) != {"namespace": lab.TARGET, "identifier": helper}]
        if snap["seq"] > cut and is_complete(snap) and others:
            return key(others[0])
    return None


# Discovery passes after a cut before a snapshot's lists are taken as read
# after it: one may have begun before the cut.
FRESH_PASSES = 2


def fresh_snapshots(events: list[Event], since: int, passes: int = FRESH_PASSES) -> list[Event]:
    """Complete snapshots after `since` whose discovery pass is at least
    `passes` later than the one the report had at `since`."""
    before = lab.snapshot_at_or_before(events, since)
    base = before["pass"] if before else 0
    return [snap for snap in lab.snapshots(events) if snap["seq"] > since and is_complete(snap) and snap["pass"] >= base + passes]


def rest_reasons(events: list[Event], members: list[Key], since: int, until: Optional[Event]) -> list[str]:
    """Why no verified rest holding exactly `members` lies after `since` and
    before the step `until` (the owner's answer about that rest), if any."""
    end = until["seq"] if until else len(events)
    status = lab.first_status(events, "verified", since)
    if status is None or status["seq"] > end:
        found = [event for event in lab.statuses(events, since) if event["seq"] <= end]
        return [f"never verified (last status: {found[-1]['status'] if found else 'none'})"]
    snap = lab.snapshot_after(events, status["seq"])
    if snap is None or snap["status"] != "verified":
        return ["no snapshot taken while verified"]
    reasons = []
    if keys(snap["roster"]) != members:
        reasons.append("the verified roster is not the expected members")
    if not all(is_ready(entry) for entry in snap["roster"]):
        reasons.append("a member is not ready and pressable")
    if snap["blockers"]:
        reasons.append(f"{len(snap['blockers'])} blocker(s)")
    if keys(snap["cells"]) != members or any(cell["disabled"] for cell in snap["cells"]):
        reasons.append("the IceBar's cells are not the members, each enabled")
    hidden = keys([check for check in snap["checks"] if check["outcome"] == "hidden"])
    if hidden != members:
        reasons.append("not every member's check is hidden")
    if not snap["lengthApplied"]:
        reasons.append("no length standing while verified")
    return reasons


def was_presented(events: list[Event], members: list[Key], since: int, until: Optional[Event]) -> bool:
    """The IceBar shown with exactly `members`' cells, every one enabled,
    after `since` and before the step `until` (the owner's answer about it)."""
    end = until["seq"] if until else len(events)
    return any(
        since < snap["seq"] <= end and snap["isIceBarPresented"] and keys(snap["cells"]) == members
        and not any(cell["disabled"] for cell in snap["cells"])
        for snap in lab.snapshots(events)
    )


# --- predicates the runner waits on ------------------------------------------------------

def predicate_holds(events: list[Event], name: str, args: list[str]) -> bool:
    since = int(args[0]) if args and args[0].isdigit() else 0
    if name == "settled":
        return start_snapshot(events) is not None
    if name == "members":  # <since> <count>: a complete snapshot with that many members
        return any(snap["seq"] > since and is_complete(snap) and len(snap["roster"]) == int(args[1]) for snap in lab.snapshots(events))
    if name == "fresh":  # <since>: a complete snapshot of a discovery pass begun after it
        return bool(fresh_snapshots(events, since))
    return lab.predicate_holds(events, name, args)


def wait(
    path: str, seconds: float, pid: int, holds: Callable[[list[Event]], bool], interval: float = 0.5,
    clock: Callable[[], float] = time.monotonic, sleep: Callable[[float], None] = time.sleep,
    alive: Callable[[int], bool] = lab.process_alive,
) -> int:
    """lab-tool.py's wait (which takes its own predicates by name only) with
    this file's: 0 held, 1 timed out, 3 a damaged report, 4 the pid ended first."""
    reader = lab.ReportReader(path)
    deadline = clock() + seconds
    while True:
        try:
            if holds(reader.read()):
                return 0
        except lab.Damaged:
            return 3
        if not alive(pid):
            return 4
        if clock() >= deadline:
            return 1
        sleep(interval)


# --- the store ------------------------------------------------------------------------------

def store_difference(before: Event, after: Event, own: list[str]) -> Event:
    """Keys added and removed, and how many values changed, outside the run's
    own keys (a key holding one of `own`)."""
    if not isinstance(before.get(STORE_ENTRIES), dict) or not isinstance(after.get(STORE_ENTRIES), dict):
        return {"unreadable": True}
    old, new = before[STORE_ENTRIES], after[STORE_ENTRIES]

    def foreign(name: str) -> bool:
        return not any(part in name for part in own)

    return {
        "added": sorted(name for name in new if name not in old and foreign(name)),
        "removed": sorted(name for name in old if name not in new and foreign(name)),
        "changed": sum(1 for name in old if name in new and old[name] != new[name] and foreign(name)),
    }


# --- the verdict -------------------------------------------------------------------------------

class Verdict:
    def __init__(self) -> None:
        self.clauses = {name: "notReached" for name in CLAUSES}
        self.reasons: list[str] = []
        self.notes: list[str] = []
        self.extra: Event = {}

    def settle(self, clause: str, reasons: list[str], otherwise: str = "fail") -> bool:
        """`pass` without reasons, else `otherwise` with them."""
        self.clauses[clause] = otherwise if reasons else "pass"
        self.reasons += [f"{clause}: {reason}" for reason in reasons]
        return not reasons

    def result(self, aborted: Optional[Event]) -> str:
        values = self.clauses
        if "fail" in values.values() or "changed" in values.values():
            return "fail"
        if "notEstablished" in (values["C1"], values["C2"]):
            return "notEstablished"
        if aborted:
            return "fail"
        return "pass" if set(values.values()) == {"pass"} else "partial"

    def json(self, aborted: Optional[Event]) -> Event:
        return dict(result=self.result(aborted), clauses=self.clauses, reasons=self.reasons, notes=self.notes, **self.extra)


def answer(steps: list[Event], question: str) -> Optional[Event]:
    return next((entry for entry in steps if entry["step"] == "answer" and entry.get("q") == question), None)


def answer_reasons(steps: list[Event], questions: list[str]) -> list[str]:
    found = {question: answer(steps, question) for question in questions}
    return [f"the owner answered {entry['a'] if entry else 'nothing'} to {question}" for question, entry in found.items()
            if entry is None or entry["a"] != "y"]


def timed_out(events: list[Event], steps: list[Event], clause: str) -> list[str]:
    """The runner's waits for that clause that ran out, each with the status
    Ice had then: it stopped waiting, so what the report shows later does not
    count."""
    def last_status(cut: int) -> str:
        found = [event for event in lab.statuses(events) if event["seq"] <= cut]
        return found[-1]["status"] if found else "none"

    return [f"the runner's wait for {entry.get('wait', 'Ice')} ran out (last status: {last_status(entry['seq'])})"
            for entry in steps if entry["step"] == "timedOut" and entry.get("clause") == clause]


def is_taken(verdict: Verdict, steps: list[Event], clause: str, question: str) -> bool:
    """Whether the owner took a step that may be skipped; a skip is recorded."""
    entry = answer(steps, question)
    if entry is not None and entry["a"] != "y":
        verdict.clauses[clause] = "skipped"
    return entry is not None and entry["a"] == "y"


def judge_cleanup(verdict: Verdict, steps: list[Event]) -> None:
    done = lab.step(steps, "cleanup")
    if done is None:
        verdict.settle("C7", ["the runner left no cleanup record"])
        return
    reasons = [text for name, text in (
        ("ice", "Ice or the helper did not stop"), ("domain", "the lab copy's defaults were not emptied"),
        ("prefsUnchanged", "the release Ice's settings changed"),
    ) if not done.get(name)]
    store = done.get("store")
    if not isinstance(store, dict) or store.get("unreadable"):
        store = {}
        reasons.append("MenuBarAgent's store could not be read")
    for name in ("added", "removed"):
        if store.get(name):
            reasons.append(f"{len(store[name])} key(s) {name} in MenuBarAgent's store outside the run's own")
    verdict.settle("C7", reasons)
    if store.get("changed"):
        verdict.notes.append(f"{store['changed']} stored value(s) of other items changed in MenuBarAgent's store (recorded, not a failure)")


def judge_own_item(verdict: Verdict, events: list[Event], steps: list[Event], helper: Key) -> None:
    if not is_taken(verdict, steps, "C5", "doOwn"):
        if verdict.clauses["C5"] == "skipped":
            verdict.notes.append("helper only: the owner's own item was skipped")
        return
    seen = lab.step(steps, "ownSeen")
    if seen is None or not seen.get("member"):
        blocked = lab.first_status(events, "blocked(", answer(steps, "doOwn")["seq"])
        verdict.settle("C5", [f"no second member was seen{' (' + blocked['status'] + ')' if blocked else ''}"])
        return
    # The runner's own cut: it waited for `verified` after this very line.
    chosen, cut = seen["member"], seen["seq"]
    verdict.extra["member"] = chosen
    both = keys([helper, chosen])
    listed, menu = answer(steps, "ownListed"), answer(steps, "ownMenu")
    reasons = timed_out(events, steps, "C5") or rest_reasons(events, both, cut, listed)
    # Up to the owner's answer: what Ice says while the item is dragged back later is not this step's.
    blocked = lab.first_status(events, "blocked(positional", cut)
    if blocked and blocked["seq"] <= (listed["seq"] if listed else len(events)):
        reasons.append(f"Ice said {blocked['status']}")
    if not reasons and not was_presented(events, both, cut, menu):
        reasons.append("the report never showed the IceBar with exactly the two cells enabled")
    verdict.settle("C5", reasons + answer_reasons(steps, ["ownListed", "ownMenu"]))


def judge_icon_drag(verdict: Verdict, events: list[Event], steps: list[Event]) -> None:
    if not is_taken(verdict, steps, "C6", "doInvert"):
        return
    cut = answer(steps, "doInvert")["seq"]
    reasons = timed_out(events, steps, "C6")
    blocked = lab.first_status(events, "blocked(iconLeftOfDivider", cut)
    if blocked is None:
        reasons.append("Ice never said blocked(iconLeftOfDivider) after the drag")
    else:
        snap = lab.snapshot_after(events, blocked["seq"])
        if snap is None or not snap["status"].startswith("blocked("):
            reasons.append("no snapshot taken while blocked")
        elif snap["isIceBarOffered"] or snap["lengthApplied"] or snap["calibratedHiddenLength"] is not None:
            reasons.append("an IceBar or a length stood while blocked")
        retired = lab.first_retire(events, cut)
        if retired is None or retired["seq"] > (snap["seq"] if snap else len(events)):
            reasons.append("the length was not retired before Ice said blocked")
        says = answer(steps, "paneSays")
        if says is None or lab.first_status(events, "verified", max(says["seq"], blocked["seq"])) is None:
            reasons.append("never verified again after the drag back")
    verdict.settle("C6", reasons + answer_reasons(steps, ["paneSays", "paneClear"]))


def judge_order(verdict: Verdict, events: list[Event], steps: list[Event], start: Event) -> None:
    """C8, whenever the runner took its last look at the bar: also in a
    sitting that ended at an earlier clause, since Ice and the helper ran."""
    look, stopping = lab.step(steps, "lastLook"), lab.step(steps, "stopping")
    if look is None or stopping is None:
        return
    ends = [snap for snap in fresh_snapshots(events, look["seq"]) if snap["seq"] <= stopping["seq"]]
    back = answer(steps, "itemBack")
    reasons = ["the owner did not say the item is back in its place"] if back is not None and back["a"] != "y" else []
    if ends:
        ice = ice_id(events)
        before, after = owner_order(start, ice), owner_order(ends[-1], ice)
        if before != after:
            reasons.append("the order of the owner's items changed")
            verdict.extra.update(orderBefore=before, orderAfter=after)
    if reasons or ends:
        verdict.settle("C8", reasons, otherwise="changed")
    else:
        verdict.settle("C8", ["no complete snapshot of a discovery pass begun after the runner's last look"], otherwise="notEstablished")


def judge(directory: str) -> Event:
    verdict = Verdict()
    steps = lab.load_steps(os.path.join(directory, "steps.jsonl"))
    aborted = lab.step(steps, "aborted")
    judge_cleanup(verdict, steps)
    try:
        events = lab.load_report(os.path.join(directory, "report.jsonl"))
        judge_report(verdict, events, steps)
    except lab.Damaged as error:
        verdict.reasons.append(f"the report: {error}")
        aborted = aborted or {"why": "the report is damaged"}
    if aborted:
        verdict.reasons.append(f"the sitting ended early: {aborted.get('why', 'aborted')}")
    return verdict.json(aborted)


def judge_report(verdict: Verdict, events: list[Event], steps: list[Event]) -> None:
    judge_clauses(verdict, events, steps)
    start = start_snapshot(events)
    if start is not None:
        judge_order(verdict, events, steps, start)


def judge_clauses(verdict: Verdict, events: list[Event], steps: list[Event]) -> None:
    """C1 to C6, each only once the one before it holds or was skipped."""
    started = lab.step(steps, "iceStarted") or {}
    if not verdict.settle("C1", start_reasons(events, started.get("limit", START_WAIT)), otherwise="notEstablished"):
        return
    helper_up = lab.step(steps, "helperUp")
    if helper_up is None:
        return
    helper = {"namespace": lab.TARGET, "identifier": helper_up["id"]}
    cut = helper_up["seq"]
    waited = helper_up.get("limit", START_WAIT)
    if not verdict.settle("C2", helper_reasons(events, cut, helper["identifier"], waited), otherwise="notEstablished"):
        return
    listed = answer(steps, "helperListed")
    if not verdict.settle("C3", timed_out(events, steps, "C3") or rest_reasons(events, [helper], cut, listed)):
        return
    if listed is not None:
        shown = [] if was_presented(events, [helper], cut, answer(steps, "helperMenu")) else ["the report never showed the IceBar with the helper's one cell enabled"]
        verdict.settle("C4", shown + answer_reasons(steps, ["helperListed", "helperMenu"]))
    judge_own_item(verdict, events, steps, helper)
    judge_icon_drag(verdict, events, steps)


# --- for the owner ---------------------------------------------------------------------------------

RESULTS = {
    "pass": "通過 (pass)",
    "partial": "部分通過 (partial)：做了的都過了，有步驟被跳過或沒法判定",
    "fail": "沒通過 (fail)",
    "notEstablished": "沒法開始 (notEstablished)：你的菜單欄不符合開始條件，功能本身沒被測到",
}


def item_line(item: Key) -> str:
    return f"    {item['namespace']} {item['identifier'] or '(no identifier)'}"


def summary(verdict: Event) -> list[str]:
    lines = [f"S5 結果：{RESULTS.get(verdict['result'], verdict['result'])}"]
    lines.append("  " + "  ".join(f"{name} {verdict['clauses'][name]}" for name in CLAUSES))
    lines += [f"  - {reason}" for reason in verdict["reasons"]]
    lines += [f"  ({note})" for note in verdict["notes"]]
    if "orderBefore" in verdict:
        lines.append("  你的圖標順序變了。開始前的順序（由左到右），請自己拖回去：")
        lines += [item_line(item) for item in verdict["orderBefore"]]
        lines.append("  現在的順序：")
        lines += [item_line(item) for item in verdict["orderAfter"]]
    return lines


# --- the command line ---------------------------------------------------------------------------------

def load_json(path: str) -> Event:
    with open(path) as handle:
        return json.load(handle)


def report_command(path: str, reasons: Callable[[list[Event]], list[str]]) -> int:
    try:
        found = reasons(lab.load_report(path, final=False))
    except lab.Damaged as error:
        found = [str(error)]
    if found:
        sys.stdout.write("\n".join(found) + "\n")
    return 1 if found else 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        raise SystemExit(__doc__)
    command, rest = argv[1], argv[2:]
    if command == "wait":
        return wait(rest[0], float(rest[1]), int(rest[2]), lambda events: predicate_holds(events, rest[3], rest[4:]))
    if command == "check-start":
        return report_command(rest[0], lambda events: start_reasons(events, float(rest[1])))
    if command == "check-helper":
        return report_command(rest[0], lambda events: helper_reasons(events, int(rest[1]), rest[2], float(rest[3])))
    if command == "new-member":
        try:
            found = new_member(lab.load_report(rest[0], final=False), int(rest[1]), rest[2])
        except lab.Damaged:
            found = None
        if found is None:
            return 1
        sys.stdout.write(json.dumps(found, sort_keys=True) + "\n")
        return 0
    if command == "store-diff":
        try:
            found = store_difference(load_json(rest[0]), load_json(rest[1]), rest[2:])
        except (OSError, ValueError):
            found = {"unreadable": True}
        sys.stdout.write(json.dumps(found, sort_keys=True) + "\n")
        return 0
    if command == "verdict":
        verdict = judge(rest[0])
        sys.stdout.write(json.dumps(verdict, sort_keys=True, ensure_ascii=False) + "\n")
        return 0 if verdict["result"] == "pass" else 1
    if command == "summary":
        sys.stdout.write("\n".join(summary(load_json(rest[0]))) + "\n")
        return 0
    raise SystemExit(f"s5-tool: unknown command {command}")


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as error:  # never 1: to the runner's waits that is "not yet"
        sys.stderr.write(f"s5-tool: {type(error).__name__}: {error}\n")
        sys.exit(2)
