#!/bin/zsh
# Ice's trace mode in the current account (plan
# 2026-10-07-icebar-preference-hiding, S1): stages a copy of a built Ice.app
# under a fresh lab identity for every run (com.icespike4.trace.r<run id>.<variant><n>:
# never seen by MenuBarAgent, so every run starts from a clean domain), runs
# it with -IceLabTrace YES, both always-hidden variants, and guards
# MenuBarAgent's TrailingItemPreferredPositions: any change outside the run's
# own identity fails the run.
#
#   run-trace.sh <built Ice.app> <scratch directory outside ~/Documents> [runs per variant, default 3]
#
# Side effects: three status items of the lab identity on the bar for about
# three seconds per run (the bar reflows while they are there); the lab
# identity's own defaults domain (exported to the evidence, then deleted);
# possibly MenuBarAgent's entries for the lab identity (left; reported).
# Evidence (contains app names): ~/IceReverse-evidence/<run id>-trace/.
set -euo pipefail
here=${0:A:h}
tool=$here/trace-tool.py
built=${1:?built Ice.app}
scratch=${2:?scratch directory outside ~/Documents}
runs=${3:-3}
[[ -d $built/Contents/MacOS ]] || { print -u2 -- "run-trace: $built is not an app bundle"; exit 2; }
[[ ${scratch:A} != $HOME/Documents* ]] || { print -u2 -- "run-trace: scratch must be outside ~/Documents (iCloud breaks codesign)"; exit 2; }
store="$HOME/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar"
run_id=$(date +%Y%m%d-%H%M%S)
evidence=$HOME/IceReverse-evidence/$run_id-trace
mkdir -p $evidence $scratch
failed=0

export_store() { # <output json>
    defaults export "$store" - | plutil -convert json -o "$1" -
}

stage() { # <bundle id> <stage directory> -> path of the staged app
    rm -rf $2 && mkdir -p $2
    ditto $built $2/Ice.app
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $1" $2/Ice.app/Contents/Info.plist
    codesign --force --deep --sign - $2/Ice.app 2> $2/codesign.log
    codesign --verify --deep --strict $2/Ice.app
    [[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" $2/Ice.app/Contents/Info.plist) == $1 ]]
    print -- $2/Ice.app
}

trace_one() { # <variant: off|on> <n>
    local variant=$1 n=$2
    local id=com.icespike4.trace.r${run_id//-/}.$variant$n
    local out=$evidence/$variant$n
    mkdir -p $out
    if defaults read $id > /dev/null 2>&1; then
        print -u2 -- "run-trace: $id already has defaults; not a clean domain"; return 1
    fi
    local app
    app=$(stage $id $scratch/stage-$variant$n)
    local always=NO
    [[ $variant == on ]] && always=YES
    export_store $out/store-before.json
    local code=0
    perl -e 'alarm 20; exec @ARGV' $app/Contents/MacOS/Ice -IceLabTrace YES -IceLabTraceAlwaysHidden $always \
        > $out/trace.jsonl 2> $out/stderr.log || code=$?
    sleep 2 # let MenuBarAgent record the items' removal before the store is read again
    export_store $out/store-after.json
    defaults export $id $out/lab-defaults.plist 2> /dev/null || true
    defaults delete $id 2> /dev/null || true
    local guard_code=0 summary_code=0
    python3 -I $tool guard $out/store-before.json $out/store-after.json $id > $out/guard.json || guard_code=$?
    python3 -I $tool summary $out/trace.jsonl > $out/summary.json || summary_code=$?
    print -- "$variant$n id=$id exit=$code guard=$([[ $guard_code == 0 ]] && echo pass || echo FAIL) done=$([[ $summary_code == 0 ]] && echo yes || echo NO)"
    python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); print("   layoutAX=%s layoutWindow=%s axTrusted=%s onBar=%s" % (s["layoutAX"], s["layoutWindow"], s["axTrusted"], s["onBar"]))' $out/summary.json
    [[ $code == 0 && $guard_code == 0 && $summary_code == 0 ]]
}

print -- "run-trace: $run_id, $runs run(s) per variant, evidence $evidence"
for variant in off on; do
    for n in $(seq 1 $runs); do
        trace_one $variant $n || failed=1
    done
done
print -- "run-trace: $([[ $failed == 0 ]] && echo 'all runs finished, guard passed' || echo 'a run FAILED') ($evidence)"
exit $failed
