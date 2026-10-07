"""Ice trace mode helpers for run-trace.sh (plan 2026-10-07-icebar-preference-hiding, S1).

  trace-tool.py guard <store-before.json> <store-after.json> <lab bundle id>
      exit 0 when MenuBarAgent's store changed only in the lab identity's own
      TrailingItemPreferredPositions entries; prints every other change (in
      that dictionary or any other top-level key) and exits 1.
  trace-tool.py summary <trace.jsonl> <lab bundle id> <off|on>
      one JSON object on stdout: the preferred positions per control item and
      point, the AX frames, and the layout verdict (icon right or left of the
      hidden divider); one line for a person on stderr. Exits 1 unless the
      trace is complete: its "start" event is the one the runner asked for
      (marker, identity, always-hidden variant, steps), every item it declared
      has every point it declared, it reached "done", and the AX read gave a
      layout.

Standard library only; run with python3 -I.
"""

import json
import sys

POSITIONS = "TrailingItemPreferredPositions"
VISIBLE = "Ice.ControlItem.Visible"
HIDDEN = "Ice.ControlItem.Hidden"
MARKER = "IceLabTrace-start-v1"
STEPS = ["stopPermissionChecks", "setSettingsInMemory", "setUpSections"]


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
    }
    return [key for key, value in expected.items() if start.get(key) != value]


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
        "onBar": {item: event.get("isAddedToMenuBar") for item, event in windows.items()},
        "layoutAX": layout_ax,
        "layoutWindow": layout(windows.get(VISIBLE, {}).get("frame"), windows.get(HIDDEN, {}).get("frame")),
    }
    print(json.dumps(result, sort_keys=True))
    print(f"   layoutAX={layout_ax} layoutWindow={result['layoutWindow']} axTrusted={result['axTrusted']} "
          f"onBar={result['onBar']} missing={missing} startMismatches={mismatches}", file=sys.stderr)
    return 0 if complete else 1


def main(argv):
    if len(argv) == 5 and argv[1] == "guard":
        return guard(argv[2], argv[3], argv[4])
    if len(argv) == 5 and argv[1] == "summary" and argv[4] in ("off", "on"):
        return summary(argv[2], argv[3], argv[4])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
