"""Ice trace mode helpers for run-trace.sh (plan 2026-10-07-icebar-preference-hiding, S1).

  trace-tool.py guard <store-before.json> <store-after.json> <lab bundle id>
      exit 0 when MenuBarAgent's TrailingItemPreferredPositions changed only in
      the lab identity's own entries; prints every other change and exits 1.
  trace-tool.py summary <trace.jsonl>
      one JSON object: the five-point preferred positions per control item,
      the AX frames, and the layout verdict (icon right or left of the hidden
      divider). Exits 1 when the trace did not reach its "done" event.

Standard library only; run with python3 -I.
"""

import json
import sys

POSITIONS = "TrailingItemPreferredPositions"
VISIBLE = "Ice.ControlItem.Visible"
HIDDEN = "Ice.ControlItem.Hidden"


def load_positions(path):
    with open(path, encoding="utf-8") as handle:
        store = json.load(handle)
    positions = store.get(POSITIONS, {})
    if not isinstance(positions, dict):
        raise ValueError(f"{path}: {POSITIONS} is not a dictionary")
    return positions


def foreign_changes(before, after, bundle_id):
    """Keys outside the lab identity that were added, removed or changed."""
    own = f"status:{bundle_id}::"
    changes = []
    for key in sorted(set(before) | set(after)):
        if key.startswith(own):
            continue
        if before.get(key) != after.get(key):
            changes.append({"key": key, "before": before.get(key), "after": after.get(key)})
    return changes


def own_entries(positions, bundle_id):
    own = f"status:{bundle_id}::"
    return {key: value for key, value in positions.items() if key.startswith(own)}


def guard(before_path, after_path, bundle_id):
    before = load_positions(before_path)
    after = load_positions(after_path)
    changes = foreign_changes(before, after, bundle_id)
    print(json.dumps({
        "foreignChanges": changes,
        "labEntriesBefore": own_entries(before, bundle_id),
        "labEntriesAfter": own_entries(after, bundle_id),
    }, sort_keys=True))
    return 1 if changes else 0


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


def summary(path):
    events = read_events(path)
    points = {}
    for event in events:
        if event.get("event") == "point":
            position = event.get("defaults", {}).get("Preferred Position")
            points.setdefault(event["item"], {})[event["point"]] = position
    ax = next((event for event in events if event.get("event") == "ax"), {})
    ax_frames = {item.get("identifier"): item.get("frame") for item in ax.get("items", [])}
    windows = {event["item"]: event for event in events if event.get("event") == "window"}
    done = any(event.get("event") == "done" for event in events)
    result = {
        "done": done,
        "refusedOrCapped": [event for event in events if event.get("event") in ("refused", "cap")],
        "preferredPositions": points,
        "axTrusted": ax.get("trusted"),
        "axFrames": ax_frames,
        "windowFrames": {item: event.get("frame") for item, event in windows.items()},
        "onBar": {item: event.get("isAddedToMenuBar") for item, event in windows.items()},
        "layoutAX": layout(ax_frames.get(VISIBLE), ax_frames.get(HIDDEN)),
        "layoutWindow": layout(windows.get(VISIBLE, {}).get("frame"), windows.get(HIDDEN, {}).get("frame")),
    }
    print(json.dumps(result, sort_keys=True))
    return 0 if done else 1


def main(argv):
    if len(argv) == 5 and argv[1] == "guard":
        return guard(argv[2], argv[3], argv[4])
    if len(argv) == 3 and argv[1] == "summary":
        return summary(argv[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
