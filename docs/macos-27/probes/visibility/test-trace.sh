#!/bin/zsh
# Tests for trace-tool.py (plan 2026-10-07-icebar-preference-hiding, S1 and S2
# design T2a, T2b) on synthetic stores, traces and reads. No app is launched and
# nothing is written outside a temporary directory; two files of the repo are
# read (LabTraceRule.swift and run-trace.sh, for the identity prefix).
#
#   test-trace.sh
set -uo pipefail
tool=${0:A:h}/trace-tool.py
tmp=$(mktemp -d) || exit 1
trap 'rm -rf $tmp' EXIT
failures=0

check() { # <name> <expected exit> <command...>
    local name=$1 expected=$2
    shift 2
    "$@" > $tmp/out 2>&1
    local actual=$?
    if [[ $actual == $expected ]]; then
        print -- "ok   $name"
    else
        print -- "FAIL $name (exit $actual, expected $expected)"; cat $tmp/out
        failures=$((failures + 1))
    fi
}

contains() { # <name> <text>: in the output of the check just before
    if grep -qF -- "$2" $tmp/out; then print -- "ok   $1"; else print -- "FAIL $1: no '$2'"; cat $tmp/out; failures=$((failures + 1)); fi
}

lab=com.icespike4.trace.r1
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3}}' > $tmp/before.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3, "status:com.icespike4.trace.r1::Ice.ControlItem.Hidden": 1}}' > $tmp/lab-only.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 150, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3}}' > $tmp/moved.json
print -- '{"TrailingItemPreferredPositions": {"status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3}}' > $tmp/removed.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 4}}' > $tmp/sibling.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3}, "OtherKey": 1}' > $tmp/other-key.json
print -- '{}' > $tmp/empty.json
print -- '[]' > $tmp/not-a-store.json

check "guard: no change passes" 0 python3 -I $tool guard $tmp/before.json $tmp/before.json "status:$lab::"
check "guard: a new entry of the lab identity passes" 0 python3 -I $tool guard $tmp/before.json $tmp/lab-only.json "status:$lab::"
contains "guard: the lab entry is reported" '"status:com.icespike4.trace.r1::Ice.ControlItem.Hidden": 1'
check "guard: a moved owner entry fails" 1 python3 -I $tool guard $tmp/before.json $tmp/moved.json "status:$lab::"
contains "guard: the moved entry is named" '"key": "status:com.example.a::x"'
check "guard: a removed owner entry fails" 1 python3 -I $tool guard $tmp/before.json $tmp/removed.json "status:$lab::"
check "guard: another lab identity (r10 vs r1) is not the run's own" 1 python3 -I $tool guard $tmp/before.json $tmp/sibling.json "status:$lab::"
check "guard: a change to another top-level key of the store fails" 1 python3 -I $tool guard $tmp/before.json $tmp/other-key.json "status:$lab::"
contains "guard: the other key is named" '"key": "OtherKey"'
check "guard: a store with no dictionary yet passes" 0 python3 -I $tool guard $tmp/empty.json $tmp/empty.json "status:$lab::"
check "guard: something that is not a store does not pass" 1 python3 -I $tool guard $tmp/not-a-store.json $tmp/empty.json "status:$lab::"
check "usage: wrong arguments exit 2" 2 python3 -I $tool guard $tmp/before.json

