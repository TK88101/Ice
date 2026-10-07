#!/bin/zsh
# Tests for trace-tool.py (plan 2026-10-07-icebar-preference-hiding, S1) on
# synthetic stores and traces. No app is launched, nothing outside a temporary
# directory is read or written.
#
#   test-trace.sh
set -uo pipefail
tool=${0:A:h}/trace-tool.py
tmp=$(mktemp -d)
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

contains() { # <name> <text>
    if grep -qF -- "$2" $tmp/out; then print -- "ok   $1"; else print -- "FAIL $1: no '$2'"; cat $tmp/out; failures=$((failures + 1)); fi
}

lab=com.icespike4.trace.r1
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3}}' > $tmp/before.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3, "status:com.icespike4.trace.r1::Ice.ControlItem.Hidden": 1}}' > $tmp/lab-only.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 150, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3}}' > $tmp/moved.json
print -- '{"TrailingItemPreferredPositions": {"status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 3}}' > $tmp/removed.json
print -- '{"TrailingItemPreferredPositions": {"status:com.example.a::x": 141.5, "status:com.icespike4.trace.r10::Ice.ControlItem.Hidden": 4}}' > $tmp/sibling.json
print -- '{}' > $tmp/empty.json

check "guard: no change passes" 0 python3 -I $tool guard $tmp/before.json $tmp/before.json $lab
check "guard: a new entry of the lab identity passes" 0 python3 -I $tool guard $tmp/before.json $tmp/lab-only.json $lab
contains "guard: the lab entry is reported" '"status:com.icespike4.trace.r1::Ice.ControlItem.Hidden": 1'
check "guard: a moved owner entry fails" 1 python3 -I $tool guard $tmp/before.json $tmp/moved.json $lab
contains "guard: the moved entry is named" '"key": "status:com.example.a::x"'
check "guard: a removed owner entry fails" 1 python3 -I $tool guard $tmp/before.json $tmp/removed.json $lab
check "guard: another lab identity (r10 vs r1) is not the run's own" 1 python3 -I $tool guard $tmp/before.json $tmp/sibling.json $lab
check "guard: a store with no dictionary yet passes" 0 python3 -I $tool guard $tmp/empty.json $tmp/empty.json $lab
check "usage: wrong arguments exit 2" 2 python3 -I $tool guard $tmp/before.json

cat > $tmp/left.jsonl <<'EOF'
{"event":"start","t":0}
{"event":"point","item":"Ice.ControlItem.Visible","point":"beforeSeed","defaults":{"Preferred Position":null},"t":0.01}
{"event":"point","item":"Ice.ControlItem.Visible","point":"afterSeed","defaults":{"Preferred Position":0.1},"t":0.02}
{"event":"window","item":"Ice.ControlItem.Visible","isAddedToMenuBar":true,"frame":[1285,0,25,24],"t":3}
{"event":"window","item":"Ice.ControlItem.Hidden","isAddedToMenuBar":true,"frame":[1469,0,20,24],"t":3}
{"event":"ax","trusted":true,"items":[{"identifier":"Ice.ControlItem.Visible","frame":[1285,0,25,24]},{"identifier":"Ice.ControlItem.Hidden","frame":[1469,0,20,24]}],"t":3.1}
{"event":"done","t":3.2}
EOF
check "summary: a finished trace exits 0" 0 python3 -I $tool summary $tmp/left.jsonl
contains "summary: P2's layout is recognised" '"layoutAX": "iconLeftOfDivider"'
contains "summary: the window frames agree" '"layoutWindow": "iconLeftOfDivider"'
contains "summary: the five-point values are kept" '"afterSeed": 0.1'

cat > $tmp/capped.jsonl <<'EOF'
{"event":"start","t":0}
{"event":"window","item":"Ice.ControlItem.Visible","isAddedToMenuBar":true,"frame":[1500,0,25,24],"t":3}
{"event":"window","item":"Ice.ControlItem.Hidden","isAddedToMenuBar":true,"frame":[1469,0,20,24],"t":3}
{"event":"cap","seconds":10,"t":10}
EOF
check "summary: a trace that never finished exits 1" 1 python3 -I $tool summary $tmp/capped.jsonl
contains "summary: the cap is reported" '"event": "cap"'
contains "summary: right of the divider is recognised" '"layoutWindow": "iconRightOfDivider"'
contains "summary: no AX read is unknown, not a verdict" '"layoutAX": "unknown"'

print -- "$failures failure(s)"
exit $((failures > 0))
