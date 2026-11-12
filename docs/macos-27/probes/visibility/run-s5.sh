#!/bin/zsh
# The owner's acceptance sitting (plan 2026-11-12-s5-owner-acceptance): the
# ONE command the owner starts in the owner's own account, in Terminal, in
# front. It starts a lab-identity copy of the staged Ice and one sacrificial
# helper item, waits for Ice to hide the helper, then asks the owner, line by
# line, to look, click and drag, and judges the sitting with s5-tool.py from
# Ice's report and the owner's answers.
#
#   /Users/Shared/IceReverse-lab/run-s5.sh             the sitting, about 16 minutes
#   /Users/Shared/IceReverse-lab/run-s5.sh --dry-run   the guards only; starts nothing
#
# Everything it trusts is in its own directory, written by stage-lab.sh and
# checked against the sha256 in lab.env and s5.env; it sources nothing. Ice's
# own functions here (`stage_ice`, `start_ice`, `stop_ice`, the domain checks)
# are run-lab.sh's, copied: the tested matrix runner is not touched.
#
# Side effects, all in this account: a copy of Ice under
# com.icespike4.lab.r<run id>.s5 and one helper item on the bar for the length
# of the sitting; their defaults domains (deleted and checked empty at the
# end); MenuBarAgent's records of them, and values it stores for the owner's
# items, which changed when helper items appeared on 2026-10-08 (left: the
# store is not ours to write; the difference is recorded and the bar's order
# judged). The release Ice's settings are read twice and never written. The
# script never moves, clicks or presses anything and posts no input event:
# the one item of the owner's that goes into Ice is dragged by the owner.
# Evidence (it holds the owner's app names): ~/IceReverse-evidence/<run id>-s5/.
#
# On every way out (also INT, TERM, HUP, its watchdog) it stops Ice, quits the
# helper, deletes the domains, compares the release's settings and prints the
# verdict.
umask 077
PATH=/usr/bin:/bin:/usr/sbin:/sbin
zmodload zsh/datetime

shared=${0:a:h}
lab_tool=$shared/lab-tool.py
tool=$shared/s5-tool.py
apps=$shared/apps
icewatch=$apps/icewatch
usage="usage: run-s5.sh [--dry-run]"

dry_run=0
case ${1:-} in
    "") ;;
    --dry-run) dry_run=1 ;;
    *) print -u2 -- $usage; exit 64 ;;
