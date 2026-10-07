#!/bin/zsh
# Remembered positions on macOS 27, measured with the harness's own two status
# items only (plan 2026-10-07-icebar-preference-hiding, S2 design, T2b): the
# dragged one, T, under com.icespike4.target and the anchor, P, under
# com.icespike4.protected, each a `vzhelper --items 1 --autosave <name of this
# run>`. Per run, four questions, each answered or recorded as not measured
# with the reason:
#   Q1 does MenuBarAgent record an undragged item, and when (3 s, 30 s, after quit);
#   Q2 after a Command-drag of T across P: MenuBarAgent's entry for T and T's
#      own `NSStatusItem Preferred Position <name>`, before and after;
#   Q3 T quit and relaunched: is it back in the dragged slot;
#   Q4 T relaunched with a contradicting seed (0.1) in its own defaults: which wins.
# Q3 and Q4 are three reads a second apart after the store has settled, and a
# verdict only when all three agree (trace-tool.py remembered). P is launched
# first, so T, a new item, lands left of it and is dragged to its right: a T
# that is right of P after a relaunch was put back, not placed afresh (a fresh
# item lands leftmost), and the seed's place is the rightmost, not beside P.
#
#   run-remembered.sh <apps directory of build.sh> <scratch directory outside ~/Documents> [runs, 1-5, default 3]
#
# Side effects: two status items of the helpers on the bar for about a minute
# and a half per run (the bar reflows while they are there); per run up to
# three Command-drags of T across P by ../dragown.swift -- synthetic mouse and
# Command events in this session and a moved cursor for about 2 s each, refused
# or aborted on any hardware input (its header says what guards it); the two
# helpers' own defaults domains (deleted and verified empty at the end).
# Left behind: MenuBarAgent's entries for the two helper identities (the store
# is not ours to write). The store is guarded on every read: a change outside
# the run's own two entries stops the runner. (It stopped the first live run:
# MenuBarAgent rewrote other items' values when it recorded the helpers'.)
# Evidence (this account only): ~/IceReverse-evidence/<run id>-remembered/;
# per run, answers.jsonl holds one line per reading or answer (q1-q4, and
# `final`: T's entry and default after everything -- no answer to any of the
# four once T was dragged; when no drag moved it, Q1's after-quit read of T).
set -euo pipefail
umask 077
here=${0:A:h}
tool=$here/trace-tool.py
source $here/t7-lib.zsh
source $here/store-lib.zsh
die() { print -u2 -- "run-remembered: $1"; exit 2; }

given_apps=${1:?apps directory of build.sh}
given_scratch=${2:?scratch directory outside ~/Documents}
# As given, before anything is resolved (and without the trailing slashes
# that make -L follow it): a link would pass every check below as the
# directory it points to.
for given in $given_apps $given_scratch; do
    while [[ $given == ?*/ ]]; do given=${given%/}; done
    [[ ! -L $given ]] || die "$given is a symbolic link"
done
apps=${given_apps:A}
scratch=${given_scratch:A}
runs=${3:-3}
plan_runs=3
target_id=com.icespike4.target
anchor_id=com.icespike4.protected
# MenuBarAgent's key for an item of these ad-hoc helpers is
# status:<process name>::<autosave name>, not the bundle id (MEASURED, run
# 20261008-081444-y8GnWW). The guard allows the run's two exact keys only.
helper_process=vzhelper
seed=0.1 # the smallest position: the rightmost item (trace-tool.py judges Q4 on that)
drag_attempts=3
idle_patience=90 # s to wait, before each attempt, for the quiet dragown wants
drag_limit=30 # s; dragown's own watchdog is 10
undragged_reads=(3 30) # s after launch (Q1)
settled_reads=3 # trace-tool.py's SETTLED_READS
relaunch_settle=2 # s for a relaunched item to be placed before the store is read
helper_lifetime=900 # s; a run takes about 90, plus the waits for quiet

