"""Helpers for run-trace.sh (Ice's trace mode: S1, S2 design T2a, T2c) and run-remembered.sh
(remembered positions: S2 design T2b) of plan 2026-10-07-icebar-preference-hiding.

  trace-tool.py guard <store-before.json> <store-after.json> <own> [<own> ...]
      exit 0 when MenuBarAgent's store changed only in the run's own
      TrailingItemPreferredPositions entries; prints every other change (in
      that dictionary or any other top-level key) and exits 1. <own> is an
      exact key, "status:<owner>::<autosave name>", or, ending in "::", a
      prefix "status:<owner>::". What <owner> is, is MenuBarAgent's choice:
      the bundle id for the signed apps seen, the process name for the
      ad-hoc helpers (run 20261008-081444-y8GnWW); so a prefix on a lab
      bundle id (run-trace.sh) may match nothing and then allows nothing.
  trace-tool.py entry <store.json> <key>
      the position MenuBarAgent remembers under that exact key, or null.
  trace-tool.py remembered q3 <dragged side: left|right> <reads.jsonl>
  trace-tool.py remembered q4 <dragged side: left|right> <reads.jsonl> <Q3's verdict>
      the verdict of T2b's Q3 (relaunched: is the item back in the dragged
      slot) or Q4 (relaunched with a contradicting seed: is it still there)
      from three settled reads, one {"agent", "default", "side", "adjacent",
      "x"} object per line: MenuBarAgent's entry, the item's own default, its
      side of its anchor, whether it is beside it, its frame's x. The slot
      is "beside the anchor on the dragged side". A verdict needs all three
      reads to agree and a dragged slot that is not where a fresh item lands
      anyway; Q4 also needs Q3's "slotKept" as its control (without it a
      missing slot says nothing about the seed) and never says more than
      "not the slot, and on the side the seed would put it". Anything else
      is "inconclusive" with its reason, exit 1.
  trace-tool.py summary <trace.jsonl> <lab bundle id> <off|on|inv>
      one JSON object on stdout: the preferred positions per control item and
      point, the AX frames, the icon-versus-divider layout, and the placement
      verdict; two lines for a person on stderr. Exits 1 unless the trace is
      complete -- its "start" event is the one the runner asked for (marker,
      identity, always-hidden variant, steps, readings, the tool's own count
      of discovery passes), every item it declared has every point it
      declared, it reached "done", and the AX read gave a layout -- and the
      placement oracle holds (plan S2 design, T2a): in the tool's two
      discovery passes, agreeing, Ice's icon is right of its hidden divider,
      no other on-bar item is left of that divider and at least one is
      between the two; the control items are on the bar; with "on", the
      always-hidden divider is left of the hidden one; and as many other
      items are on the bar as in the baseline pass taken before Ice's items
      existed. With "inv" (S2 design, T2c: the runner wrote the icon's
      default large before launch; always-hidden off) the oracle is another:
      the trace complete and the two passes agreeing, and then, if the pass
      has the icon on the bar with its middle not right of the usable hidden
      divider's left edge, the pass must carry the notice
      ("invertedWithNotice"; without it the run fails); a layout the stored
      value did not invert is recorded as "notInverted" and passes, unless it
      carries the notice all the same.

Standard library only; run with python3 -I.
"""

import json
import sys

POSITIONS = "TrailingItemPreferredPositions"
VISIBLE = "Ice.ControlItem.Visible"
HIDDEN = "Ice.ControlItem.Hidden"
ALWAYS_HIDDEN = "Ice.ControlItem.AlwaysHidden"
MARKER = "IceLabTrace-start-v1"
SIDES = ("left", "right")
# A new item with nothing stored lands leftmost (E2), so left of its anchor: a
# slot on that side cannot be told from a fresh placement. Q4's seed is the
# smallest preferred position, so the rightmost item (P4): right of the anchor
# like a slot dragged there, but not beside it. run-remembered.sh launches and
# seeds (`seed=`) to match.
FRESH_SIDE = "left"
SETTLED_READS = 3 # run-remembered.sh's settled_reads
READ_FIELDS = ("agent", "default", "side", "adjacent", "x")
STEPS = ["stopPermissionChecks", "setSettingsInMemory", "readBaseline", "setUpSections"]
READINGS = ["ownExtras", "discover"]
DISCOVERY_PASSES = 2
# The placement verdicts a run of each variant may end on.
PASSING = {
    "off": ("dividerOthersIcon",),
    "on": ("dividerOthersIcon",),
    "inv": ("invertedWithNotice", "notInverted"),
}
# The fields of a "placement" event that are not the pass's reading itself.
PLACEMENT_ENVELOPE = ("event", "pass", "t")


