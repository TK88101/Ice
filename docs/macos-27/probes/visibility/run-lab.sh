#!/bin/zsh -f
# The lab matrix (plan 2026-10-07-icebar-preference-hiding, S4 and its design
# D1-D5): the ONE command the owner starts in the `icetest` session, in front,
# at a time the owner names, and then leaves the Mac alone. It runs every
# scenario of the matrix against the staged Ice, each with its own fresh copy
# and identity, judges each run with lab-tool.py, and prints the report.
#
#   /Users/Shared/IceReverse-lab/run-lab.sh               the matrix: up to three rounds
#   /Users/Shared/IceReverse-lab/run-lab.sh <scenario>    one scenario, once
#   /Users/Shared/IceReverse-lab/run-lab.sh --dry-run     the guards only; starts nothing
#
# Everything it trusts is in its own directory, written by stage-lab.sh: no
# environment variable and no file it did not hash changes what it does; it
# sources nothing. On every way out (also INT, TERM, HUP, its watchdog) it
# stops Ice, quits the helpers, deletes the defaults domains it created and
# prints the report so far.
#
# Side effects, all in this account: Ice copies and sacrificial helper items
# on the bar for the length of the run; the helpers' and the copies' defaults
# domains (deleted and checked empty at the end); MenuBarAgent's records of
# them (left: they cannot be removed by us; about 100 keys a round, D2); the
# menus helper and Terminal brought to the front in turn (`front-*`,
# `crowded`). It never moves, clicks or presses anything that is not ours, and
# never posts an input event.
set -uo pipefail
umask 022
PATH=/usr/bin:/bin:/usr/sbin:/sbin
zmodload zsh/datetime

shared=${0:a:h}
tool=$shared/lab-tool.py
apps=$shared/apps
icewatch=$apps/icewatch
usage="usage: run-lab.sh [--dry-run | <scenario>]"

# --- arguments ----------------------------------------------------------------------

dry_run=0
only=
case ${1:-} in
    "") ;;
    --dry-run) dry_run=1 ;;
    [a-z]*) only=$1 ;;
    *) print -u2 -- $usage; exit 64 ;;
