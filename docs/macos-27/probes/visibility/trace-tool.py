"""Ice trace mode helpers for run-trace.sh (plan 2026-10-07-icebar-preference-hiding, S1).

  trace-tool.py guard <store-before.json> <store-after.json> <lab bundle id>
      exit 0 when MenuBarAgent's store changed only in the lab identity's own
      TrailingItemPreferredPositions entries; prints every other change (in
      that dictionary or any other top-level key) and exits 1.
  trace-tool.py summary <trace.jsonl> <lab bundle id> <off|on>
      one JSON object on stdout: the preferred positions per control item and
      point, the AX frames, the icon-versus-divider layout, and the placement
      verdict; one line for a person on stderr. Exits 1 unless the trace is
      complete -- its "start" event is the one the runner asked for (marker,
      identity, always-hidden variant, steps), every item it declared has
      every point it declared, it reached "done", and the AX read gave a
      layout -- and the placement oracle holds (plan S2 design, T2a): in the
      discovery passes the trace declared, all agreeing, the hidden divider,
      then every other item, then Ice's icon; on the bar; with "on", the
      always-hidden divider left of the hidden one.

Standard library only; run with python3 -I.
"""

import json
import sys

POSITIONS = "TrailingItemPreferredPositions"
VISIBLE = "Ice.ControlItem.Visible"
HIDDEN = "Ice.ControlItem.Hidden"
ALWAYS_HIDDEN = "Ice.ControlItem.AlwaysHidden"
MARKER = "IceLabTrace-start-v1"
STEPS = ["stopPermissionChecks", "setSettingsInMemory", "readBaseline", "setUpSections"]
READINGS = ["ownExtras", "discoverTwice"]
# The fields of a "placement" event that are not the pass's reading itself.
PLACEMENT_ENVELOPE = ("event", "pass", "t")


def load_store(path):
    with open(path, encoding="utf-8") as handle:
        store = json.load(handle)
    if not isinstance(store, dict) or not isinstance(store.get(POSITIONS, {}), dict):
        raise ValueError(f"{path}: not a MenuBarAgent store")
    return store


def own_prefix(bundle_id):
    """MenuBarAgent keys a remembered position as status:<bundle id>::<autosave name> (P4)."""
    return f"status:{bundle_id}::"


def changes(before, after, skip=lambda key: False):
    return [
        {"key": key, "before": before.get(key), "after": after.get(key)}
        for key in sorted(set(before) | set(after))
        if not skip(key) and before.get(key) != after.get(key)
    ]


def foreign_changes(before, after, bundle_id):
    """Everything outside the lab identity's own position entries that changed."""
    own = own_prefix(bundle_id)
    outside = changes(before, after, skip=lambda key: key == POSITIONS)
    inside = changes(before.get(POSITIONS, {}), after.get(POSITIONS, {}), skip=lambda key: key.startswith(own))
    return outside + inside


def own_entries(store, bundle_id):
    own = own_prefix(bundle_id)
    return {key: value for key, value in store.get(POSITIONS, {}).items() if key.startswith(own)}


def guard(before_path, after_path, bundle_id):
    before = load_store(before_path)
    after = load_store(after_path)
    found = foreign_changes(before, after, bundle_id)
    print(json.dumps({
        "foreignChanges": found,
        "labEntriesBefore": own_entries(before, bundle_id),
        "labEntriesAfter": own_entries(after, bundle_id),
    }, sort_keys=True))
    return 1 if found else 0


def read_events(path):
    events = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("{"):
                events.append(json.loads(line))
    return events


def mid_x(frame):
    return frame[0] + frame[2] / 2 if frame else None


def layout(icon, divider):
    """P2's question: is Ice's icon right of its hidden divider?"""
    if icon is None or divider is None:
        return "unknown"
    return "iconRightOfDivider" if mid_x(icon) > mid_x(divider) else "iconLeftOfDivider"


def start_mismatches(start, bundle_id, variant):
    """How the trace's own announcement differs from what the runner asked for."""
    expected = {
        "mode": MARKER,
        "bundleID": bundle_id,
        "alwaysHiddenSection": variant == "on",
        "steps": STEPS,
        "readings": READINGS,
    }
    return [key for key, value in expected.items() if start.get(key) != value]


def failed_clauses(reading, baseline, on_bar, variant):
    """The oracle's clauses one discovery pass's reading does not meet, by name.

    `baseline` is the pass taken before any control item existed."""
    always_hidden, hidden = reading.get("alwaysHiddenDivider"), reading.get("hiddenDivider")
    expected_on_bar = [VISIBLE, HIDDEN] + ([ALWAYS_HIDDEN] if variant == "on" else [])
    clauses = {
        "iconRightOfDivider": reading.get("iconPlacement") == "right",
        "noOthersLeftOfDivider": reading.get("othersLeftOfHiddenDivider") == 0,
        # None between would mean the pass saw no other item and proves nothing.
        "othersBetween": (reading.get("othersBetween") or 0) >= 1,
        "alwaysHiddenLeftOfHidden": variant != "on" or bool(always_hidden and hidden and always_hidden[0] < hidden[0]),
        "controlItemsOnBar": all(on_bar.get(item) is True for item in expected_on_bar)
        and reading.get("hiddenDividerUsable") is True
        and (variant != "on" or reading.get("alwaysHiddenDividerUsable") is True),
        "passComplete": reading.get("complete") is True and reading.get("ownReadOk") is True,
        # As many other items on the bar as before Ice's items were added:
        # the new leftmost divider pushed none of them off it.
        "noneDisplaced": baseline.get("complete") is True and baseline.get("othersOnBar") == reading.get("othersOnBar"),
    }
    return [name for name, holds in clauses.items() if not holds]