start() { # [always-hidden: true|false] [bundle id]: the start event a trace announces
    print -- "{\"event\":\"start\",\"mode\":\"IceLabTrace-start-v1\",\"bundleID\":\"${2:-$lab}\",\"alwaysHiddenSection\":${1:-false},\"steps\":[\"stopPermissionChecks\",\"setSettingsInMemory\",\"readBaseline\",\"setUpSections\"],\"points\":[\"beforeSeed\",\"afterSeed\",\"afterStatusItem\",\"afterAutosaveName\",\"afterMainQueueTurn\"],\"items\":[\"Ice.ControlItem.Visible\",\"Ice.ControlItem.Hidden\",\"Ice.ControlItem.AlwaysHidden\"],\"readings\":[\"ownExtras\",\"discover\"],\"discoveryPasses\":2,\"t\":0}"
}
placement() { # <pass> <icon minX> <hidden minX> <always-hidden minX|null> <others left> <between> [extra json fields]: one discovery pass
    local icon=$2 hidden=$3 always=null usable=false verdict=null
    [[ $4 != null ]] && { always="[$4,4.5,18,24]"; usable=true; }
    (( icon + 17.5 > hidden )) || verdict='\"iconLeftOfDivider\"'
    print -- "{\"event\":\"placement\",\"pass\":$1,\"discovered\":true,\"icon\":[$icon,4.5,35,24],\"iconOnBar\":true,\"hiddenDivider\":[$hidden,4.5,18,24],\"hiddenDividerUsable\":true,\"alwaysHiddenDivider\":$always,\"alwaysHiddenDividerUsable\":$usable,\"iconPlacement\":$verdict,\"othersLeftOfHiddenDivider\":$5,\"othersBetween\":$6,\"othersRightOfIcon\":2,\"othersUnplaced\":0,\"othersOnBar\":$(($5 + $6 + 2)),\"complete\":true,\"ownReadOk\":true${7:+,$7},\"t\":4}"
}
both() { # <placement's arguments after the pass>: two agreeing passes
    placement 1 "$@"
    placement 2 "$@"
}
trace() { # <always-hidden: true|false> <placement lines...>: a finished trace with the given passes
    local always=$1
    shift
    start $always
    print -- "{\"event\":\"baseline\",\"discovered\":true,\"othersOnBar\":${baseline_on_bar:-14},\"othersUnplaced\":14,\"complete\":true,\"t\":1}"
    points
    print -- '{"event":"window","item":"Ice.ControlItem.Visible","isAddedToMenuBar":true,"frame":[1508,0,35,24],"t":3}'
    print -- '{"event":"window","item":"Ice.ControlItem.Hidden","isAddedToMenuBar":true,"frame":[1009,0,18,24],"t":3}'
    print -- "{\"event\":\"window\",\"item\":\"Ice.ControlItem.AlwaysHidden\",\"isAddedToMenuBar\":$always,\"frame\":[990,0,18,24],\"t\":3}"
    print -- '{"event":"ax","trusted":true,"items":[{"identifier":"Ice.ControlItem.Visible","frame":[1508,0,35,24]},{"identifier":"Ice.ControlItem.Hidden","frame":[1009,0,18,24]}],"t":3.1}'
    print -l -- "$@"
    print -- '{"event":"done","t":5}'
}
points() { # the five points of all three control items
    local item point
    for item in Visible Hidden AlwaysHidden; do
        for point in beforeSeed afterSeed afterStatusItem afterAutosaveName afterMainQueueTurn; do
            print -- "{\"event\":\"point\",\"item\":\"Ice.ControlItem.$item\",\"point\":\"$point\",\"defaults\":{\"Preferred Position\":0.1},\"t\":0.01}"
        done
    done
}
{
    start
    points
    print -- '{"event":"window","item":"Ice.ControlItem.Visible","isAddedToMenuBar":true,"frame":[1285,0,25,24],"t":3}'
    print -- '{"event":"window","item":"Ice.ControlItem.Hidden","isAddedToMenuBar":true,"frame":[1469,0,20,24],"t":3}'
    print -- '{"event":"ax","trusted":true,"items":[{"identifier":"Ice.ControlItem.Visible","frame":[1285,0,25,24]},{"identifier":"Ice.ControlItem.Hidden","frame":[1469,0,20,24]}],"t":3.1}'
    print -- '{"event":"baseline","discovered":true,"othersOnBar":11,"othersUnplaced":11,"complete":true,"t":1}'
    both 1285 1469 null 9 0
    print -- '{"event":"done","t":3.2}'
} > $tmp/left.jsonl
check "summary: a complete trace with P2's layout exits 1: the placement oracle fails" 1 python3 -I $tool summary $tmp/left.jsonl $lab off
contains "summary: P2's layout is recognised" '"layoutAX": "iconLeftOfDivider"'
contains "summary: the trace itself is complete" '"complete": true'
contains "summary: the failed clause is named" '"iconRightOfDivider"'
contains "summary: the window frames agree" '"layoutWindow": "iconLeftOfDivider"'
contains "summary: the five-point values are kept" '"afterSeed": 0.1'

