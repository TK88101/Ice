#!/bin/zsh
# Tests for trace-tool.py (plan 2026-10-07-icebar-preference-hiding, S1) on
# synthetic stores and traces. No app is launched, nothing outside a temporary
# directory is read or written.
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

check "guard: no change passes" 0 python3 -I $tool guard $tmp/before.json $tmp/before.json $lab
check "guard: a new entry of the lab identity passes" 0 python3 -I $tool guard $tmp/before.json $tmp/lab-only.json $lab
contains "guard: the lab entry is reported" '"status:com.icespike4.trace.r1::Ice.ControlItem.Hidden": 1'
check "guard: a moved owner entry fails" 1 python3 -I $tool guard $tmp/before.json $tmp/moved.json $lab
contains "guard: the moved entry is named" '"key": "status:com.example.a::x"'
check "guard: a removed owner entry fails" 1 python3 -I $tool guard $tmp/before.json $tmp/removed.json $lab
check "guard: another lab identity (r10 vs r1) is not the run's own" 1 python3 -I $tool guard $tmp/before.json $tmp/sibling.json $lab
check "guard: a change to another top-level key of the store fails" 1 python3 -I $tool guard $tmp/before.json $tmp/other-key.json $lab
contains "guard: the other key is named" '"key": "OtherKey"'
check "guard: a store with no dictionary yet passes" 0 python3 -I $tool guard $tmp/empty.json $tmp/empty.json $lab
check "guard: something that is not a store does not pass" 1 python3 -I $tool guard $tmp/not-a-store.json $tmp/empty.json $lab
check "usage: wrong arguments exit 2" 2 python3 -I $tool guard $tmp/before.json

start() { # [always-hidden: true|false] [bundle id]: the start event a trace announces
    print -- "{\"event\":\"start\",\"mode\":\"IceLabTrace-start-v1\",\"bundleID\":\"${2:-$lab}\",\"alwaysHiddenSection\":${1:-false},\"steps\":[\"stopPermissionChecks\",\"setSettingsInMemory\",\"readBaseline\",\"setUpSections\"],\"points\":[\"beforeSeed\",\"afterSeed\",\"afterStatusItem\",\"afterAutosaveName\",\"afterMainQueueTurn\"],\"items\":[\"Ice.ControlItem.Visible\",\"Ice.ControlItem.Hidden\",\"Ice.ControlItem.AlwaysHidden\"],\"readings\":[\"ownExtras\",\"discoverTwice\"],\"discoveryPasses\":2,\"t\":0}"
}
placement() { # <pass> <icon minX> <hidden minX> <always-hidden minX|null> <others left> <between> [extra json fields]: one discovery pass
    local icon=$2 hidden=$3 always=null usable=false verdict=right
    [[ $4 != null ]] && { always="[$4,4.5,18,24]"; usable=true; }
    (( icon + 17.5 > hidden )) || verdict=iconLeftOfDivider
    print -- "{\"event\":\"placement\",\"pass\":$1,\"discovered\":true,\"icon\":[$icon,4.5,35,24],\"hiddenDivider\":[$hidden,4.5,18,24],\"hiddenDividerUsable\":true,\"alwaysHiddenDivider\":$always,\"alwaysHiddenDividerUsable\":$usable,\"iconPlacement\":\"$verdict\",\"othersLeftOfHiddenDivider\":$5,\"othersBetween\":$6,\"othersRightOfIcon\":2,\"othersUnplaced\":0,\"othersOnBar\":$(($5 + $6 + 2)),\"complete\":true,\"ownReadOk\":true${7:+,$7},\"t\":4}"
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
    placement 1 1285 1469 null 9 0
    placement 2 1285 1469 null 9 0
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
    print -- '{"event":"cap","seconds":10,"t":10}'
} > $tmp/capped.jsonl
check "summary: a trace that never finished exits 1" 1 python3 -I $tool summary $tmp/capped.jsonl $lab off
contains "summary: the cap is reported" '"event": "cap"'
contains "summary: right of the divider is recognised" '"layoutWindow": "iconRightOfDivider"'
contains "summary: no AX read is unknown, not a verdict" '"layoutAX": "unknown"'