esac
(( $# <= 1 )) || { print -u2 -- $usage; exit 64; }

# --- lab.env, read as words ------------------------------------------------------------

# Defaults of what tests may change; the staging writes none of them.
# A first calibration under the capture bursts (plan 2026-10-09-lab-first-run-followup,
# S3): up to 24 observations, two to a burst of about 26.5 s, about 350 s.
STATUS_LIMIT=600
START_LIMIT=20
TIME_SCALE=1
CAPTURE=1
ROUNDS=3
KEY_BUDGET=1500
HELPER_LIFETIME=10800
RUN_LIMIT=28800
required=(EXPECT_USER OWNER_USER GIT_REV ICE_SHA TARGET_SHA PROTECTED_SHA MENUS_SHA ICEWATCH_SHA TOOL_SHA)
optional=(STATUS_LIMIT START_LIMIT TIME_SCALE CAPTURE ROUNDS KEY_BUDGET HELPER_LIFETIME RUN_LIMIT)
seen=()
while IFS='=' read -r key value; do
    if (( ! ${${required}[(Ie)$key]} && ! ${${optional}[(Ie)$key]} )) || [[ ! $value =~ '^[A-Za-z0-9._,/-]+$' ]]; then
        print -u2 -- "run-lab: lab.env has a line it does not know (${key[1,40]}); stopped."
        exit 2
    fi
    typeset -g "$key=$value"
    seen+=($key)
done < $shared/lab.env
for key in $required; do
    (( ${seen[(Ie)$key]} )) || { print -u2 -- "run-lab: lab.env lacks $key; stopped."; exit 2; }
done
[[ $STATUS_LIMIT == <1-> && $START_LIMIT == <1-> && $CAPTURE == [01] && $ROUNDS == <1-3> && $KEY_BUDGET == <1->
    && $HELPER_LIFETIME == <1-10800> && $RUN_LIMIT == <1-> && $TIME_SCALE =~ '^[0-9]+(\.[0-9]+)?$' ]] \
    || { print -u2 -- "run-lab: a value in lab.env is out of range; stopped."; exit 2; }

scenarios=(${=$(/usr/bin/python3 -I $tool order 2>/dev/null)})
if [[ -n $only ]] && (( ! ${scenarios[(Ie)$only]} )); then
    print -u2 -- "run-lab: no scenario $only (${scenarios[*]})"
    exit 64
fi

# --- guards ----------------------------------------------------------------------------

guard_failed=0
guard() { # <enforced in a dry run: 0|1> <message>
    if (( dry_run )) && (( ! $1 )); then
        print -- "(dry run, reported only) $2"
    else
        print -u2 -- "run-lab: $2"
        guard_failed=1
    fi
}

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
# Every file's sha256 with its relative path, and every link's target, sorted
# in the C locale (as t7-lib.zsh's t7_sha_tree: made in one account, checked in another).
sha_tree() {
    (
        cd "$1" || exit 1
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
        find . -type l | LC_ALL=C sort | while read -r link; do print -r -- "$link -> $(readlink "$link")"; done
    ) | shasum -a 256 | cut -d' ' -f1
}

[[ $(id -un) == $EXPECT_USER ]] || guard 0 "this account is $(id -un), not $EXPECT_USER"
for file in $shared $shared/lab.env $shared/run-lab.sh $tool $shared/Ice.app $apps/Target.app/Contents/MacOS/vzhelper \
    $apps/Protected.app/Contents/MacOS/vzhelper $apps/Menus.app/Contents/MacOS/vzhelper $icewatch; do
    [[ ! -L $file && $(stat -f %Su $file 2>/dev/null) == $OWNER_USER ]] || guard 1 "$file is not $OWNER_USER's"
    [[ ! -w $file ]] || guard 0 "this account can write $file"
done
(( guard_failed )) && exit 2
staged_ok=1
[[ $(sha_tree $shared/Ice.app) == $ICE_SHA ]] || staged_ok=0
for name file want in Target $apps/Target.app/Contents/MacOS/vzhelper $TARGET_SHA Protected $apps/Protected.app/Contents/MacOS/vzhelper $PROTECTED_SHA \
    Menus $apps/Menus.app/Contents/MacOS/vzhelper $MENUS_SHA icewatch $icewatch $ICEWATCH_SHA lab-tool $tool $TOOL_SHA; do
    [[ $(sha $file) == $want ]] || { print -u2 -- "run-lab: $name is not the staged file"; staged_ok=0; }
done
(( staged_ok )) || guard 1 "the staged files do not match lab.env's sha256"
ours=$(ps -U $(id -u) -o comm= | grep -c -E '/IceLab[A-Za-z0-9]*$|/vzhelper$' || true)
(( ours == 0 )) || guard 0 "$ours Ice copy or helper process(es) of ours are already running"
preflight=$($icewatch preflight 2>/dev/null)
[[ $preflight == *'"axTrusted":true'* && $preflight == *'"screenCapture":true'* ]] \
    || guard 1 "Terminal lacks Accessibility or Screen Recording: $preflight"
menu_frame=$($icewatch menu-frame 2>/dev/null)
# The scenarios that verify need the front app's menu to end left of the notch
# (2026-09-29: past it the check cannot read the bar): Terminal, in front.
[[ $menu_frame == *'"verdict":"fits"'* ]] || guard 1 "the app in front must have a short menu (Terminal, in front); icewatch menu-frame: ${menu_frame:-nothing}"
(( guard_failed )) && exit 2

if (( dry_run )); then
    print -- "run-lab dry run: the guards pass ($GIT_REV; preflight $preflight)."
    print -- "  It would run ${only:-the matrix: ${scenarios[*]}} (${only:+once}${only:-up to $ROUNDS rounds, stopping after an unclean round 1})."
    print -- "  Each scenario: a fresh copy of $shared/Ice.app with its own bundle id and executable, started with -IceLabReport YES;"
    print -- "  sacrificial helpers under com.icespike4.target / .protected; evidence in $shared/evidence/<run id>/."
    print -- "dry run: nothing was started and nothing written."
    exit 0
fi

# --- state and cleanup ---------------------------------------------------------------------

run_id=$(date +%Y%m%d-%H%M%S)
run=$shared/evidence/$run_id
stage=$run/stage
mkdir -m 755 $run || { print -u2 -- "run-lab: could not create $run"; exit 2; }
mkdir -m 700 $stage
: > $run/domains.txt
: > $run/timeline.txt
ice_pid=
ice_exec=
ice_fd=
helper_pids=()
helper_fds=()
ref_pids=()
ref_fds=()
ref_ids=()
menus_pid=
menus_fd=
# Every helper this run started, from the moment it starts: the cleanup quits
# them all, also one that was starting when a signal came.
spawned_pids=()
terminal_pid=
watchdog_pid=
caffeinate_pid=
cleaned=0

note() { print -r -- "$(date +%H:%M:%S) $*" >> $run/timeline.txt; }
nap() { sleep $(( $1 * TIME_SCALE )); }
still_runs() { [[ $(ps -p $1 -o command= 2>/dev/null) == *$2* ]]; }
lab() { /usr/bin/python3 -I $tool "$@"; }

remember_domain() { grep -qxF -- $1 $run/domains.txt || print -r -- $1 >> $run/domains.txt; }
domain_is_empty() {
    local now result=1
    now=$(mktemp -t labprefs) || return 1
    defaults export $1 $now 2>/dev/null && [[ $(plutil -p $now) == $'{\n}' ]] && result=0
    rm -f $now
    return $result
}

stop_ice() {
    [[ -n $ice_fd ]] && { exec {ice_fd}>&-; ice_fd=; }
    [[ -n $ice_pid ]] || return 0
    still_runs $ice_pid $ice_exec && kill -TERM $ice_pid 2>/dev/null
    for _ in {1..25}; do still_runs $ice_pid $ice_exec || break; sleep 0.2; done
    still_runs $ice_pid $ice_exec && kill -KILL $ice_pid 2>/dev/null
    for _ in {1..10}; do still_runs $ice_pid $ice_exec || break; sleep 0.2; done
    if still_runs $ice_pid $ice_exec; then
        note "Ice $ice_pid is still running"
        return 1
    fi
    note "Ice $ice_pid stopped"
    ice_pid=
}

quit_pids() { # <pids...>: their stdin is already closed
    local pid
    for pid in "$@"; do
        for _ in {1..15}; do still_runs $pid /vzhelper || break; sleep 0.2; done
        still_runs $pid /vzhelper && kill -TERM $pid 2>/dev/null
    done
}

quit_members() {
    local fd
    for fd in $helper_fds; do exec {fd}>&-; done
    quit_pids $helper_pids
    helper_fds=()
    helper_pids=()
}

quit_references() {
    local fd
    for fd in $ref_fds; do exec {fd}>&-; done
    quit_pids $ref_pids
    ref_fds=()
    ref_pids=()
    ref_ids=()
}

quit_menus() {
    [[ -n $menus_fd ]] && { exec {menus_fd}>&-; menus_fd=; }
    [[ -n $menus_pid ]] && quit_pids $menus_pid
    menus_pid=
}

delete_domains() { # returns 1 when one could not be emptied
    local domain result=0
    for domain in ${(f)"$(<$run/domains.txt)"}; do
        defaults delete $domain >/dev/null 2>&1
        domain_is_empty $domain || { print -u2 -- "run-lab: $domain STILL HAS DEFAULTS; delete it by hand: defaults delete $domain"; result=1; }
    done
    return $result
}

cleanup() {
    (( cleaned )) && return
    cleaned=1
    trap '' INT TERM HUP QUIT
    local code=$1 domains=verified
    [[ -n $watchdog_pid ]] && kill $watchdog_pid 2>/dev/null
    stop_ice || code=1
    quit_members
    quit_references
    quit_menus
    # Every helper this run started, also one a signal caught while it started:
    # given a moment to end, then terminated.
    quit_pids $spawned_pids
    delete_domains || { domains=FAILED; code=1; }
    rm -rf -- $stage
    [[ -n $caffeinate_pid ]] && kill $caffeinate_pid 2>/dev/null
    note "cleanup: domains $domains"
    print
    {
        print -- "==== lab matrix $run_id ($GIT_REV) ===="
        lab report $run
        print -- "defaults domains of the run: $domains"
        print -- "evidence: $run"
    } | tee $run/report.txt
    exit $code
}

trap 'cleanup 130' INT
trap 'cleanup 143' TERM
trap 'cleanup 129' HUP
trap 'cleanup 131' QUIT
trap 'cleanup $?' EXIT
# Gives up without a signal if this script is already gone (its pid may be reused).
perl -e 'sleep $ARGV[0]; kill "TERM", $ARGV[1] if getppid() == $ARGV[1]' $RUN_LIMIT $$ &
watchdog_pid=$!
caffeinate -dis -w $$ &
caffeinate_pid=$!
# The app in front now is the one `front-*` and `crowded` bring back.
terminal_pid=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null | sed -n 's/.*"pid"=\([0-9]*\).*/\1/p')
note "run $run_id rev $GIT_REV front $terminal_pid preflight $preflight"

# --- MenuBarAgent's store (D2, D5): recorded, never a stop ---------------------------------------

store="$HOME/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar"
export_store() { # <file>
    defaults export "$store" - 2>/dev/null | plutil -convert json -o "$1" - 2>/dev/null || { print -r -- '{"unreadable":true}' > $1; }
}
lab_keys() { # <store json>: how many keys are the lab's
    /usr/bin/python3 -I -c '
import json, sys
store = json.load(open(sys.argv[1]))
entries = store.get("TrailingItemPreferredPositions", {}) if isinstance(store, dict) else {}
print(sum(1 for key in entries if "vz-lab-" in key or "com.icespike4.lab." in key or "::Ice.ControlItem." in key and "IceLab" in key))
' $1 2>/dev/null || print 0
}
export_store $run/store-before.json
keys=$(lab_keys $run/store-before.json)
print -- "run-lab: $run_id; MenuBarAgent holds $keys lab key(s) (budget $KEY_BUDGET)"
if (( keys > KEY_BUDGET )); then
    print -u2 -- "run-lab: more than $KEY_BUDGET lab keys in MenuBarAgent's store: see the README (a new lab account); stopped."
    exit 2
fi

# --- helpers --------------------------------------------------------------------------------

# Starts a helper with its stdin on a FIFO this script holds open (its EOF is
# the helper's quit). Sets REPLY_PID and REPLY_FD.
start_helper() { # <app> <log> <vzhelper arguments...>
    local app=$1 log=$2 fifo=$run/.fifo-$RANDOM fd
    shift 2
    mkfifo $fifo || return 1
    $apps/$app/Contents/MacOS/vzhelper --controller $$ "$@" --lifetime $HELPER_LIFETIME < $fifo > $log 2>&1 &
    REPLY_PID=$!
    spawned_pids+=($REPLY_PID)
    exec {fd}> $fifo
    rm -f $fifo
    REPLY_FD=$fd
    for _ in {1..50}; do grep -q '^up ' $log && return 0; sleep 0.2; done
    note "helper $app did not come up ($log)"
    return 1
}

glyphs=(target hidden2 hidden3 hidden4 ell gamma zed vee wedge)

# One member, its identifier and autosave name new in this run (D2).
start_member() { # <dir> <identifier> <glyph>
    start_helper Target.app $1/helper-$2.log --items 1 --identifiers $2 --glyphs $3 --autosave $2 --menu || return 1
    helper_pids+=($REPLY_PID)
    helper_fds+=($REPLY_FD)
    remember_domain com.icespike4.target
    note "member $2 up"
}

start_references() { # <round>
    local i id
    for i in 1 2; do
        id=vz-lab-$run_id-$1ref$i
        start_helper Protected.app $run/helper-$1-$id.log --items 1 --identifiers $id --glyphs ${${(s: :):-reference alt}[i]} --autosave $id || return 1
        ref_pids+=($REPLY_PID)
        ref_fds+=($REPLY_FD)
        ref_ids+=($id)
    done
    remember_domain com.icespike4.protected
    note "references up: $ref_ids"
}

start_menus() { # <dir> <count>
    start_helper Menus.app $1/helper-menus.log --role menus || return 1
    menus_pid=$REPLY_PID
    menus_fd=$REPLY_FD
    remember_domain com.icespike4.protected
    print -u $menus_fd -- "menus $2"
}

bring_forward() { # [pid]: fails when there is none or it did not come forward
    [[ -n ${1:-} ]] && $icewatch activate --pid $1 >/dev/null 2>&1
}

# --- one Ice copy ----------------------------------------------------------------------------

# Copies the staged Ice under its own bundle id and executable name, re-signed (D2).
stage_ice() { # <bundle id> <executable> -> path
    local dir=$stage/$1 app
    mkdir -p -- $dir || return 1
    app=$dir/Ice.app
    ditto -- $shared/Ice.app $app || return 1
    # The staged bundle is read-only to this account; its copy is this run's.
    chmod -R u+w $app || return 1
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $1" $app/Contents/Info.plist || return 1
    mv -- $app/Contents/MacOS/Ice $app/Contents/MacOS/$2 || return 1
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $2" $app/Contents/Info.plist || return 1
    codesign --force --deep --sign - $app 2> $dir/codesign.log || return 1
    codesign --verify --deep --strict $app 2>> $dir/codesign.log || return 1
    print -r -- $app
}

# Starts a staged copy with the report on; its standard output to a file
# (never a pipe, D1), its commands through a FIFO this script holds.
start_ice() { # <app> <executable> <bundle id> <report file> <always-hidden true|false> [hold]
    local app=$1 exec=$2 id=$3 report=$4 fifo=$run/.ice-fifo-$RANDOM fd hold=()
    [[ ${6:-} == hold ]] && hold=(-IceLabHoldLength YES)
    remember_domain $id
    if [[ ! -s $report ]]; then
        defaults write $id UseIceBar -bool true
        defaults write $id ShowOnHover -bool false
        defaults write $id ShowOnScroll -bool false
        defaults write $id EnableAlwaysHiddenSection -bool $5
    fi
    mkfifo $fifo || return 1
    : > $report
    OS_ACTIVITY_DT_MODE=YES $app/Contents/MacOS/$exec -IceLabReport YES $hold -SUEnableAutomaticChecks NO -SUAutomaticallyUpdate NO \
        < $fifo > $report 2> ${report%.jsonl}.log &
    ice_pid=$!
    ice_exec=$app/Contents/MacOS/$exec
    exec {fd}> $fifo
    rm -f $fifo
    ice_fd=$fd
    note "Ice $id started, pid $ice_pid"
    lab wait $report $START_LIMIT $ice_pid started >/dev/null
}

send_ice() { [[ -n $ice_fd ]] && print -u $ice_fd -- "$*"; }

# --- the scenario's record -------------------------------------------------------------------

dir=
report=
# The report's last complete line's seq: its line number (lab-tool.py's judge
# refuses a report where they differ).
seq_now() { [[ -f $report ]] && print $(( $(wc -l < $report) )) || print 0; }
mark() { # <step> [raw JSON fields]
    local seq=$(seq_now)
    print -r -- "{\"step\":\"$1\",\"seq\":${seq:-0},\"t\":$EPOCHREALTIME${2:+,$2}}" >> $dir/steps.jsonl
}
abort_run() { # <why>
    mark aborted "\"why\":\"$1\""
    note "$(basename $dir): aborted: $1"
    return 1
}

# Waits for a predicate on the current report, in one lab-tool.py process
# that reads only what was appended (D5); a damaged report or Ice ending
# aborts the run.
await() { # <seconds> <predicate> [args...]
    local seconds=$(( $1 * TIME_SCALE )) code
    shift
    lab wait $report $seconds ${ice_pid:-0} "$@" >/dev/null
    code=$?
    case $code in
        0) return 0 ;;
        3) abort_run "the report is damaged"; return 3 ;;
        4) abort_run "Ice ended"; return 3 ;;
        *) return 1 ;;
    esac
}