grep -v '"point":"afterSeed"' $tmp/left.jsonl | grep -v 'Hidden","point":"afterMainQueueTurn"' > $tmp/gap.jsonl
check "summary: a finished trace missing points exits 1 (no false green)" 1 python3 -I $tool summary $tmp/gap.jsonl $lab off
contains "summary: the missing points are named" '"Ice.ControlItem.Visible:afterSeed"'
grep -v '"event":"ax"' $tmp/left.jsonl > $tmp/noax.jsonl
check "summary: a finished trace with no AX layout exits 1" 1 python3 -I $tool summary $tmp/noax.jsonl $lab off
check "summary: the on variant asked, the off variant run, exits 1" 1 python3 -I $tool summary $tmp/left.jsonl $lab on
contains "summary: the variant mismatch is named" '"alwaysHiddenSection"'
check "summary: another identity's trace exits 1" 1 python3 -I $tool summary $tmp/left.jsonl com.icespike4.trace.r2 off
contains "summary: the identity mismatch is named" '"bundleID"'
{ print -- '{"event":"start","t":0}'; grep -v '"event":"start"' $tmp/left.jsonl } > $tmp/bare-start.jsonl
check "summary: a start without the marker or declarations exits 1" 1 python3 -I $tool summary $tmp/bare-start.jsonl $lab off
contains "summary: nothing declared is named" '"nothing declared"'
check "usage: summary without id and variant exits 2" 2 python3 -I $tool summary $tmp/left.jsonl

# The runner's per-run identities must be ones the app accepts (LabTraceRule).
prefix=$(grep -o 'labBundleIDPrefix = "[^"]*"' ${0:A:h:h:h:h:h}/Packages/IceCore/Sources/IceCore/LabTraceRule.swift | cut -d'"' -f2)
if [[ -n $prefix ]] && grep -qF "local id=$prefix" ${0:A:h}/run-trace.sh; then
    print -- "ok   run-trace.sh makes identities under LabTraceRule's prefix ($prefix)"
else
    print -- "FAIL run-trace.sh's identities are not under LabTraceRule's prefix '$prefix'"; failures=$((failures + 1))
fi

{
    start
    points
    print -- '{"event":"window","item":"Ice.ControlItem.Visible","isAddedToMenuBar":true,"frame":[1500,0,25,24],"t":3}'
    print -- '{"event":"window","item":"Ice.ControlItem.Hidden","isAddedToMenuBar":true,"frame":[1469,0,20,24],"t":3}'
    print -- '{"event":"cap","seconds":20,"t":20}'
} > $tmp/capped.jsonl
check "summary: a trace that never finished exits 1" 1 python3 -I $tool summary $tmp/capped.jsonl $lab off
contains "summary: the cap is reported" '"event": "cap"'
contains "summary: right of the divider is recognised" '"layoutWindow": "iconRightOfDivider"'
contains "summary: no AX read is unknown, not a verdict" '"layoutAX": "unknown"'