# The placement oracle (S2 design, T2a): hidden divider | the other items | icon.
trace false "$(placement 1 1508 1009 null 0 12)" "$(placement 2 1508 1009 null 0 12)" > $tmp/good-off.jsonl
check "placement: divider, others, icon in two agreeing passes exits 0" 0 python3 -I $tool summary $tmp/good-off.jsonl $lab off
contains "placement: the verdict is said" '"placement": "dividerOthersIcon"'
contains "placement: no clause failed" '"failedClauses": []'
trace true "$(placement 1 1508 1009 990 0 12)" "$(placement 2 1508 1009 990 0 12)" > $tmp/good-on.jsonl
check "placement: with the always-hidden divider left of the hidden one, on exits 0" 0 python3 -I $tool summary $tmp/good-on.jsonl $lab on
trace true "$(placement 1 1508 1009 1100 0 12)" "$(placement 2 1508 1009 1100 0 12)" > $tmp/on-reversed.jsonl
check "placement: an always-hidden divider right of the hidden one fails on" 1 python3 -I $tool summary $tmp/on-reversed.jsonl $lab on
contains "placement: that clause is named" '"alwaysHiddenLeftOfHidden"'
trace true "$(placement 1 1508 1009 null 0 12)" "$(placement 2 1508 1009 null 0 12)" > $tmp/on-missing.jsonl
check "placement: no always-hidden divider in the pass fails on" 1 python3 -I $tool summary $tmp/on-missing.jsonl $lab on
trace false "$(placement 1 1508 1492 null 14 0)" "$(placement 2 1508 1492 null 14 0)" > $tmp/t1.jsonl
check "placement: T1's layout (everything left of the divider) fails" 1 python3 -I $tool summary $tmp/t1.jsonl $lab off
contains "placement: others left of the divider are named" '"noOthersLeftOfDivider"'
contains "placement: nothing between is named" '"othersBetween"'
contains "placement: the verdict is failed" '"placement": "failed"'
trace false "$(placement 1 1508 1009 null 0 12)" "$(placement 2 1508 1009 null 0 11)" > $tmp/disagree.jsonl
check "placement: two passes that disagree are indeterminate, exit 1" 1 python3 -I $tool summary $tmp/disagree.jsonl $lab off
contains "placement: indeterminate is said" '"placement": "indeterminate"'
trace false "$(placement 1 1508 1009 null 0 12)" > $tmp/one-pass.jsonl
check "placement: one pass where two were declared exits 1" 1 python3 -I $tool summary $tmp/one-pass.jsonl $lab off
contains "placement: the missing pass is said" '"placement": "missing"'
trace false "$(placement 1 1508 1009 null 0 12)" '{"event":"placement","pass":2,"discovered":false,"t":4}' > $tmp/undiscovered.jsonl
check "placement: a pass that returned nothing exits 1" 1 python3 -I $tool summary $tmp/undiscovered.jsonl $lab off
incomplete='"complete":false'
trace false "$(placement 1 1508 1009 null 0 12 | sed 's/"complete":true/"complete":false/')" "$(placement 2 1508 1009 null 0 12 | sed 's/"complete":true/"complete":false/')" > $tmp/incomplete.jsonl
check "placement: an incomplete discovery pass fails" 1 python3 -I $tool summary $tmp/incomplete.jsonl $lab off
contains "placement: the pass clause is named" '"passComplete"'
trace false "$(placement 1 1508 1009 null 0 12 | sed 's/"hiddenDividerUsable":true/"hiddenDividerUsable":false/')" "$(placement 2 1508 1009 null 0 12 | sed 's/"hiddenDividerUsable":true/"hiddenDividerUsable":false/')" > $tmp/unusable.jsonl
check "placement: an unusable hidden divider fails" 1 python3 -I $tool summary $tmp/unusable.jsonl $lab off
contains "placement: the on-bar clause is named" '"controlItemsOnBar"'
trace false "$(placement 1 1508 1009 null 0 12)" "$(placement 2 1508 1009 null 0 12)" | sed 's/"item":"Ice.ControlItem.Hidden","isAddedToMenuBar":true/"item":"Ice.ControlItem.Hidden","isAddedToMenuBar":false/' > $tmp/off-bar.jsonl
check "placement: a hidden divider not added to the bar fails" 1 python3 -I $tool summary $tmp/off-bar.jsonl $lab off
grep -v '"readings"' $tmp/good-off.jsonl > /dev/null # (the start line carries the declaration)
baseline_on_bar=15 trace false "$(placement 1 1508 1009 null 0 12)" "$(placement 2 1508 1009 null 0 12)" > $tmp/displaced.jsonl
check "placement: fewer items on the bar than before Ice's items existed fails" 1 python3 -I $tool summary $tmp/displaced.jsonl $lab off
contains "placement: the displacement clause is named" '"noneDisplaced"'
grep -v '"event":"baseline"' $tmp/good-off.jsonl > $tmp/no-baseline.jsonl
check "placement: no baseline read exits 1" 1 python3 -I $tool summary $tmp/no-baseline.jsonl $lab off
sed 's/"event":"baseline","discovered":true/"event":"baseline","discovered":false/' $tmp/good-off.jsonl > $tmp/baseline-undiscovered.jsonl
check "placement: a baseline pass that returned nothing exits 1" 1 python3 -I $tool summary $tmp/baseline-undiscovered.jsonl $lab off
sed 's/,"readings":\["ownExtras","discoverTwice"\],"discoveryPasses":2//' $tmp/good-off.jsonl > $tmp/undeclared.jsonl
check "placement: a trace that declares no discovery passes (a T1 build) exits 1" 1 python3 -I $tool summary $tmp/undeclared.jsonl $lab off

print -- "$failures failure(s)"
exit $((failures > 0))