chevron() { # prints true, false or null
    local line=$($icewatch chevron 2>/dev/null)
    case $line in
        *'"listed":true'*) print true ;;
        *'"listed":false'*) print false ;;
        *) print null ;;
    esac
}

capture() { # <name>
    (( CAPTURE )) || return 0
    local width=${${menu_frame#*\"displayWidth\":}%%[,\}]*} height=${${menu_frame#*\"barHeight\":}%%[,\}]*}
    screencapture -x -R0,0,${width%.*},${height%.*} $dir/bar-$1.png 2>/dev/null
}

expected() { # <scenario> <members, comma-separated> [extra JSON fields]
    local list=${(j:",":)${(s:,:)${2:-}}}
    print -r -- "{\"scenario\":\"$1\",\"members\":[${list:+\"$list\"}],\"blockers\":[]${3:+,$3}}" > $dir/expected.json
}

member_ids() { # <round> <scenario> <count>: this run's identifiers
    local i
    # Not {1..$3}: zsh counts down from 1 to 0.
    for (( i = 1; i <= $3; i++ )); do print -r -- vz-lab-$run_id-$1$2-$i; done
}

# --- scenarios -----------------------------------------------------------------------------------

# The common start: « before anything of ours, a fresh Ice copy, then the members.
begin() { # <round> <scenario> <members> [always-hidden true|false] [hold]
    local round=$1 name=$2 count=$3 always=${4:-false} hold=${5:-} i
    mark chevronAtStart "\"listed\":$(chevron)"
    # A reference lives one round at most (vzhelper's lifetime cap): one that is
    # gone would read as Ice failing its checks.
    local pid
    for pid in $ref_pids; do
        kill -0 $pid 2>/dev/null || { abort_run "a reference helper is gone"; return 1; }
    done
    ice_id=com.icespike4.lab.r$run_id.$round${name//[^a-z0-9]/}
    ice_name=IceLab${run_id//[^0-9]/}$round${${name//[^a-z0-9]/}[1,8]}
    ice_app=$(stage_ice $ice_id $ice_name) || { abort_run "staging the copy failed"; return 1; }
    start_ice $ice_app $ice_name $ice_id $report $always $hold || { abort_run "Ice did not start"; return 1; }
    nap 2
    members=(${(f)"$(member_ids $round $name $count)"})
    for (( i = 1; i <= count; i++ )); do
        start_member $dir $members[i] $glyphs[i] || { abort_run "a member did not start"; return 1; }
    done
    expected $name "${(j:,:)members}"
    capture before
}

finish() {
    capture end
    stop_ice
    quit_members
    quit_menus
}

hide() { # <since>: the first verified, or the status limit
    await $STATUS_LIMIT verified ${1:-0}
    local code=$?
    nap 3
    return $code
}

s_noref() { begin $1 noref 1 && hide; }
s_sparse() { begin $1 sparse 1 && hide; }
s_k2() { begin $1 k2 2 && hide; }
s_k4() { begin $1 k4 4 && hide; }
s_k8() { begin $1 k8 8 && hide; }

s_press() {
    begin $1 press 2 && hide || return
    local id log before i
    send_ice bar open
    nap 2
    for i in {1..${#members}}; do
        id=$members[i]
        log=$dir/helper-$id.log
        before=$(grep -c '^menu .*"open"' $log)
        send_ice press com.icespike4.target $id
        local seen=false
        for _ in {1..20}; do
            (( $(grep -c '^menu .*"open"' $log) > before )) && { seen=true; break; }
            sleep 0.1
        done
        mark menuOpen "\"member\":\"$id\",\"seen\":$seen"
        print -u $helper_fds[i] -- closemenu
        nap 1
    done
    send_ice bar close
    nap 2
}

s_addremove() {
    begin $1 addremove 2 && hide || return
    local third=vz-lab-$run_id-$1addremove-3
    expected addremove "${(j:,:)members}" "\"added\":\"$third\""
    mark added
    start_member $dir $third $glyphs[3] || { abort_run "the third member did not start"; return 1; }
    local since=$(seq_now)
    await $STATUS_LIMIT length-null $since && hide $since || return
    mark removed
    since=$(seq_now)
    local fd=$helper_fds[2]
    exec {fd}>&-
    quit_pids $helper_pids[2]
    await $STATUS_LIMIT length-null $since && hide $since
}

s_crowded() {
    local round=$1 n step_back=0 since key1 key2 listed
    start_menus $dir 0 || { abort_run "the menus helper did not start"; return 1; }
    bring_forward $menus_pid || { abort_run "the menus helper could not be brought forward"; return 1; }
    begin $round crowded 2 || return
    since=$(seq_now)
    for n in {0..40}; do
        print -u $menus_fd -- "menus $n"
        nap 2.5
        if lab await $report any-length $since >/dev/null; then
            mark witness '"ok":false,"why":"a length came before the bracketed witness"'
            break
        fi
        if lab await $report divider-unusable >/dev/null; then
            (( step_back )) && { mark witness '"ok":false,"why":"the divider stayed unusable one step back"'; break; }
            step_back=1
            print -u $menus_fd -- "menus $(( n - 1 ))"
            nap 2.5
        fi
        lab await $report stacked >/dev/null || continue
        key1=$(lab bracket $report)
        listed=$(chevron)
        key2=$(lab bracket $report)
        if [[ $listed == true && -n $key1 && $key1 == $key2 ]]; then
            mark witness "\"ok\":true,\"menus\":$n"
            break
        fi
        (( n == 40 )) && mark witness '"ok":false,"why":"the ladder ended without both witnesses"'
    done
    await $STATUS_LIMIT rest && { nap 15; mark chevronAtRest "\"listed\":$(chevron)"; }
    bring_forward $terminal_pid
}

s_fresh-off() { begin $1 fresh-off 2 false && hide; }
s_fresh-on() { begin $1 fresh-on 2 true && hide; }

placed() { # <round> <scenario> <always-hidden>
    begin $1 $2 2 $3 || return
    hide
    nap 45
    stop_ice
    export_store $dir/store-before-second.json
    report=$dir/report-2.jsonl
    start_ice $ice_app $ice_name $ice_id $report $3 || { abort_run "the second start failed"; return 1; }
    hide
}
s_placed-off() { placed $1 placed-off false; }
s_placed-on() { placed $1 placed-on true; }

front() { # <round> <scenario> <menus>
    begin $1 $2 1 && hide || return
    local since
    start_menus $dir $3 || { abort_run "the menus helper did not start"; return 1; }
    since=$(seq_now)
    if bring_forward $menus_pid; then mark front '"ok":true'; else mark front '"ok":false'; return; fi
    [[ $2 == front-short ]] && hide $since || nap 20
    since=$(seq_now)
    if bring_forward $terminal_pid; then mark back '"ok":true'; else mark back '"ok":false'; return; fi
    [[ $2 == front-short ]] && hide $since || nap 20
}
s_front-short() { front $1 front-short 2; }
s_front-long() { front $1 front-long 24; }

s_relaunch() {
    begin $1 relaunch 2 && hide || return
    stop_ice
    nap 3
    report=$dir/report-2.jsonl
    start_ice $ice_app $ice_name $ice_id $report false || { abort_run "the second start failed"; return 1; }
    hide
}

selfread_frames() { # <helper log> <helper fd> <identifier>: prints the frames' JSON
    local before=$(grep -c '^selfread ' $1) line
    print -u $2 -- selfread
    for _ in {1..20}; do
        (( $(grep -c '^selfread ' $1) > before )) && break
        sleep 0.1
    done
    line=$(grep '^selfread ' $1 | tail -1)
    lab selfread-frames "$line" $3
}

s_positional() {
    local round=$1 id=vz-lab-$run_id-$1positional-p since frames
    begin $round positional 0 || return
    start_helper Target.app $dir/helper-$id.log --items 2 --identifiers $id,$id --glyphs tee,eff --autosave $id \
        || { abort_run "the positional helper did not start"; return 1; }
    helper_pids+=($REPLY_PID)
    helper_fds+=($REPLY_FD)
    remember_domain com.icespike4.target
    print -r -- "{\"scenario\":\"positional\",\"members\":[],\"blockers\":[\"$id\",\"$id\"]}" > $dir/expected.json
    nap 1
    frames=$(selfread_frames $dir/helper-$id.log $helper_fds[1] $id)
    mark frames "\"when\":\"before\",\"frames\":$frames"
    since=$(seq_now)
    await 60 blockers $since 2
    send_ice bar open
    nap 20
    frames=$(selfread_frames $dir/helper-$id.log $helper_fds[1] $id)
    mark frames "\"when\":\"after\",\"frames\":$frames"
}

s_inverted() {
    local round=$1 id=com.icespike4.lab.r$run_id.${1}inverted
    # Pre-seeded before the copy starts: icon far left, divider rightmost (D4, INFERRED).
    remember_domain $id
    defaults write $id "NSStatusItem Preferred Position Ice.ControlItem.Visible" -float 5000
    defaults write $id "NSStatusItem Preferred Position Ice.ControlItem.Hidden" -float 1
    report=$dir/report-1.jsonl
    begin $round inverted 1 || return
    nap 40
    send_ice bar open
    nap 2
}

s_drawn() { begin $1 drawn 1 false hold && await $STATUS_LIMIT status 0 'failed(drawn:'; nap 3; }

s_incomplete() {
    begin $1 incomplete 1 && await $STATUS_LIMIT rest || return
    local log=$run/helper-$1-$ref_ids[1].log before
    before=$(grep -c '^resumed ' $log)
    mark stall
    print -u $ref_fds[1] -- "stall 25"
    for _ in {1..350}; do
        (( $(grep -c '^resumed ' $log) > before )) && break
        sleep 0.1
    done
    mark resumed
    nap 30
    mark settled
}

s_inverted-moved() { expected inverted-moved ""; }

run_scenario() { # <round> <scenario>
    local round=$1 name=$2 verdict
    dir=$run/$round-$name
    report=$dir/report-1.jsonl
    mkdir -m 755 $dir
    : > $dir/steps.jsonl
    # Replaced once the members are known; there from the start, so an early
    # abort is judged with the runner's reason.
    expected $name ""
    note "round $round: $name begins"
    export_store $dir/store-before.json
    s_$name $round
    finish
    export_store $dir/store-after.json
    lab judge $dir > $dir/verdict.json 2> $dir/judge.err
    # A judge that failed is an aborted run, said so, never a missing one.
    [[ -s $dir/verdict.json ]] || print -r -- "{\"scenario\": \"$name\", \"result\": \"aborted\", \"kind\": null, \"clauses\": {}, \"reasons\": [\"the judge failed: see judge.err\"]}" > $dir/verdict.json
    verdict=$(<$dir/verdict.json)
    print -- "  $round $name: ${${verdict#*\"result\": \"}%%\"*}"
    note "round $round: $name: $verdict"
}

# --- the run ---------------------------------------------------------------------------------------

if [[ -n $only ]]; then
    [[ $only == noref ]] || start_references 1 || { print -u2 -- "run-lab: the references did not start"; exit 1; }
    run_scenario 1 $only
    exit 0
fi

for round in {1..$ROUNDS}; do
    print -- "run-lab: round $round of $ROUNDS"
    run_scenario $round noref
    start_references $round || { print -u2 -- "run-lab: the references did not start"; exit 1; }
    for name in ${scenarios:#noref}; do
        run_scenario $round $name
    done
    quit_references
    if ! lab clean $run $round; then
        print -- "run-lab: round $round is not clean; three clean rounds are out of reach, so the run ends here."
        break
    fi
done
exit 0