# The placement oracle (S2 design, T2a): hidden divider | the other items | icon.
trace false "$(both 1508 1009 null 0 12)" > $tmp/good-off.jsonl
check "placement: divider, others, icon in two agreeing passes exits 0" 0 python3 -I $tool summary $tmp/good-off.jsonl $lab off
contains "placement: the verdict is said" '"placement": "dividerOthersIcon"'
contains "placement: no clause failed" '"failedClauses": []'
trace true "$(both 1508 1009 990 0 12)" > $tmp/good-on.jsonl
check "placement: with the always-hidden divider left of the hidden one, on exits 0" 0 python3 -I $tool summary $tmp/good-on.jsonl $lab on
trace true "$(both 1508 1009 1100 0 12)" > $tmp/on-reversed.jsonl
check "placement: an always-hidden divider right of the hidden one fails on" 1 python3 -I $tool summary $tmp/on-reversed.jsonl $lab on
contains "placement: that clause is named" '"alwaysHiddenLeftOfHidden"'
trace true "$(both 1508 1009 null 0 12)" > $tmp/on-missing.jsonl
check "placement: no always-hidden divider in the pass fails on" 1 python3 -I $tool summary $tmp/on-missing.jsonl $lab on
trace false "$(both 1508 1492 null 14 0)" > $tmp/t1.jsonl
check "placement: T1's layout (everything left of the divider) fails" 1 python3 -I $tool summary $tmp/t1.jsonl $lab off
contains "placement: others left of the divider are named" '"noOthersLeftOfDivider"'
contains "placement: nothing between is named" '"othersBetween"'
contains "placement: the verdict is failed" '"placement": "failed"'
trace false "$(placement 1 1508 1009 null 0 12)" "$(placement 2 1508 1009 null 0 11)" > $tmp/disagree.jsonl
check "placement: two passes that disagree are indeterminate, exit 1" 1 python3 -I $tool summary $tmp/disagree.jsonl $lab off
contains "placement: indeterminate is said" '"placement": "indeterminate"'
trace false "$(placement 1 1508 1009 null 0 12)" > $tmp/one-pass.jsonl
trace false "$(placement 1 1508 1009 null 0 12)" "$(placement 1 1508 1009 null 0 12)" > $tmp/same-pass.jsonl
check "placement: two events of the same pass are not two passes" 1 python3 -I $tool summary $tmp/same-pass.jsonl $lab off
contains "placement: the misnumbered passes are missing" '"placement": "missing"'
check "placement: one pass where two were declared exits 1" 1 python3 -I $tool summary $tmp/one-pass.jsonl $lab off
contains "placement: the missing pass is said" '"placement": "missing"'
trace false "$(placement 1 1508 1009 null 0 12)" '{"event":"placement","pass":2,"discovered":false,"t":4}' > $tmp/undiscovered.jsonl
check "placement: a pass that returned nothing exits 1" 1 python3 -I $tool summary $tmp/undiscovered.jsonl $lab off
trace false "$(both 1508 1009 null 0 12)" | sed '/"event":"placement"/s/"complete":true/"complete":false/' > $tmp/incomplete.jsonl
check "placement: an incomplete discovery pass fails" 1 python3 -I $tool summary $tmp/incomplete.jsonl $lab off
contains "placement: the pass clause is named" '"passComplete"'
trace false "$(both 1508 1009 null 0 12)" | sed 's/"hiddenDividerUsable":true/"hiddenDividerUsable":false/' > $tmp/unusable.jsonl
check "placement: an unusable hidden divider fails" 1 python3 -I $tool summary $tmp/unusable.jsonl $lab off
contains "placement: the on-bar clause is named" '"controlItemsOnBar"'
trace false "$(both 1508 1009 null 0 12)" | sed 's/"item":"Ice.ControlItem.Hidden","isAddedToMenuBar":true/"item":"Ice.ControlItem.Hidden","isAddedToMenuBar":false/' > $tmp/off-bar.jsonl
check "placement: a hidden divider not added to the bar fails" 1 python3 -I $tool summary $tmp/off-bar.jsonl $lab off
trace false "$(both 1508 1009 null 0 12)" | sed 's/"iconOnBar":true/"iconOnBar":false/' > $tmp/icon-parked.jsonl
check "placement: an icon whose frame is right of the divider but which is not on the bar fails" 1 python3 -I $tool summary $tmp/icon-parked.jsonl $lab off
contains "placement: the on-bar clause is named for the icon" '"controlItemsOnBar"'
baseline_on_bar=15 trace false "$(both 1508 1009 null 0 12)" > $tmp/displaced.jsonl
check "placement: fewer items on the bar than before Ice's items existed fails" 1 python3 -I $tool summary $tmp/displaced.jsonl $lab off
contains "placement: the displacement clause is named" '"noneDisplaced"'
grep -v '"event":"baseline"' $tmp/good-off.jsonl > $tmp/no-baseline.jsonl
check "placement: no baseline read exits 1" 1 python3 -I $tool summary $tmp/no-baseline.jsonl $lab off
sed 's/"event":"baseline","discovered":true/"event":"baseline","discovered":false/' $tmp/good-off.jsonl > $tmp/baseline-undiscovered.jsonl
check "placement: a baseline pass that returned nothing exits 1" 1 python3 -I $tool summary $tmp/baseline-undiscovered.jsonl $lab off
sed 's/,"readings":\["ownExtras","discover"\],"discoveryPasses":2//' $tmp/good-off.jsonl > $tmp/undeclared.jsonl
check "placement: a trace that declares no discovery passes (a T1 build) exits 1" 1 python3 -I $tool summary $tmp/undeclared.jsonl $lab off
sed 's/"discoveryPasses":2/"discoveryPasses":1/' $tmp/one-pass.jsonl > $tmp/declares-one.jsonl
check "placement: a build that declares and runs one pass exits 1: the count is the tool's" 1 python3 -I $tool summary $tmp/declares-one.jsonl $lab off
contains "placement: the pass-count mismatch is named" '"discoveryPasses"'