def placement(events, declared_passes, on_bar, variant):
    """(verdict, failed clauses, the readings): judged on the last pass, and only if every pass agrees."""
    passes = sorted((event for event in events if event.get("event") == "placement"), key=lambda event: event.get("pass", 0))
    readings = [{key: value for key, value in event.items() if key not in PLACEMENT_ENVELOPE} for event in passes]
    baseline = next((event for event in events if event.get("event") == "baseline"), {})
    discovered = [baseline] + readings
    if not declared_passes or len(readings) != declared_passes or not all(reading.get("discovered") is True for reading in discovered):
        return "missing", [], readings
    if any(reading != readings[-1] for reading in readings):
        return "indeterminate", [], readings
    failed = failed_clauses(readings[-1], baseline, on_bar, variant)
    return ("failed" if failed else "dividerOthersIcon"), failed, readings


def summary(path, bundle_id, variant):
    events = read_events(path)
    start = next((event for event in events if event.get("event") == "start"), {})
    points = {}
    for event in events:
        if event.get("event") == "point":
            position = (event.get("defaults") or {}).get("Preferred Position")
            points.setdefault(event.get("item"), {})[event.get("point")] = position
    ax = next((event for event in events if event.get("event") == "ax"), {})
    ax_frames = {item.get("identifier"): item.get("frame") for item in ax.get("items", [])}
    windows = {event.get("item"): event for event in events if event.get("event") == "window"}
    done = any(event.get("event") == "done" for event in events)
    declared_items = start.get("items") or []
    declared_points = start.get("points") or []
    missing = [f"{item}:{point}" for item in declared_items for point in declared_points if point not in points.get(item, {})]
    mismatches = start_mismatches(start, bundle_id, variant)
    if not declared_items or not declared_points:
        mismatches.append("nothing declared")
    layout_ax = layout(ax_frames.get(VISIBLE), ax_frames.get(HIDDEN))
    complete = done and not missing and not mismatches and layout_ax != "unknown"
    on_bar = {item: event.get("isAddedToMenuBar") for item, event in windows.items()}
    verdict, failed, readings = placement(events, start.get("discoveryPasses"), on_bar, variant)
    baseline_on_bar = next((event.get("othersOnBar") for event in events if event.get("event") == "baseline"), None)
    result = {
        "complete": complete,
        "done": done,
        "startMismatches": mismatches,
        "missingPoints": missing,
        "refusedOrCapped": [event for event in events if event.get("event") in ("refused", "cap")],
        "preferredPositions": points,
        "axTrusted": ax.get("trusted"),
        "axFrames": ax_frames,
        "windowFrames": {item: event.get("frame") for item, event in windows.items()},
        "onBar": on_bar,
        "layoutAX": layout_ax,
        "layoutWindow": layout(windows.get(VISIBLE, {}).get("frame"), windows.get(HIDDEN, {}).get("frame")),
        "placement": verdict,
        "failedClauses": failed,
        "placementPasses": readings,
        "othersOnBarBefore": baseline_on_bar,
    }
    print(json.dumps(result, sort_keys=True))
    print(f"   layoutAX={layout_ax} layoutWindow={result['layoutWindow']} axTrusted={result['axTrusted']} "
          f"onBar={result['onBar']} missing={missing} startMismatches={mismatches}", file=sys.stderr)
    last = readings[-1] if readings else {}
    print(f"   placement={verdict} failedClauses={failed} hiddenDivider={last.get('hiddenDivider')} icon={last.get('icon')} "
          f"alwaysHiddenDivider={last.get('alwaysHiddenDivider')} othersLeft={last.get('othersLeftOfHiddenDivider')} "
          f"between={last.get('othersBetween')} rightOfIcon={last.get('othersRightOfIcon')} unplaced={last.get('othersUnplaced')} "
          f"onBar={last.get('othersOnBar')} onBarBefore={baseline_on_bar}",
          file=sys.stderr)
    return 0 if complete and verdict == "dividerOthersIcon" else 1


def main(argv):
    if len(argv) == 5 and argv[1] == "guard":
        return guard(argv[2], argv[3], argv[4])
    if len(argv) == 5 and argv[1] == "summary" and argv[4] in ("off", "on"):
        return summary(argv[2], argv[3], argv[4])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
