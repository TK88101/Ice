#!/bin/zsh
# Ice's trace mode in the current account (plan
# 2026-10-07-icebar-preference-hiding, S1): stages a copy of a built Ice.app
# under a fresh lab identity for every run (com.icespike4.trace.r<run id>.<variant><n>:
# never seen by MenuBarAgent, so every run starts from a clean domain), runs
# it with -IceLabTrace YES, both always-hidden variants, judges the placement
# oracle of the plan's S2 design (hidden divider | the other items | icon;
# trace-tool.py summary), and guards MenuBarAgent's store: any change outside the run's own position entries
# fails the run and stops the runner. The store is read here, not in Ice: a
# read of another app's group container from Ice could raise a privacy prompt
# in the owner's session.
#
#   run-trace.sh <built Ice.app with trace mode> <scratch directory outside ~/Documents> [runs per variant, 1-20, default 3]
#
# Side effects: three status items of the lab identity on the bar for about
# six seconds per run (the bar reflows while they are there); three read-only
# discovery passes over every app's status items by Accessibility, as any Ice
# on macOS 27 makes once a second; the lab
# identity's own defaults domain (exported to the evidence, then deleted);
# possibly MenuBarAgent's entries for the lab identity (left; reported). Each
# staged copy is unregistered from LaunchServices and deleted after its run.
# Evidence (contains app names, this account only): ~/IceReverse-evidence/<run id>-trace/,
# with the store as it was before the first launch (store-before.plist).
#
# Every step is checked explicitly: trace_one runs under `||`, where zsh does
# not apply errexit.
set -euo pipefail
umask 077
here=${0:A:h}
tool=$here/trace-tool.py
source $here/t7-lib.zsh
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
built=${1:?built Ice.app}
scratch=${2:?scratch directory outside ~/Documents}
runs=${3:-3}
[[ $runs == <1-20> ]] || { print -u2 -- "run-trace: runs must be 1-20"; exit 2; }
[[ -x $built/Contents/MacOS/Ice ]] || { print -u2 -- "run-trace: $built is not an Ice.app"; exit 2; }
[[ ${built:A} != /Applications/* ]] || { print -u2 -- "run-trace: not a release Ice in /Applications"; exit 2; }
# A build without trace mode would ignore the argument and run as a normal Ice:
# refused here by LabTrace's marker (a Debug build keeps its code in
# Ice.debug.dylib), and killed at launch if its first line is not the marker.
marker=IceLabTrace-start-v1
handshake_tries=30 # x 0.1 s
store_settle_tries=10 # x 1 s
grep -rqaF $marker $built/Contents/MacOS || { print -u2 -- "run-trace: $built has no trace mode"; exit 2; }
[[ ${scratch:A:l} != ${HOME:l}/documents* ]] || { print -u2 -- "run-trace: scratch must be outside ~/Documents (iCloud breaks codesign)"; exit 2; }
# The staged copies are executed: not from a directory another account made or links.
t7_private_directory $scratch || exit 2
work=$(mktemp -d $scratch/icetrace.XXXXXX) || exit 2
store="$HOME/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar"
run_id=$(date +%Y%m%d-%H%M%S)-${work:t:e}
evidence=$HOME/IceReverse-evidence/$run_id-trace
mkdir -p $evidence
defaults export "$store" $evidence/store-before.plist || { print -u2 -- "run-trace: MenuBarAgent's store could not be saved"; exit 1; }

export_store() { # <output json>
    defaults export "$store" - | plutil -convert json -o "$1" -
}

stage() { # <bundle id> <stage directory> -> path of the staged app
    mkdir -- $2 || return 1
    ditto -- $built $2/Ice.app || return 1
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $1" $2/Ice.app/Contents/Info.plist || return 1
    codesign --force --deep --sign - $2/Ice.app 2> $2/codesign.log || return 1
    codesign --verify --deep --strict $2/Ice.app || return 1
    [[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" $2/Ice.app/Contents/Info.plist) == $1 ]] || return 1
    print -- $2/Ice.app
}

unstage() { # <stage directory>
    $lsregister -u $1/Ice.app 2> /dev/null || true
    rm -rf -- $1
}

launch() { # <app> <always-hidden YES|NO> <out directory> -> the trace's exit status
    perl -e 'alarm 20; exec @ARGV' $1/Contents/MacOS/Ice -IceLabTrace YES -IceLabTraceAlwaysHidden $2 \
        > $3/trace.jsonl 2> $3/stderr.log &
    local pid=$! tries=0
    until head -1 $3/trace.jsonl 2> /dev/null | grep -qF $marker; do
        kill -0 $pid 2> /dev/null || break # it quit by itself (refused, crashed)
        if (( ++tries > handshake_tries )); then
            print -u2 -- "run-trace: no trace handshake from pid $pid; killed"
            kill -9 $pid
            break
        fi
        sleep 0.1
    done
    local code=0
    wait $pid || code=$?
    return $code
}

settled_store() { # <output json>: read until two reads a second apart agree
    local previous=$1.previous tries=0
    export_store $previous || return 1
    while (( tries++ < store_settle_tries )); do
        sleep 1
        export_store $1 || return 1
        cmp -s $previous $1 && { rm -f -- $previous; return 0; }
        mv -- $1 $previous
    done
    print -u2 -- "run-trace: MenuBarAgent's store did not settle"
    return 1
}

stop() { # <reason>: the owner's store may have changed; nothing more is launched
    print -u2 -- "run-trace: $1; stopped. The store as it was: $evidence/store-before.plist"
    exit 1
}

trace_one() { # <variant: off|on> <n>; stops the runner when the store guard fails
    local variant=$1 n=$2
    local id=com.icespike4.trace.r${run_id//[^A-Za-z0-9]/}.$variant$n
    local out=$evidence/$variant$n stage_dir=$work/stage-$variant$n
    mkdir -p $out || return 1
    t7_domain_is_empty $id || { print -u2 -- "run-trace: $id already has defaults; not a clean domain"; return 1; }
    local app
    app=$(stage $id $stage_dir) || { print -u2 -- "run-trace: staging $id failed"; unstage $stage_dir; return 1; }
    local always=NO
    [[ $variant == on ]] && always=YES
    export_store $out/store-before.json || { unstage $stage_dir; return 1; }
    local code=0
    launch $app $always $out || code=$?
    sleep 2 # let MenuBarAgent record the items' removal before the store is read again
    unstage $stage_dir
    settled_store $out/store-after.json || stop "MenuBarAgent's store could not be read back"
    local defaults_code=0
    t7_prefs_export $id $out/lab-defaults.plist || defaults_code=1
    defaults delete $id 2> /dev/null || true
    t7_domain_is_empty $id || { print -u2 -- "run-trace: $id still has defaults after the delete"; defaults_code=1; }
    local guard_code=0 summary_code=0
    python3 -I $tool guard $out/store-before.json $out/store-after.json $id > $out/guard.json || guard_code=$?
    python3 -I $tool summary $out/trace.jsonl $id $variant > $out/summary.json 2> $out/summary.txt || summary_code=$?
    print -- "$variant$n id=$id exit=$code guard=$([[ $guard_code == 0 ]] && echo pass || echo FAIL) complete=$([[ $summary_code == 0 ]] && echo yes || echo NO) labDefaults=$([[ $defaults_code == 0 ]] && echo exported+removed || echo FAIL)"
    cat $out/summary.txt
    [[ $code == 0 ]] || print -- "   stderr: $(head -1 $out/stderr.log)"
    [[ $guard_code == 0 ]] || stop "MenuBarAgent's store changed outside the lab identity ($out/guard.json)"
    [[ $code == 0 && $summary_code == 0 && $defaults_code == 0 ]]
}

print -- "run-trace: $run_id, $runs run(s) per variant, evidence $evidence"
failed=0
for variant in off on; do
    for n in {1..$runs}; do
        trace_one $variant $n || failed=1
    done
done
rmdir $work 2> /dev/null || true
print -- "run-trace: $([[ $failed == 0 ]] && echo 'all runs complete, guard passed' || echo 'a run FAILED') ($evidence)"
exit $failed