# Remembered positions (S2 design, T2b): the store guard over the run's two
# exact keys, one entry, and the three-read verdicts of Q3 and Q4. The keys
# are as MenuBarAgent wrote them for the helpers (run 20261008-081444-y8GnWW):
# by process name, not bundle id.
t_key=status:vzhelper::vz-rem-1-t
p_key=status:vzhelper::vz-rem-1-p
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:vzhelper::Item-0": 300}}' > $tmp/rem-before.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:vzhelper::Item-0": 300, "status:vzhelper::vz-rem-1-t": 616.5, "status:vzhelper::vz-rem-1-p": 588.5}}' > $tmp/rem-both.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:vzhelper::Item-0": 310, "status:vzhelper::vz-rem-1-t": 616.5, "status:vzhelper::vz-rem-1-p": 588.5}}' > $tmp/rem-other-helper.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:vzhelper::Item-0": 300, "status:vzhelper::vz-rem-1-t": 616.5, "status:vzhelper::vz-rem-1-t2": 1}}' > $tmp/rem-longer-name.json
check "guard: the run's two exact keys may appear" 0 python3 -I $tool guard $tmp/rem-before.json $tmp/rem-both.json $t_key $p_key
contains "guard: both entries are reported" '"status:vzhelper::vz-rem-1-p": 588.5'
check "guard: the second key fails when only the first is named" 1 python3 -I $tool guard $tmp/rem-before.json $tmp/rem-both.json $t_key
check "guard: another entry of the same process is not the run's own" 1 python3 -I $tool guard $tmp/rem-before.json $tmp/rem-other-helper.json $t_key $p_key
contains "guard: the other helper entry is named" '"key": "status:vzhelper::Item-0"'
check "guard: an exact key is not a prefix" 1 python3 -I $tool guard $tmp/rem-before.json $tmp/rem-longer-name.json $t_key $p_key
check "guard: a bundle id is neither a key nor a prefix: usage, exit 2" 2 python3 -I $tool guard $tmp/rem-before.json $tmp/rem-both.json com.icespike4.target
check "entry: a key's remembered position is printed" 0 python3 -I $tool entry $tmp/rem-both.json $t_key
contains "entry: the value" '616.5'
check "entry: no entry is null, not an error" 0 python3 -I $tool entry $tmp/rem-before.json $t_key
contains "entry: null" 'null'
check "entry: a key that is only a prefix of one is null" 0 python3 -I $tool entry $tmp/rem-longer-name.json $p_key
contains "entry: the prefix is null" 'null'
check "entry: something that is not a store exits 1" 1 python3 -I $tool entry $tmp/not-a-store.json $t_key
check "usage: entry with a prefix, not a key, exits 2" 2 python3 -I $tool entry $tmp/rem-both.json status:vzhelper::
check "usage: entry with a bundle id and a name exits 2" 2 python3 -I $tool entry $tmp/rem-both.json com.icespike4.target vz-rem-1-t