# What is executed is this account's own: the directory, and with `tree`
# everything in it, is no link, no other account's and not writable by one.
# (Not checked: ACLs, and the directories above it.)
own_only() { # <directory> [tree]
    local depth=(-maxdepth 0) foreign
    [[ ${2:-} == tree ]] && depth=()
    foreign=$(find $1 $depth \( -type l -o ! -user $UID -o -perm +022 \) -print -quit) || die "$1 could not be checked"
    [[ -d $1 && -z $foreign ]] || die "${foreign:-$1} is a link, another account's or writable by one"
}

[[ $runs == <1-5> ]] || die "runs must be 1-5"
own_only $apps
for app bundle_id in Target $target_id Protected $anchor_id; do
    [[ -x $apps/$app.app/Contents/MacOS/vzhelper ]] || die "$apps/$app.app is not a helper built by build.sh"
    own_only $apps/$app.app tree
    [[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" $apps/$app.app/Contents/Info.plist) == $bundle_id ]] \
        || die "$apps/$app.app is not $bundle_id"
done
[[ ${scratch:A:l} != ${HOME:l}/documents* ]] || die "scratch must be outside ~/Documents (iCloud breaks codesign)"
t7_private_directory $scratch || exit 2
own_only $scratch
work=$(mktemp -d $scratch/remembered.XXXXXX) || exit 2
dragown=$work/dragown
swiftc -O $here/../dragown.swift -o $dragown 2> $work/swiftc.log || die "dragown.swift did not compile ($work/swiftc.log)"
$dragown selftest 2> $work/selftest.log || die "dragown's rules fail their self-test ($work/selftest.log)"
(( $(ps -ax -o comm= | grep -c '/vzhelper$' || true) == 0 )) || die "a vzhelper is already running"
for bundle_id in $target_id $anchor_id; do
    t7_domain_is_empty $bundle_id || die "$bundle_id already has defaults; not a clean domain"
done

run_id=$(date +%Y%m%d-%H%M%S)-${work:t:e}
stamp=${run_id//[^A-Za-z0-9]/}
evidence=$HOME/IceReverse-evidence/$run_id-remembered
mkdir -p $evidence
defaults export "$menubar_store" $evidence/store-before.plist || die "MenuBarAgent's store could not be saved"

typeset -A helper_fd helper_pid # by role: target, anchor
out= t_name= p_name= t_key= p_key=

still_runs() { # <pid>: still the helper this script started
    [[ $(ps -p $1 -o comm= 2> /dev/null) == */vzhelper ]]
}

# The helper's stdin stays open in this script: EOF is its quit, and it exits
# with this script whatever happens (--controller).
launch_helper() { # <role> <app> <identifier and autosave name> <glyph> <log>
    local role=$1 fifo=$work/fifo-$1 fd
    mkfifo $fifo || return 1
    $apps/$2.app/Contents/MacOS/vzhelper --controller $$ --items 1 --identifiers $3 --glyphs $4 --autosave $3 \
        --lifetime $helper_lifetime < $fifo > $5 2>&1 &
    helper_pid[$role]=$!
    exec {fd}> $fifo
    rm -f -- $fifo
    helper_fd[$role]=$fd
    for _ in {1..50}; do
        grep -q '^up ' $5 && return 0
        sleep 0.2
    done
    print -u2 -- "run-remembered: the $role helper did not come up ($5)"
    return 1
}

quit_helper() { # <role>
    local fd=${helper_fd[$1]:-} pid=${helper_pid[$1]:-}
    [[ -z $fd ]] || exec {fd}>&-
    unset "helper_fd[$1]" "helper_pid[$1]"
    [[ -n $pid ]] || return 0
    for _ in {1..25}; do
        still_runs $pid || return 0
        sleep 0.2
    done
    kill -TERM $pid 2> /dev/null || true
    sleep 0.5
    ! still_runs $pid
}

clear_domains() { # the helpers' own defaults: deleted, then verified empty
    local bundle_id result=0
    for bundle_id in $target_id $anchor_id; do
        defaults delete $bundle_id > /dev/null 2>&1 || true
        t7_domain_is_empty $bundle_id || { print -u2 -- "run-remembered: $bundle_id still has defaults after the delete"; result=1; }
    done
    return $result
}

cleaned=0
cleanup() {
    (( cleaned )) && return
    cleaned=1
    trap '' INT TERM HUP QUIT
    local helpers=stopped domains=empty
    quit_helper target || helpers="the target helper is still running"
    quit_helper anchor || helpers="the anchor helper is still running"
    clear_domains || domains="NOT empty"
    rm -rf -- $work
    print -- "run-remembered: helpers $helpers; helper defaults $domains; left in MenuBarAgent's store: the two helper identities' entries"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'exit 131' QUIT

stop() { # <reason>: the owner's store may have changed; nothing more is launched
    print -u2 -- "run-remembered: $1; stopped. The store as it was: $evidence/store-before.plist"
    exit 1
}

# The store into $out/store-<label>.json, guarded against the run's first read.
checked_store() { # <label> [settled]
    local file=$out/store-$1.json
    if [[ ${2:-} == settled ]]; then
        settled_store $file || stop "MenuBarAgent's store could not be read back"
    else
        export_store $file || stop "MenuBarAgent's store could not be read"
    fi
    python3 -I $tool guard $out/store-before.json $file $t_key $p_key > $out/guard-$1.json \
        || stop "MenuBarAgent's store changed outside the run's two entries ($out/guard-$1.json)"
}

agent_entry() { # <store label> <key> -> a JSON number or null
    python3 -I $tool entry $out/store-$1.json $2
}

own_default() { # -> T's own preferred position, a number or null
    local value
    value=$(defaults read $target_id "NSStatusItem Preferred Position $t_name" 2> /dev/null) || value=
    if t7_is_number "$value"; then print -- $value; else print -- null; fi
}

# T against P: "side":"left"|"right","adjacent":true|false,"x":<T's frame>; all null when either is not found.
layout_now() {
    local line side adjacent x
    if line=$($dragown read $t_name $p_name 2> /dev/null) && side=$(t7_json_get "$line" side) && [[ $side == (left|right) ]] \
        && adjacent=$(t7_json_get "$line" adjacent) && [[ $adjacent == (true|false) ]] \
        && x=$(t7_json_get "$line" target.frame.0) && t7_is_number "$x"; then
        print -- "\"side\":\"$side\",\"adjacent\":$adjacent,\"x\":$x"
    else
        print -- '"side":null,"adjacent":null,"x":null'
    fi
}

record() { # <key> <json value> ...: one answer of this run
    python3 -I -c 'import json, sys
print(json.dumps(dict(zip(sys.argv[1::2], map(json.loads, sys.argv[2::2]))), sort_keys=True))' "$@" >> $out/answers.jsonl \
        || stop "an answer could not be recorded ($*)"
}

not_measured() { # <question> <reason>
    record question "\"$1\"" measured false reason "\"$2\""
}

# Waits until dragown would not refuse for recent hardware input, or the
# patience runs out; dragown itself still decides.
await_quiet() {
    local line waited=0
    while (( waited < idle_patience )); do
        if line=$($dragown read $t_name $p_name 2> /dev/null) && [[ $(t7_json_get "$line" idleEnough) == true ]]; then return 0; fi
        sleep 2
        waited=$(( waited + 2 ))
    done
}

# One drag-<attempt>.json each, with the store (guarded) and T's own default
# read just before it as store-pre-drag-<attempt>.json and
# default-pre-drag-<attempt>.json; $moved_attempt is the attempt that took T
# to the other side of P.
moved_attempt=
drag() { # -> 0 when T ended on the other side of P
    local attempt code
    moved_attempt=
    for attempt in {1..$drag_attempts}; do
        await_quiet
        checked_store pre-drag-$attempt
        own_default > $out/default-pre-drag-$attempt.json
        code=0
        perl -e 'alarm shift; exec @ARGV' $drag_limit $dragown drag $t_name $p_name \
            > $out/drag-$attempt.json 2> $out/drag-$attempt.log || code=$?
        print -- "   drag attempt $attempt: exit $code $(< $out/drag-$attempt.json)"
        # 0 moved, 1 not moved, 3 refused, 4 aborted: dragown let go itself (2,
        # usage, posted nothing). Anything else is a dragown that died, or
        # could not let go for certain (5): let go for it.
        if [[ $code != (0|1|2|3|4) ]]; then
            $dragown release > $out/drag-$attempt-release.json 2>&1 || stop "dragown died (exit $code) and its release failed too: the button or Command may be held"
        fi
        if (( code == 0 )); then
            moved_attempt=$attempt
            return 0
        fi
    done
    return 1
}

# Q3 and Q4: after the store has settled, three reads a second apart of
# (MenuBarAgent's entry, T's own default, T's side of P, whether it is beside
# it, its x), and their verdict; $verdict keeps it (Q3's is Q4's control).
verdict=
relaunched_verdict() { # <q3|q4> <dragged side> [Q3's verdict, for q4]
    local question=$1 number label measured=true
    verdict=
    sleep $relaunch_settle
    : > $out/$question-reads.jsonl
    for number in {1..$settled_reads}; do
        label=$question-$number
        if (( number == 1 )); then
            checked_store $label settled
        else
            sleep 1
            checked_store $label
        fi
        print -- "{\"agent\":$(agent_entry $label $t_key),\"default\":$(own_default),$(layout_now)}" >> $out/$question-reads.jsonl
    done
    python3 -I $tool remembered $question $2 $out/$question-reads.jsonl ${3:-} > $out/$question.json || true
    verdict=$(t7_json_get "$(< $out/$question.json)" verdict) || stop "the verdict of $question could not be computed ($out/$question.json)"
    [[ $verdict != inconclusive ]] || measured=false
    record question "\"$question\"" measured $measured result "$(< $out/$question.json)"
}

# Runs under `||`, where zsh does not apply errexit: what an answer rests on
# is checked explicitly.
measure_one() { # <n>: one run; fails only when the harness itself did
    local n=$1
    out=$evidence/run$n
    t_name=vz-rem-$stamp-$n-t
    p_name=vz-rem-$stamp-$n-p
    t_key=status:$helper_process::$t_name
    p_key=status:$helper_process::$p_name
    mkdir -p $out
    clear_domains || return 1
    export_store $out/store-before.json || stop "MenuBarAgent's store could not be read"

    # P first: a new item lands leftmost (E2), so T arrives left of P and the
    # drag takes it to P's right (the header says why). dragown refuses a
    # layout in which the two are not adjacent.
    launch_helper anchor Protected $p_name reference $out/helper-p.log || return 1
    local anchor_up=$SECONDS
    launch_helper target Target $t_name target $out/helper-t-1.log || return 1
    # The reads are timed from T, the later of the two; each row says how long
    # each item had been up (whole seconds).
    local target_up=$SECONDS at remaining
    for at in $undragged_reads; do
        remaining=$(( target_up + at - SECONDS ))
        if (( remaining > 0 )); then sleep $remaining; fi
        checked_store ${at}s
        record question '"q1"' at "\"${at}s\"" targetUpSeconds $(( SECONDS - target_up )) anchorUpSeconds $(( SECONDS - anchor_up )) \
            target "$(agent_entry ${at}s $t_key)" \
            anchor "$(agent_entry ${at}s $p_key)" targetDefault "$(own_default)"
    done

    # The dragged slot: T's side of P as dragown saw it settle, and only a slot
    # when T is beside P there. Empty when no drag moved T.
    local dragged_side= beside=false
    if drag; then
        local moved=$(< $out/drag-$moved_attempt.json) before=pre-drag-$moved_attempt
        checked_store dragged settled
        dragged_side=$(t7_json_get "$moved" after.side)
        [[ $dragged_side == (left|right) ]] || stop "dragown reported a move without a side ($out/drag-$moved_attempt.json)"
        beside=$(t7_json_get "$moved" after.adjacent) || stop "dragown reported a move without its adjacency ($out/drag-$moved_attempt.json)"
        record question '"q2"' measured true sideBefore "\"$(t7_json_get "$moved" before.side)\"" sideAfter "\"$dragged_side\"" \
            besideAfter $beside \
            agentBefore "$(agent_entry $before $t_key)" agentAfter "$(agent_entry dragged $t_key)" \
            defaultBefore "$(< $out/default-$before.json)" defaultAfter "$(own_default)" \
            anchorAgentBefore "$(agent_entry $before $p_key)" anchorAgentAfter "$(agent_entry dragged $p_key)"
    else
        not_measured q2 "no drag took T across P in $drag_attempts attempts (drag-*.json)"
    fi

    if [[ -z $dragged_side ]]; then
        not_measured q3 "no dragged slot to return to"
        not_measured q4 "no dragged slot to return to"
    elif [[ $beside != true ]]; then
        not_measured q3 "the drag left T on the $dragged_side of P but not beside it: no slot to recognise"
        not_measured q4 "the drag left T on the $dragged_side of P but not beside it: no slot to recognise"
    else
        quit_helper target || return 1
        launch_helper target Target $t_name target $out/helper-t-2.log || return 1
        relaunched_verdict q3 $dragged_side

        quit_helper target || return 1
        record question '"q4"' step '"beforeSeed"' default "$(own_default)"
        local kept=$verdict
        defaults write $target_id "NSStatusItem Preferred Position $t_name" -float $seed || stop "the seed could not be written"
        local seeded=$(own_default)
        [[ $seeded != null ]] && (( seeded > seed - 0.001 && seeded < seed + 0.001 )) || stop "the seed reads back as $seeded, not $seed"
        record question '"q4"' step '"seedWritten"' default $seeded
        launch_helper target Target $t_name target $out/helper-t-3.log || return 1
        relaunched_verdict q4 $dragged_side $kept
    fi

    quit_helper target || return 1
    quit_helper anchor || return 1
    sleep 2 # let MenuBarAgent record the items' removal before the store is read again
    checked_store after-quit settled
    # P was never dragged itself: its entry after its quit is Q1's last read,
    # with whether T was dragged across it (P gave way then). T's is no answer
    # to Q1 once it was dragged, relaunched and seeded: kept apart.
    record question '"q1"' at '"afterQuit"' anchor "$(agent_entry after-quit $p_key)" \
        displacedByTheDrag $([[ -n $dragged_side ]] && print true || print false)
    record question '"final"' target "$(agent_entry after-quit $t_key)" targetDefault "$(own_default)"
    clear_domains
}

print -- "run-remembered: $run_id, $runs run(s), evidence $evidence"
(( runs == plan_runs )) || print -- "run-remembered: $runs run(s) is not the plan's $plan_runs: a trial, not T2b's measurement"
failed=0
for n in {1..$runs}; do
    code=0
    measure_one $n || code=$?
    print -- "run $n: $([[ $code == 0 ]] && echo complete || echo 'FAILED (the harness, not an answer)')"
    [[ -f $evidence/run$n/answers.jsonl ]] && sed 's/^/   /' $evidence/run$n/answers.jsonl
    if (( code != 0 )); then
        failed=1
        quit_helper target || true
        quit_helper anchor || true
    fi
done
print -- "run-remembered: $([[ $failed == 0 ]] && echo 'every run complete, guard passed' || echo 'a run FAILED') ($evidence)"
exit $failed
