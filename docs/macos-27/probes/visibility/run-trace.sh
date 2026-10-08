#!/bin/zsh
# Ice's trace mode in the current account (plan
# 2026-10-07-icebar-preference-hiding, S1): stages a copy of a built Ice.app
# under a fresh lab identity for every run (com.icespike4.trace.r<run id>.<variant><n>:
# never seen by MenuBarAgent, so every run starts from a clean domain), runs
# it with -IceLabTrace YES, both always-hidden variants and then `inv` (S2
# design T2c: the lab identity's icon default is written large before launch,
# the one deliberate exception to the clean domain; an inverted layout must
# carry the layout pane's notice, and a layout the value did not invert is
# recorded, not failed), judges the placement
# oracle of the plan's S2 design (hidden divider | the other items | icon;
# trace-tool.py summary), and guards MenuBarAgent's store: any change outside the run's own position entries
# fails the run and stops the runner. ("Own" is entries under the lab bundle
# id. MenuBarAgent keyed the ad-hoc helpers of run-remembered.sh by process
# name instead; if it keys an ad-hoc Ice so too, nothing here is "own" and any
# change to the store stops the runner. In these few seconds it has recorded nothing.) The store is read here, not in Ice: a
# read of another app's group container from Ice could raise a privacy prompt
# in the owner's session.
#
#   run-trace.sh <built Ice.app with trace mode> <scratch directory outside ~/Documents> [runs per variant, 1-20, default 3] [executable name]
#
# With an executable name each staged copy's executable is renamed to it
# (`CFBundleExecutable` to match), as the lab runner stages its copies (S4
# design D2): this shows that a renamed copy starts, nothing about how
# MenuBarAgent keys it.
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
source $here/store-lib.zsh
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
built=${1:?built Ice.app}
scratch=${2:?scratch directory outside ~/Documents}
runs=${3:-3}
executable=${4:-Ice}
[[ $runs == <1-20> ]] || { print -u2 -- "run-trace: runs must be 1-20"; exit 2; }
[[ $executable =~ '^[A-Za-z][A-Za-z0-9]{0,30}$' ]] || { print -u2 -- "run-trace: the executable name must be letters and digits"; exit 2; }
[[ -x $built/Contents/MacOS/Ice ]] || { print -u2 -- "run-trace: $built is not an Ice.app"; exit 2; }
[[ ${built:A} != /Applications/* ]] || { print -u2 -- "run-trace: not a release Ice in /Applications"; exit 2; }
# A build without trace mode would ignore the argument and run as a normal Ice:
# refused here by LabTrace's marker (a Debug build keeps its code in
# Ice.debug.dylib), and killed at launch if its first line is not the marker.
marker=IceLabTrace-start-v1
handshake_tries=30 # x 0.1 s
# `inv`: a preferred position far beyond the bar, so as far left as macOS
# puts it. Ice leaves a stored value alone (ControlItemPositionSeed).
inverting_position=5000
icon_position_key="NSStatusItem Preferred Position Ice.ControlItem.Visible"
grep -rqaF $marker $built/Contents/MacOS || { print -u2 -- "run-trace: $built has no trace mode"; exit 2; }
[[ ${scratch:A:l} != ${HOME:l}/documents* ]] || { print -u2 -- "run-trace: scratch must be outside ~/Documents (iCloud breaks codesign)"; exit 2; }
# The staged copies are executed: not from a directory another account made or links.
t7_private_directory $scratch || exit 2
work=$(mktemp -d $scratch/icetrace.XXXXXX) || exit 2
run_id=$(date +%Y%m%d-%H%M%S)-${work:t:e}
evidence=$HOME/IceReverse-evidence/$run_id-trace
mkdir -p $evidence
defaults export "$menubar_store" $evidence/store-before.plist || { print -u2 -- "run-trace: MenuBarAgent's store could not be saved"; exit 1; }

stage() { # <bundle id> <stage directory> -> path of the staged app
    mkdir -- $2 || return 1
    ditto -- $built $2/Ice.app || return 1
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $1" $2/Ice.app/Contents/Info.plist || return 1
    if [[ $executable != Ice ]]; then
        mv -- $2/Ice.app/Contents/MacOS/Ice $2/Ice.app/Contents/MacOS/$executable || return 1
        /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $executable" $2/Ice.app/Contents/Info.plist || return 1
    fi
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
    perl -e 'alarm 30; exec @ARGV' $1/Contents/MacOS/$executable -IceLabTrace YES -IceLabTraceAlwaysHidden $2 \
        > $3/trace.jsonl 2> $3/stderr.log &
    local pid=$! tries=0
    launched_pid=$pid
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
    launched_pid=
    return $code
}

stop() { # <reason>: the owner's store may have changed; nothing more is launched
    print -u2 -- "run-trace: $1; stopped. The store as it was: $evidence/store-before.plist"
    exit 1
}

# What a run has under way, for every way out of the script: the trace it
# launched (stopped first: a running Ice writes its defaults back), its staged
# copy, and the lab identity whose defaults domain may hold something (what
# `inv` writes, what the trace writes). A run clears each once it has dealt
# with it itself.
launched_pid=
pending_stage=
pending_id=
drop_pending_defaults() { # fails, and keeps the identity pending, unless the domain is verified empty
    [[ -n $pending_id ]] || return 0
    defaults delete $pending_id 2> /dev/null || true
    t7_domain_is_empty $pending_id || { print -u2 -- "run-trace: $pending_id STILL HAS DEFAULTS; delete it by hand: defaults delete $pending_id"; return 1; }
    pending_id=
}
cleanup() { # the script's exit status, or 1 when the lab defaults could not be removed
    local code=$?
    trap '' INT TERM HUP QUIT
    if [[ -n $launched_pid ]]; then
        kill -9 $launched_pid 2> /dev/null || true
        wait $launched_pid 2> /dev/null || true
        launched_pid=
    fi
    [[ -z $pending_stage ]] || unstage $pending_stage
    drop_pending_defaults || code=1
    rmdir $work 2> /dev/null || true
    exit $code
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'exit 131' QUIT

trace_one() { # <variant: off|on|inv> <n>; stops the runner when the store guard fails
    local variant=$1 n=$2
    local id=com.icespike4.trace.r${run_id//[^A-Za-z0-9]/}.$variant$n
    local out=$evidence/$variant$n stage_dir=$work/stage-$variant$n
    mkdir -p $out || return 1
    t7_domain_is_empty $id || { print -u2 -- "run-trace: $id already has defaults; not a clean domain"; return 1; }
    # An earlier run's defaults that could not be removed end the runner
    # here: cleanup tries once more and names the domain, and no later run
    # takes its place in `pending_id`.
    [[ -z $pending_id ]] || exit 1
    # Recorded before anything exists, so that no way out leaves it behind
    # (cleanup takes a stage that was never made); a domain that was not
    # clean is not ours and is left alone above.
    pending_id=$id
    pending_stage=$stage_dir
    abandon() { # <what failed>: this run's staged copy and defaults, gone
        print -u2 -- "run-trace: $1"
        unstage $stage_dir
        pending_stage=
        drop_pending_defaults
        return 1
    }
    local app
    app=$(stage $id $stage_dir) || { abandon "staging $id failed"; return 1; }
    local always=NO
    [[ $variant == on ]] && always=YES
    if [[ $variant == inv ]]; then
        defaults write $id $icon_position_key -float $inverting_position \
            && [[ $(defaults read $id $icon_position_key 2> /dev/null) == $inverting_position ]] \
            || { abandon "the icon's position could not be written for $id"; return 1; }
    fi
    export_store $out/store-before.json || { abandon "MenuBarAgent's store could not be read"; return 1; }
    local code=0
    launch $app $always $out || code=$?
    sleep 2 # let MenuBarAgent record the items' removal before the store is read again
    unstage $stage_dir
    pending_stage=
    settled_store $out/store-after.json || stop "MenuBarAgent's store could not be read back"
    local defaults_code=0
    t7_prefs_export $id $out/lab-defaults.plist || defaults_code=1
    defaults delete $id 2> /dev/null || true
    if t7_domain_is_empty $id; then pending_id=; else print -u2 -- "run-trace: $id still has defaults after the delete"; defaults_code=1; fi
    local guard_code=0 summary_code=0
    python3 -I $tool guard $out/store-before.json $out/store-after.json "status:$id::" > $out/guard.json || guard_code=$?
    python3 -I $tool summary $out/trace.jsonl $id $variant > $out/summary.json 2> $out/summary.txt || summary_code=$?
    print -- "$variant$n id=$id exit=$code guard=$([[ $guard_code == 0 ]] && echo pass || echo FAIL) summary=$([[ $summary_code == 0 ]] && echo pass || echo FAIL) labDefaults=$([[ $defaults_code == 0 ]] && echo exported+removed || echo FAIL)"
    cat $out/summary.txt
    [[ $code == 0 ]] || print -- "   stderr: $(head -1 $out/stderr.log)"
    [[ $guard_code == 0 ]] || stop "MenuBarAgent's store changed outside the lab identity ($out/guard.json)"
    [[ $code == 0 && $summary_code == 0 && $defaults_code == 0 ]]
}

print -- "run-trace: $run_id, $runs run(s) per variant, executable $executable, evidence $evidence"
failed=0
for variant in off on inv; do
    for n in {1..$runs}; do
        trace_one $variant $n || failed=1
    done
done
rmdir $work 2> /dev/null || true
print -- "run-trace: $([[ $failed == 0 ]] && echo 'every run complete with its oracle holding (off, on: divider | others | icon; inv: an inverted layout carries the notice), guard passed' || echo 'a run FAILED') ($evidence)"
exit $failed