def load_store(path):
    with open(path, encoding="utf-8") as handle:
        store = json.load(handle)
    if not isinstance(store, dict) or not isinstance(store.get(POSITIONS, {}), dict):
        raise ValueError(f"{path}: not a MenuBarAgent store")
    return store


def is_own_pattern(own):
    """An exact key or, ending in "::", a prefix: nothing looser (a bare bundle id is neither)."""
    return own.startswith("status:") and "::" in own


def is_own(key, owns):
    return any(key.startswith(own) if own.endswith("::") else key == own for own in owns)


def changes(before, after, skip=lambda key: False):
    return [
        {"key": key, "before": before.get(key), "after": after.get(key)}
        for key in sorted(set(before) | set(after))
        if not skip(key) and before.get(key) != after.get(key)
    ]


def foreign_changes(before, after, owns):
    """Everything outside the run's own position entries that changed."""
    outside = changes(before, after, skip=lambda key: key == POSITIONS)
    inside = changes(before.get(POSITIONS, {}), after.get(POSITIONS, {}), skip=lambda key: is_own(key, owns))
    return outside + inside


def own_entries(store, owns):
    return {key: value for key, value in store.get(POSITIONS, {}).items() if is_own(key, owns)}


def guard(before_path, after_path, owns):
    before = load_store(before_path)
    after = load_store(after_path)
    found = foreign_changes(before, after, owns)
    print(json.dumps({
        "foreignChanges": found,
        "labEntriesBefore": own_entries(before, owns),
        "labEntriesAfter": own_entries(after, owns),
    }, sort_keys=True))
    return 1 if found else 0


def entry(store_path, key):
    print(json.dumps(load_store(store_path).get(POSITIONS, {}).get(key)))
    return 0


def remembered_verdict(question, dragged_side, reads, control=None):
    """(verdict, why it is inconclusive or None) from the settled reads after a relaunch.

    `control` is Q3's verdict, for Q4."""
    if len(reads) != SETTLED_READS:
        return "inconclusive", "readCount"
    if any(read != reads[0] for read in reads):
        return "inconclusive", "readsDisagree"
    side, adjacent = reads[0]["side"], reads[0]["adjacent"]
    if side not in SIDES:
        return "inconclusive", "sideUnread"
    if dragged_side == FRESH_SIDE:
        return "inconclusive", "slotOnTheFreshSide"
    if question == "q4" and control != "slotKept":
        return "inconclusive", "noSlotKeptControl"
    if side == FRESH_SIDE:
        return ("slotLost" if question == "q3" else "neitherSlotNorSeed"), None
    if not isinstance(adjacent, bool):
        return "inconclusive", "adjacencyUnread"
    if question == "q3":
        return ("slotKept" if adjacent else "elsewhereOnTheDraggedSide"), None
    return ("rememberedSlotWins" if adjacent else "seedCompatibleNotSlot"), None


def remembered(question, dragged_side, path, control=None):
    reads = [{field: event.get(field) for field in READ_FIELDS} for event in read_events(path)]
    verdict, reason = remembered_verdict(question, dragged_side, reads, control)
    print(json.dumps({"question": question, "draggedSide": dragged_side, "control": control, "verdict": verdict, "reason": reason, "reads": reads}, sort_keys=True))
    return 1 if verdict == "inconclusive" else 0


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
    """P2's question: is Ice's icon right of its hidden divider? IceCore's boundary: the divider's minX."""
    if icon is None or divider is None:
        return "unknown"
    return "iconRightOfDivider" if mid_x(icon) > divider[0] else "iconLeftOfDivider"


def start_mismatches(start, bundle_id, variant):
    """How the trace's own announcement differs from what the runner asked for."""
    expected = {
        "mode": MARKER,
        "bundleID": bundle_id,
        "alwaysHiddenSection": variant == "on",
        "steps": STEPS,
        "readings": READINGS,
        "discoveryPasses": DISCOVERY_PASSES,
    }
    return [key for key, value in expected.items() if start.get(key) != value]