esac
(( $# <= 1 )) || { print -u2 -- $usage; exit 64; }

# --- lab.env and s5.env, read as words --------------------------------------------------

HIDE_LIMIT=1100
START_LIMIT=20
TIME_SCALE=1
# A settled first read, and the helper's membership (s5-tool.py's START_LIMIT).
START_WAIT=120
# The owner's own drag: until Ice sees it.
OWNER_WAIT=300
HELPER_LIFETIME=3600
RUN_LIMIT=2400
EVIDENCE_ROOT=$HOME/IceReverse-evidence
RELEASE_DOMAIN=com.jordanbaird.Ice
read_env() { # <file> <strict: 0|1> <known keys...>
    local file=$1 strict=$2 key value
    shift 2
    [[ -r $file ]] || { print -u2 -- "run-s5: $file is missing (stage-lab.sh writes it); stopped."; exit 2; }
    while IFS='=' read -r key value; do
        if (( ! ${@[(Ie)$key]} )); then
            (( strict )) || continue
            print -u2 -- "run-s5: ${file:t} has a line it does not know (${key[1,40]}); stopped."
            exit 2
        fi
        [[ $value =~ '^[A-Za-z0-9._,/-]+$' ]] || { print -u2 -- "run-s5: ${file:t} has a value it does not accept ($key); stopped."; exit 2; }
        typeset -g "$key=$value"
        seen+=($key)
    done < $file
}
seen=()
# lab.env is run-lab.sh's: only what the sitting shares with it is read.
read_env $shared/lab.env 0 OWNER_USER GIT_REV ICE_SHA TARGET_SHA ICEWATCH_SHA TOOL_SHA HIDE_LIMIT START_LIMIT TIME_SCALE
read_env $shared/s5.env 1 S5_SHA S5TOOL_SHA START_WAIT OWNER_WAIT HELPER_LIFETIME RUN_LIMIT EVIDENCE_ROOT RELEASE_DOMAIN
for key in OWNER_USER GIT_REV ICE_SHA TARGET_SHA ICEWATCH_SHA TOOL_SHA S5_SHA S5TOOL_SHA; do
    (( ${seen[(Ie)$key]} )) || { print -u2 -- "run-s5: lab.env or s5.env lacks $key; stopped."; exit 2; }
done
[[ $HIDE_LIMIT == <1-> && $START_LIMIT == <1-> && $START_WAIT == <1-> && $OWNER_WAIT == <1-> && $HELPER_LIFETIME == <1-10800>
    && $RUN_LIMIT == <1-> && $TIME_SCALE =~ '^[0-9]+(\.[0-9]+)?$' && $EVIDENCE_ROOT == /* ]] \
    || { print -u2 -- "run-s5: a value in lab.env or s5.env is out of range; stopped."; exit 2; }

# --- guards -------------------------------------------------------------------------------

guard_failed=0
guard() { print -u2 -- "run-s5: $1"; guard_failed=1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
sha_tree() { # as run-lab.sh's
    (
        cd "$1" || exit 1
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
        find . -type l | LC_ALL=C sort | while read -r link; do print -r -- "$link -> $(readlink "$link")"; done
    ) | shasum -a 256 | cut -d' ' -f1
}

[[ $(id -un) == $OWNER_USER ]] || guard "this account is $(id -un), not $OWNER_USER: the sitting is the owner's"
[[ -d $shared/Ice.app && $(sha_tree $shared/Ice.app) == $ICE_SHA ]] || guard "Ice.app is not the staged bundle"
for name file want in helper $apps/Target.app/Contents/MacOS/vzhelper $TARGET_SHA icewatch $icewatch $ICEWATCH_SHA \
    lab-tool $lab_tool $TOOL_SHA s5-tool $tool $S5TOOL_SHA run-s5 $shared/run-s5.sh $S5_SHA; do
    [[ -f $file && ! -L $file && $(sha $file) == $want ]] || guard "$name is not the staged file"
done
(( guard_failed )) && { print -u2 -- "run-s5: stage again (stage-lab.sh); stopped."; exit 2; }

# Any Ice at all: the release shares nothing with the copy, but two Ices on
# one bar are not what is accepted. Named, never signalled.
running=$(ps -U $(id -u) -o comm= | grep -E '/Ice\.app/Contents/MacOS/|/IceLab[A-Za-z0-9]*$|/vzhelper$' || true)
[[ -z $running ]] || guard "an Ice or a helper is already running; quit it first (Ice's own menu, Quit): ${running//$'\n'/, }"
preflight=$($icewatch preflight 2>/dev/null)
# The system's capture indicator answers to this capture too (run 20261009-234913).
last_capture=$EPOCHREALTIME
[[ $preflight == *'"axTrusted":true'* && $preflight == *'"screenCapture":true'* ]] \
    || guard "Terminal lacks Accessibility or Screen Recording in this account (System Settings > Privacy & Security, for Terminal; not for Ice): ${preflight:-icewatch answered nothing}"
menu_frame=$($icewatch menu-frame 2>/dev/null)
[[ $menu_frame == *'"verdict":"fits"'* ]] || guard "Terminal must be in front (an app with a short menu); icewatch menu-frame: ${menu_frame:-nothing}"
displays=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c 'Resolution:' || true)
(( displays == 1 )) || guard "$displays displays: the sitting is for the built-in display alone"
(( guard_failed )) && exit 2

if (( dry_run )); then
    print -- "run-s5 dry run: the guards pass ($GIT_REV; preflight $preflight)."
    print -- "  It would start a copy of $shared/Ice.app under com.icespike4.lab.r<run id>.s5 and one helper,"
    print -- "  and write its evidence to $EVIDENCE_ROOT/<run id>-s5/."
    print -- "dry run: nothing was started and nothing written."
    exit 0
fi

# --- state and cleanup ------------------------------------------------------------------------

run_id=$(date +%Y%m%d-%H%M%S)
run=$EVIDENCE_ROOT/$run_id-s5
stage=$run/stage
mkdir -p -m 700 $EVIDENCE_ROOT && mkdir -m 700 $run && mkdir -m 700 $stage \
    || { print -u2 -- "run-s5: could not create $run"; exit 2; }
report=$run/report.jsonl
: > $run/domains.txt
: > $run/timeline.txt
: > $run/steps.jsonl
ice_id=com.icespike4.lab.r$run_id.s5
ice_name=IceLab${run_id//[^0-9]/}s5
helper=vz-s5-$run_id
ice_pid=
ice_exec=
ice_fd=
helper_pid=
helper_fd=
watchdog_pid=
caffeinate_pid=
cleaned=0
ended=
cut_at=0

note() { print -r -- "$(date +%H:%M:%S) $*" >> $run/timeline.txt; }
say() { print -r -- "$*"; }
nap() { sleep $(( $1 * TIME_SCALE )); }
still_runs() { [[ $(ps -p $1 -o command= 2>/dev/null) == *$2* ]]; }
s5() { /usr/bin/python3 -I $tool "$@"; }
seq_now() { [[ -f $report ]] && print $(( $(wc -l < $report) )) || print 0; }
mark() { # <step> [raw JSON fields]
    print -r -- "{\"step\":\"$1\",\"seq\":$(seq_now),\"t\":$EPOCHREALTIME${2:+,$2}}" >> $run/steps.jsonl
}

remember_domain() { grep -qxF -- $1 $run/domains.txt || print -r -- $1 >> $run/domains.txt; }
domain_is_empty() {
    local now result=1
    now=$(mktemp -t s5prefs) || return 1
    defaults export $1 $now 2>/dev/null && [[ $(plutil -p $now) == $'{\n}' ]] && result=0
    rm -f $now
    return $result
}
delete_domains() { # returns 1 when one could not be emptied
    local domain result=0
    for domain in ${(f)"$(<$run/domains.txt)"}; do
        defaults delete $domain >/dev/null 2>&1
        domain_is_empty $domain || { print -u2 -- "run-s5: $domain STILL HAS DEFAULTS; delete it by hand: defaults delete $domain"; result=1; }
    done
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

quit_helper() {
    [[ -n $helper_fd ]] && { exec {helper_fd}>&-; helper_fd=; }
    [[ -n $helper_pid ]] || return 0
    for _ in {1..15}; do still_runs $helper_pid /vzhelper || break; sleep 0.2; done
    still_runs $helper_pid /vzhelper && kill -TERM $helper_pid 2>/dev/null
    helper_pid=
}

# The release Ice's settings, in a form two reads can be compared in.
export_prefs() { # <file>
    defaults export $RELEASE_DOMAIN $1 2>/dev/null && plutil -convert xml1 $1 2>/dev/null
}

store="$HOME/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar"
export_store() { # <file>
    defaults export "$store" - 2>/dev/null | plutil -convert json -o "$1" - 2>/dev/null || print -r -- '{"unreadable":true}' > $1
}
# Read until two reads a second apart agree (store-lib.zsh's settled_store).
settled_store() { # <file>
    local tries=0
    export_store $1.previous
    while (( tries++ < 10 )); do
        sleep 1
        export_store $1
        cmp -s $1.previous $1 && break
        mv -f -- $1 $1.previous
    done
    [[ -f $1 ]] || mv -f -- $1.previous $1
    rm -f -- $1.previous
}

cleanup() { # <why the sitting was cut short, or nothing>
    (( cleaned )) && return
    cleaned=1
    trap '' INT TERM HUP QUIT
    local why=$1 ice_ok=true domain_ok=true prefs_ok=true difference code
    [[ -n $watchdog_pid ]] && kill $watchdog_pid 2>/dev/null
    [[ -n $why ]] && mark aborted "\"why\":\"$why\""
    mark stopping
    stop_ice || ice_ok=false
    quit_helper
    delete_domains || domain_ok=false
    rm -rf -- $stage
    [[ -n $caffeinate_pid ]] && kill $caffeinate_pid 2>/dev/null
    export_prefs $run/prefs-after.plist && cmp -s $run/prefs-before.plist $run/prefs-after.plist || prefs_ok=false
    settled_store $run/store-after.json
    difference=$(s5 store-diff $run/store-before.json $run/store-after.json $helper $ice_id $ice_name)
    [[ $difference == \{*\} ]] || difference='{"unreadable":true}'
    mark cleanup "\"ice\":$ice_ok,\"domain\":$domain_ok,\"prefsUnchanged\":$prefs_ok,\"store\":$difference"
    note "cleanup: ice $ice_ok domain $domain_ok prefs $prefs_ok"
    s5 verdict $run > $run/verdict.json
    code=$?
    print
    {
        print -- "==== S5 $run_id ($GIT_REV) ===="
        s5 summary $run/verdict.json
        [[ $prefs_ok == true ]] || print -- "  正式版 Ice 的設定變了。還原：defaults import $RELEASE_DOMAIN $run/prefs-before.plist"
        print -- "記錄在：$run"
    } | tee $run/report.txt
    exit $code
}

trap 'cleanup interrupted' INT
trap 'cleanup terminated' TERM
trap 'cleanup "the terminal closed"' HUP
trap 'cleanup quit' QUIT
trap 'cleanup "$ended"' EXIT
# Gives up without a signal if this script is already gone (its pid may be reused).
perl -e 'sleep $ARGV[0]; kill "TERM", $ARGV[1] if getppid() == $ARGV[1]' $RUN_LIMIT $$ < /dev/null &
watchdog_pid=$!
caffeinate -dis -w $$ < /dev/null &
caffeinate_pid=$!
note "run $run_id rev $GIT_REV preflight $preflight"
export_prefs $run/prefs-before.plist || { ended="the release Ice's settings could not be read"; exit 2; }
export_store $run/store-before.json

# --- Ice and the helper (run-lab.sh's, for one copy and one member) ---------------------------------

stage_ice() { # -> path
    local app=$stage/Ice.app
    ditto -- $shared/Ice.app $app || return 1
    chmod -R u+w $app || return 1
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ice_id" $app/Contents/Info.plist || return 1
    mv -- $app/Contents/MacOS/Ice $app/Contents/MacOS/$ice_name || return 1
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $ice_name" $app/Contents/Info.plist || return 1
    codesign --force --deep --sign - $app 2> $run/codesign.log || return 1
    codesign --verify --deep --strict $app 2>> $run/codesign.log || return 1
    print -r -- $app
}

start_ice() { # <app>
    local fifo=$run/.ice-fifo-$RANDOM fd
    remember_domain $ice_id
    defaults write $ice_id UseIceBar -bool true
    defaults write $ice_id ShowOnHover -bool false
    defaults write $ice_id ShowOnScroll -bool false
    defaults write $ice_id EnableAlwaysHiddenSection -bool false
    mkfifo $fifo || return 1
    : > $report
    OS_ACTIVITY_DT_MODE=YES $1/Contents/MacOS/$ice_name -IceLabReport YES -SUEnableAutomaticChecks NO -SUAutomaticallyUpdate NO \
        < $fifo > $report 2> $run/report.log &
    ice_pid=$!
    ice_exec=$1/Contents/MacOS/$ice_name
    exec {fd}> $fifo
    rm -f $fifo
    ice_fd=$fd
    note "Ice $ice_id started, pid $ice_pid"
    s5 wait $report $START_LIMIT $ice_pid started
}

# The helper's stdin is a FIFO this script holds open: its EOF is the helper's quit.
start_helper() {
    local fifo=$run/.fifo-$RANDOM fd log=$run/helper.log
    remember_domain com.icespike4.target
    mkfifo $fifo || return 1
    $apps/Target.app/Contents/MacOS/vzhelper --controller $$ --items 1 --identifiers $helper --glyphs target --autosave $helper --menu \
        --lifetime $HELPER_LIFETIME < $fifo > $log 2>&1 &
    helper_pid=$!
    exec {fd}> $fifo
    rm -f $fifo
    helper_fd=$fd
    for _ in {1..50}; do grep -q '^up ' $log && { note "helper $helper up"; return 0; }; sleep 0.2; done
    return 1
}

# CaptureBurstParameters.standard.clearAfter (IceCore): Ice is not started
# within it of a capture of the runner's own.
CLEAR_AFTER=22
cool_down() {
    local left=$(( CLEAR_AFTER - (EPOCHREALTIME - last_capture) ))
    (( left > 0 )) && nap $left
    return 0
}

# --- the sitting ----------------------------------------------------------------------------------

# Waits for a predicate on the report. 0 held; 1 not in time; 2 the sitting
# cannot go on (`ended` says why).
await() { # <seconds> <predicate> [args...]
    local seconds=$(( $1 * TIME_SCALE )) code
    shift
    s5 wait $report $seconds ${ice_pid:-0} "$@"
    code=$?
    case $code in
        0|1) return $code ;;
        3) ended="the report is damaged"; return 2 ;;
        *) ended="Ice ended"; return 2 ;;
    esac
}

# Asks until the answer is y, n or s; records it. 2 when there is no more input.
ask() { # <question id> <text>
    local reply
    while true; do
        print -n -- "$2 [y 是 / n 否 / s 跳過] "
        read -r reply || { print; ended="no answer to $1 (the input ended)"; return 2; }
        case $reply in
            y|Y) reply=y ;;
            n|N) reply=n ;;
            s|S) reply=s ;;
            *) say "  請輸入 y、n 或 s。"; continue ;;
        esac
        break
    done
    # The answer's cut of the report, taken once: what the sitting waits for
    # next is waited for after this very line, and judged after it.
    cut_at=$(seq_now)
    print -r -- "{\"step\":\"answer\",\"seq\":$cut_at,\"t\":$EPOCHREALTIME,\"q\":\"$1\",\"a\":\"$reply\"}" >> $run/steps.jsonl
    REPLY=$reply
}

minutes() { print $(( ($1 + 59) / 60 )); }

# 0 done; 1 Ice did not get there in time; 2 the sitting cannot go on.
own_item() {
    local cut=$cut_at found name
    say "  按住 Command，把你選的「一個」圖標拖到 Ice 分隔線的左邊，然後放開。"
    say "  我在等 Ice 看到它（最多 $(minutes $OWNER_WAIT) 分鐘）……"
    await $OWNER_WAIT members $cut 2 || { (( $? == 2 )) && return 2; say "  沒等到：Ice 沒有看到新的圖標。"; return 1; }
    found=$(s5 new-member $report $cut $helper)
    cut=$(seq_now)
    mark ownSeen "\"member\":${found:-null}"
    say "  Ice 看到了。現在等它藏好並驗證（最多 $(minutes $HIDE_LIMIT) 分鐘），這段時間請不要動……"
    await $HIDE_LIMIT verified $cut || { (( $? == 2 )) && return 2; say "  沒等到 verified。"; return 1; }
    nap 3
    print -n -- "  這是哪個圖標？打個名字方便記錄（直接按 Return 也行）："
    read -r name || { print; ended="no name (the input ended)"; return 2; }
    mark ownName "\"name\":\"${name//[^[:alnum:] ._-]/}\""
    ask ownListed "  點一下 Ice 圖標。你的圖標有沒有出現在彈出的小條裡？" || return 2
    ask ownMenu "  在小條裡點你的圖標。它的選單有沒有打開？" || return 2
}

icon_drag() {
    local cut=$cut_at
    say "  右鍵點 Ice 圖標，選「Ice Settings…」，打開「Menu Bar Layout」那一頁，視窗留著。"
    say "  然後按住 Command，把 Ice 圖標拖到它的分隔線左邊，放開。"
    say "  我在等 Ice 發現（最多 $(minutes $OWNER_WAIT) 分鐘）……"
    await $OWNER_WAIT status $cut 'blocked(iconLeftOfDivider' || { (( $? == 2 )) && return 2; say "  沒等到：Ice 沒有說圖標放錯了。"; return 1; }
    ask paneSays "  設定視窗裡有沒有出現一行提醒，說 Ice 圖標要在分隔線右邊？" || return 2
    cut=$cut_at
    say "  現在按住 Command，把 Ice 圖標拖回分隔線右邊。等它重新藏好（最多 $(minutes $HIDE_LIMIT) 分鐘）……"
    await $HIDE_LIMIT verified $cut || { (( $? == 2 )) && return 2; say "  沒等到 verified。"; return 1; }
    ask paneClear "  那行提醒消失了嗎？" || return 2
}

# 0 when the sitting ran to where it could; 2 when it was cut short (`ended`).
sitting() {
    local app cut did_own=0
    say "==== S5：在你自己的菜單欄上驗收 ($GIT_REV) ===="
    say "會發生的事：一份測試用的 Ice 和一個假圖標會出現在菜單欄上，結束時都會消失。"
    say "正式版 Ice 的設定不會被動到。你的圖標排列順序有可能變，結束時我會檢查並告訴你。"
    say "前 $(minutes $(( HIDE_LIMIT / 3 ))) 分鐘左右請讓 Terminal 留在最前面，不要動電腦；之後照提示做。隨時可按 Control-C 結束。"
    print -n -- "按 Return 開始："
    read -r || { print; ended="not started (the input ended)"; return 2; }
    cool_down
    app=$(stage_ice) || { ended="staging the copy failed ($run/codesign.log)"; return 2; }
    start_ice $app || { ended="Ice did not start ($run/report.log)"; return 2; }
    mark iceStarted
    say "Ice 啟動了，等它讀完菜單欄……"
    await $START_WAIT settled || (( $? == 1 )) || return 2
    if ! s5 check-start $report > $run/start.txt; then
        say "沒法開始，Ice 一啟動的狀態不對："
        cat $run/start.txt
        return 0
    fi
    nap 2
    cut=$(seq_now)
    start_helper || { ended="the helper did not start ($run/helper.log)"; return 2; }
    # The cut from before the helper's start: what the wait below and the judge both count from.
    print -r -- "{\"step\":\"helperUp\",\"seq\":$cut,\"t\":$EPOCHREALTIME,\"id\":\"$helper\"}" >> $run/steps.jsonl
    await $START_WAIT members $cut 1 || (( $? == 1 )) || return 2
    if ! s5 check-helper $report $cut $helper > $run/helper.txt; then
        mark chevron "\"listed\":$([[ $($icewatch chevron 2>/dev/null) == *'"listed":true'* ]] && print true || print false)"
        say "沒法開始，假圖標沒有成為 Ice 裡唯一的成員："
        cat $run/helper.txt
        return 0
    fi
    say "假圖標進了 Ice。等它藏好並驗證，通常 5 分鐘左右（最多 $(minutes $HIDE_LIMIT) 分鐘）。請不要動電腦……"
    await $HIDE_LIMIT verified $cut || { (( $? == 2 )) && return 2; say "沒等到 verified，到此為止。"; return 0; }
    nap 3
    say ""
    say "好了，假圖標已經藏進 Ice。接下來請照做並回答。"
    say "第 1 步"
    ask helperListed "  點一下 Ice 圖標。彈出的小條裡有沒有一個圖標（那個假圖標）？" || return 2
    ask helperMenu "  在小條裡點那個圖標。它的選單有沒有打開？" || return 2
    say "第 2 步：把你自己的一個圖標放進 Ice。"
    ask doOwn "  要做這一步嗎？" || return 2
    if [[ $REPLY == y ]]; then
        did_own=1
        own_item
        (( $? == 2 )) && return 2
    fi
    say "第 3 步：把 Ice 圖標放到錯的位置，看它會不會提醒。"
    ask doInvert "  要做這一步嗎？" || return 2
    if [[ $REPLY == y ]]; then
        icon_drag
        (( $? == 2 )) && return 2
    fi
    if (( did_own )); then
        say "第 4 步：按住 Command，把你剛才放進去的圖標拖回原來的位置。"
        ask itemBack "  它回到原位了嗎？" || return 2
    fi
    say "最後檢查一次你的圖標順序……"
    await 60 fresh $cut_at || (( $? == 1 )) || return 2
    return 0
}

sitting || true
exit 0
