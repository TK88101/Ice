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
    print -- "{\"event\":\"start\",\"mode\":\"IceLabTrace-start-v1\",\"bundleID\":\"${2:-$lab}\",\"alwaysHiddenSection\":${1:-false},\"steps\":[\"stopPermissionChecks\",\"setSettingsInMemory\",\"setUpSections\"],\"points\":[\"beforeSeed\",\"afterSeed\",\"afterStatusItem\",\"afterAutosaveName\",\"afterMainQueueTurn\"],\"items\":[\"Ice.ControlItem.Visible\",\"Ice.ControlItem.Hidden\",\"Ice.ControlItem.AlwaysHidden\"],\"t\":0}"
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
    print -- '{"event":"done","t":3.2}'
} > $tmp/left.jsonl
check "summary: a complete trace exits 0" 0 python3 -I $tool summary $tmp/left.jsonl $lab off
contains "summary: P2's layout is recognised" '"layoutAX": "iconLeftOfDivider"'
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

print -- "$failures failure(s)"
exit $((failures > 0))