def failed_clauses(reading, baseline, on_bar, variant):
    """The oracle's clauses one discovery pass's reading does not meet, by name.

    `baseline` is the pass taken before any control item existed."""
    always_hidden, hidden = reading.get("alwaysHiddenDivider"), reading.get("hiddenDivider")
    expected_on_bar = [VISIBLE, HIDDEN] + ([ALWAYS_HIDDEN] if variant == "on" else [])
    clauses = {
        # null is IceCore's "right of the divider"; an absent key is not.
        "iconRightOfDivider": "iconPlacement" in reading and reading["iconPlacement"] is None,
        "noOthersLeftOfDivider": reading.get("othersLeftOfHiddenDivider") == 0,
        # None between would mean the pass saw no other item and proves nothing.
        "othersBetween": (reading.get("othersBetween") or 0) >= 1,
        "alwaysHiddenLeftOfHidden": variant != "on" or bool(always_hidden and hidden and always_hidden[0] < hidden[0]),
        "controlItemsOnBar": all(on_bar.get(item) is True for item in expected_on_bar)
        and reading.get("iconOnBar") is True
        and reading.get("hiddenDividerUsable") is True
        and (variant != "on" or reading.get("alwaysHiddenDividerUsable") is True),
        "passComplete": reading.get("complete") is True and reading.get("ownReadOk") is True,
        # As many other items on the bar as before Ice's items were added:
        # the new leftmost divider pushed none of them off it.
        "noneDisplaced": baseline.get("complete") is True and baseline.get("othersOnBar") == reading.get("othersOnBar"),
    }
    return [name for name, holds in clauses.items() if not holds]


def inverted_verdict(reading):
    """The `inv` variant's verdict on one pass: is it inverted by its own frames, and does it say so?

    The frames are judged here, apart from the app's rule, whose word is the notice being checked."""
    inverted = (
        reading.get("iconOnBar") is True and reading.get("hiddenDividerUsable") is True
        and layout(reading.get("icon"), reading.get("hiddenDivider")) == "iconLeftOfDivider"
    )
    noticed = reading.get("notice") == "iconLeftOfDivider"
    if inverted:
        return "invertedWithNotice" if noticed else "invertedWithoutNotice"
    return "noticeWithoutInversion" if noticed else "notInverted"


def placement(events, baseline, on_bar, variant):
    """(verdict, failed clauses, the readings): judged on the last pass, and only if every pass agrees."""
    passes = sorted((event for event in events if event.get("event") == "placement"), key=lambda event: event.get("pass", 0))
    readings = [{key: value for key, value in event.items() if key not in PLACEMENT_ENVELOPE} for event in passes]
    numbered = [event.get("pass") for event in passes] == list(range(1, DISCOVERY_PASSES + 1))
    if not numbered or not all(reading.get("discovered") is True for reading in [baseline] + readings):
        return "missing", [], readings
    if any(reading != readings[-1] for reading in readings):
        return "indeterminate", [], readings
    if variant == "inv":
        return inverted_verdict(readings[-1]), [], readings
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
    baseline = next((event for event in events if event.get("event") == "baseline"), {})
    baseline_on_bar = baseline.get("othersOnBar")
    verdict, failed, readings = placement(events, baseline, on_bar, variant)
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
          f"iconPlacement={last.get('iconPlacement')} notice={last.get('notice')} "
          f"alwaysHiddenDivider={last.get('alwaysHiddenDivider')} othersLeft={last.get('othersLeftOfHiddenDivider')} "
          f"between={last.get('othersBetween')} rightOfIcon={last.get('othersRightOfIcon')} unplaced={last.get('othersUnplaced')} "
          f"onBar={last.get('othersOnBar')} onBarBefore={baseline_on_bar} baselineComplete={baseline.get('complete')} "
          f"baselineAttempts={baseline.get('attempts')} baselineFailedReads={baseline.get('failedReads')}",
          file=sys.stderr)
    return 0 if complete and verdict in PASSING[variant] else 1


def main(argv):
    if len(argv) >= 5 and argv[1] == "guard" and all(is_own_pattern(own) for own in argv[4:]):
        return guard(argv[2], argv[3], argv[4:])
    if len(argv) == 4 and argv[1] == "entry" and is_own_pattern(argv[3]) and not argv[3].endswith("::"):
        return entry(argv[2], argv[3])
    if len(argv) == 5 and argv[1:3] == ["remembered", "q3"] and argv[3] in SIDES:
        return remembered("q3", argv[3], argv[4])
    if len(argv) == 6 and argv[1:3] == ["remembered", "q4"] and argv[3] in SIDES:
        return remembered("q4", argv[3], argv[4], argv[5])
    if len(argv) == 5 and argv[1] == "summary" and argv[4] in PASSING:
        return summary(argv[2], argv[3], argv[4])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