reads() { # <agent> <default> <side> <adjacent> x3: three settled reads, one per line
    local agent default side adjacent
    for agent default side adjacent in "$@"; do
        print -- "{\"agent\":$agent,\"default\":$default,\"side\":$side,\"adjacent\":$adjacent}"
    done
}
# T was dragged to the right of P. A fresh item lands leftmost (left of P); the
# seed (0.1) is the rightmost item, right of P too but not beside it.
reads 430 430 '"right"' true 430 430 '"right"' true 430 430 '"right"' true > $tmp/q-slot.jsonl
reads 0.1 0.1 '"right"' false 0.1 0.1 '"right"' false 0.1 0.1 '"right"' false > $tmp/q-seed.jsonl
reads 500 500 '"left"' true 500 500 '"left"' true 500 500 '"left"' true > $tmp/q-fresh.jsonl
reads 430 0.1 '"right"' true 430 0.1 '"right"' true 430 0.1 '"left"' true > $tmp/q-flips.jsonl
reads 430 0.1 '"right"' true 430 0.1 '"right"' true 431 0.1 '"right"' true > $tmp/q-drifts.jsonl
reads 430 0.1 '"right"' true 430 0.1 '"right"' true > $tmp/q-two.jsonl
reads null null null null null null null null null null null null > $tmp/q-unread.jsonl
reads 430 0.1 '"right"' null 430 0.1 '"right"' null 430 0.1 '"right"' null > $tmp/q-no-adjacency.jsonl
sed -e '1s/}$/,"x":1040}/' -e '2,3s/}$/,"x":1041}/' $tmp/q-slot.jsonl > $tmp/q-x-drifts.jsonl
check "remembered q3: three agreeing reads beside P on the dragged side: the slot is kept" 0 python3 -I $tool remembered q3 right $tmp/q-slot.jsonl
contains "remembered q3: kept is said" '"verdict": "slotKept"'
check "remembered q3: on the dragged side but not beside P is not the slot" 0 python3 -I $tool remembered q3 right $tmp/q-seed.jsonl
contains "remembered q3: elsewhere is said" '"verdict": "elsewhereOnTheDraggedSide"'
check "remembered q3: on the dragged side with the adjacency unread is inconclusive" 1 python3 -I $tool remembered q3 right $tmp/q-no-adjacency.jsonl
check "remembered q3: three agreeing reads on the other side: the slot is lost" 0 python3 -I $tool remembered q3 right $tmp/q-fresh.jsonl
contains "remembered q3: lost is said" '"verdict": "slotLost"'
check "remembered q3: a side that flips between reads is inconclusive, exit 1" 1 python3 -I $tool remembered q3 right $tmp/q-flips.jsonl
contains "remembered q3: inconclusive is said" '"verdict": "inconclusive"'
check "remembered q3: a store entry that drifts between reads is inconclusive" 1 python3 -I $tool remembered q3 right $tmp/q-drifts.jsonl
check "remembered q3: a frame that moves between reads is inconclusive" 1 python3 -I $tool remembered q3 right $tmp/q-x-drifts.jsonl
contains "remembered q3: the moving frame is a disagreement" '"reason": "readsDisagree"'
check "remembered q3: two reads are not three" 1 python3 -I $tool remembered q3 right $tmp/q-two.jsonl
contains "remembered q3: the read count is the reason" '"reason": "readCount"'
check "remembered q3: three agreeing reads that saw no side are inconclusive" 1 python3 -I $tool remembered q3 right $tmp/q-unread.jsonl
contains "remembered q3: the unread side is the reason" '"reason": "sideUnread"'
check "remembered q3: a slot on the side a fresh item lands on cannot be told from a fresh placement" 1 python3 -I $tool remembered q3 left $tmp/q-fresh.jsonl
contains "remembered q3: the fresh side is the reason" '"reason": "slotOnTheFreshSide"'
check "remembered q4: beside P on the dragged side, against the seed: the remembered slot wins" 0 python3 -I $tool remembered q4 right $tmp/q-slot.jsonl slotKept
contains "remembered q4: remembered is said" '"verdict": "rememberedSlotWins"'
check "remembered q4: right of P but no longer beside it: not the slot, and where the seed would put it" 0 python3 -I $tool remembered q4 right $tmp/q-seed.jsonl slotKept
contains "remembered q4: seed-compatible is said, not that the seed won" '"verdict": "seedCompatibleNotSlot"'
check "remembered q4: on the fresh side: neither the slot nor the seed" 0 python3 -I $tool remembered q4 right $tmp/q-fresh.jsonl slotKept
contains "remembered q4: neither is said" '"verdict": "neitherSlotNorSeed"'
check "remembered q4: without Q3's kept slot as the control there is no verdict" 1 python3 -I $tool remembered q4 right $tmp/q-slot.jsonl slotLost
contains "remembered q4: the missing control is the reason" '"reason": "noSlotKeptControl"'
check "remembered q4: an inconclusive Q3 is no control either" 1 python3 -I $tool remembered q4 right $tmp/q-seed.jsonl inconclusive
check "remembered q4: the slot and the seed are told apart by adjacency only: unread is inconclusive" 1 python3 -I $tool remembered q4 right $tmp/q-no-adjacency.jsonl slotKept
contains "remembered q4: the unread adjacency is the reason" '"reason": "adjacencyUnread"'
check "remembered q4: a slot on the fresh side is inconclusive" 1 python3 -I $tool remembered q4 left $tmp/q-fresh.jsonl slotKept
check "remembered q4: reads that disagree are inconclusive" 1 python3 -I $tool remembered q4 right $tmp/q-flips.jsonl slotKept
contains "remembered q4: the disagreement is the reason" '"reason": "readsDisagree"'
check "usage: remembered q4 without Q3's verdict exits 2" 2 python3 -I $tool remembered q4 right $tmp/q-slot.jsonl
check "usage: remembered q3 with a fourth argument exits 2" 2 python3 -I $tool remembered q3 right $tmp/q-slot.jsonl slotKept
check "usage: remembered with an unknown question exits 2" 2 python3 -I $tool remembered q5 right $tmp/q-slot.jsonl
check "usage: remembered with an unknown side exits 2" 2 python3 -I $tool remembered q3 up $tmp/q-slot.jsonl

print -- "$failures failure(s)"
exit $((failures > 0))
