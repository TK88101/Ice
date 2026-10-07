#!/bin/zsh -f
# IceBar build plan T7 (docs/plans/2026-10-03-icebar-build.md section 10.3): the
# ONE command the owner runs, in the isolated account's Terminal, at the time
# the owner named. It starts the staged Ice and the sacrificial helpers, walks
# the checklist of section 10.5 with the owner, and on every exit path stops
# them, restores Ice's preferences and prints the report.
#
#   /Users/Shared/IceReverse-t7/run-t7.sh               the smoke pass, then the checklist
#   /Users/Shared/IceReverse-t7/run-t7.sh --smoke       the smoke pass only: no question
#   /Users/Shared/IceReverse-t7/run-t7.sh --phase 1|2|3|4   one checklist phase, no smoke pass
#   /Users/Shared/IceReverse-t7/run-t7.sh --dry-run     starts neither Ice nor a helper
#
# The smoke pass (plan 2026-10-07-icebar-menu-frame-fix, section 11): phases
# 1-3 up to Ice's `active` with nobody typing, each recorded, so that a sitting
# is not spent on a run that cannot hide.
#
# Everything it trusts is in its own directory, written by stage-t7.sh: no
# environment variable changes what it does.
set -uo pipefail
umask 022
# The tools it calls come from the system, not from this account's PATH.
PATH=/usr/bin:/bin:/usr/sbin:/sbin

shared=${0:a:h}
ice=$shared/Ice.app/Contents/MacOS/Ice
ice_arguments=(-SUEnableAutomaticChecks NO -SUAutomaticallyUpdate NO)
# Section 10.1 A5: written to an empty domain, so everything else is Ice's default.
settings=(UseIceBar true ShowOnHover false ShowOnScroll false EnableAlwaysHiddenSection false)
phase_members=(1 2 4 2)
member_glyphs=(hidden2 hidden3 hidden4 ell)
new_item_glyph=gamma
helper_lifetime=1800
run_limit=9000
start_timeout=20
long_menus=24
# F3: how long a helper's `selfread` reply may take. F2b: how long the owner
# watches for an IceBar after the click.
selfread_wait=2
click_watch=3
# Section 11, G1: Ice's baseline needs a reference, an identifiable item
# between its hidden divider and its icon. Two helpers for that, started
# before Ice with a preferred position between Ice's icon (0) and divider (1).
reference_glyphs=(reference alt)
reference_positions=(0.4 0.6)
reference_polls=6
reference_tries=3
smoke_phases=(1 2 3)
usage="usage: run-t7.sh [--dry-run] [--smoke] [--phase 1|2|3|4]"

dry_run=0
smoke=1
checklist=1
phases=(1 2 3 4)
while (( $# )); do
    case $1 in
        --dry-run) dry_run=1 ;;
        --smoke) checklist=0 ;;
        --phase)
            [[ ${2:-} == [1-4] ]] || { print -u2 -- $usage; exit 64; }
            phases=($2)
            smoke=0
            shift ;;
        *) print -u2 -- $usage; exit 64 ;;
    esac
    shift
done

# --- guards (section 10.3 step 1) ------------------------------------------------

guard_failed=0
guard() { # <enforced in a dry run: 0|1> <message>
    if (( dry_run )) && (( ! $1 )); then
        print -- "（dry-run 僅回報）$2"
    else
        print -u2 -- "run-t7: $2"
        guard_failed=1
    fi
}

# t7.env is read as words, never sourced: nothing from the staging runs before
# the checks below have passed.
BACKUP_ROOT=$HOME/IceReverse-t7-backup
NEW_ITEM_DELAY=3
# Plan 2026-10-07-icebar-menu-frame-fix F2: how long a phase waits for Ice's
# first `active` (T0: a full sweep took about 2.7 min), and how long a status
# that stops hiding must stay the latest before the phase is given up.
STATUS_LIMIT=300
BLOCKING_GRACE=10
# Section 11: a capture of the bar strip only, before and after each phase's
# `active`; 0 in test-t7.sh, which must not capture the tester's bar.
CAPTURE=1
required=(EXPECT_USER OWNER_USER GIT_REV DOMAIN HELPER_DOMAINS ICE_SHA TARGET_SHA MENUS_SHA ICEWATCH_SHA)
optional=(BACKUP_ROOT NEW_ITEM_DELAY STATUS_LIMIT BLOCKING_GRACE CAPTURE)
allowed=($required $optional)
seen=()
while IFS='=' read -r key value; do
    if (( ! ${allowed[(Ie)$key]} )) || [[ ! $value =~ '^[A-Za-z0-9._,/-]+$' ]]; then
        print -u2 -- "run-t7: t7.env 有無法辨識的一行（${key[1,40]}），停止。"
        exit 2
    fi
    typeset -g "$key=$value"
    seen+=($key)
done < $shared/t7.env
for key in $required; do
    (( ${seen[(Ie)$key]} )) || { print -u2 -- "run-t7: t7.env 缺少 $key，停止。"; exit 2; }
done
domain=$DOMAIN
[[ $STATUS_LIMIT == <1-> && $BLOCKING_GRACE == <-> && $CAPTURE == [01] ]] || { print -u2 -- "run-t7: t7.env 的 STATUS_LIMIT/BLOCKING_GRACE/CAPTURE 不合規，停止。"; exit 2; }
helper_domains=(${(s:,:)HELPER_DOMAINS})
backup_root=$BACKUP_ROOT

[[ $(id -un) == $EXPECT_USER ]] || guard 0 "這個帳號是 $(id -un)，不是 $EXPECT_USER"
for file in $shared $shared/t7.env $shared/t7-lib.zsh $shared/run-t7.sh $shared/Ice.app $ice \
    $shared/apps/Target.app/Contents/MacOS/vzhelper $shared/apps/Menus.app/Contents/MacOS/vzhelper $shared/apps/icewatch; do
    # Someone else's file or a link is refused in a dry run too: the owner's
    # dry run must not run another account's code.
    [[ ! -L $file && $(stat -f %Su $file 2>/dev/null) == $OWNER_USER ]] || guard 1 "$file 不是 $OWNER_USER 的檔案"
    [[ ! -w $file ]] || guard 0 "這個帳號可以改寫 $file"
done
(( guard_failed )) && exit 2

source $shared/t7-lib.zsh
running=$(t7_count_ours -U $(id -u))
(( running == 0 )) || guard 0 "這個帳號裡已有 $running 個 Ice 或 vzhelper 在執行"
t7_check_staged $shared || guard 1 "staging 的檔案與 t7.env 記錄的 sha256 不符"
preflight=$($shared/apps/icewatch preflight 2>/dev/null)
t7_preflight_ok "$preflight" || guard 1 "Terminal 缺少「輔助使用」或「螢幕與系統錄音」權限：$preflight"
# Plan 2026-10-07 F4: Ice's own reader, with this Terminal in front. Without a
# menu frame Ice never hides (run 20261007-012252-t7).
menu_frame=$($shared/apps/icewatch menu-frame 2>/dev/null)
t7_menu_frame_ok "$menu_frame" || guard 1 "Ice 讀不到 app 選單的寬度（icewatch menu-frame：${menu_frame:-沒有輸出}）；這樣 Ice 不會隱藏，所以不開始"
(( guard_failed )) && exit 2
display_width=$(t7_json_get "$menu_frame" displayWidth)
bar_height=$(t7_json_get "$menu_frame" barHeight)

if (( dry_run )); then
    print -- "run-t7 dry-run：檢查通過（$GIT_REV；preflight $preflight；menu-frame $menu_frame）。正式執行會做："
    print -- "  1. 匯出 $domain 到 $backup_root/<run id>/prefs-before.plist，清空後寫入：$settings"
    print -- "  1b. 啟動 ${#reference_glyphs} 個參照 helper（$shared/apps/Target.app/Contents/MacOS/vzhelper … --autosave vz-t7-ref<n> --lifetime $run_limit），偏好位置寫入 $helper_domains[1]"
    print -- "  2. 啟動 OS_ACTIVITY_DT_MODE=YES OS_ACTIVITY_MODE=debug $ice $ice_arguments"
    print -- "  2b. $shared/apps/icewatch references：確認 Ice 的分隔線與圖示之間有參照圖示"
    (( smoke )) && print -- "  自動檢查（不問問題）：階段 $smoke_phases 各自等到 active"
    for phase in $phases; do
        print -- "  階段 $phase：${phase_members[phase]} 個 helper（$shared/apps/Target.app/Contents/MacOS/vzhelper --controller <pid> --items 1 --identifiers vz-t7-<glyph> --glyphs <glyph> --menu --lifetime $helper_lifetime）"
    done
    print -- "  階段 4 另啟動 $shared/apps/Menus.app/Contents/MacOS/vzhelper --role menus，並送出 menus $long_menus"
    print -- "  結束或中止：結束 Ice 與 helper、還原 $domain、刪除 $helper_domains、印出報告"
    print -- "dry-run：沒有啟動 Ice 或任何 helper，沒有寫入任何設定。"
    exit 0
fi

# --- state and cleanup (step 3) ---------------------------------------------------

run_id=$(date +%Y%m%d-%H%M%S)-t7
run=$shared/evidence/$run_id
backup=$backup_root/$run_id
ice_pid=
tail_pid=
watchdog_pid=
restore_armed=0
cleaned=0
helper_fds=()
helper_pids=()
# The reference helpers live for the whole run, not for a phase.
reference_fds=()
reference_pids=()
references_line=
references_inverted=0
# What the current phase's records are filed under: its number, or s<number>
# in the smoke pass.
label=0
current_phase=0
in_smoke=0
phase_stopped=0
# The current phase's members, for the placement snapshots (plan F3).
member_fds=()
member_ids=()
member_names=()
member_x=()
typeset -A phase_from phase_to phase_done

note() { print -r -- "$(date +%H:%M:%S) $*" >> $run/timeline.txt; }
log_lines() { wc -l < $run/ice.log | tr -d ' '; }
# A pid is signalled only while it is still the program this script started.
still_runs() { # <pid> <executable path>
    [[ $(ps -p $1 -o command= 2>/dev/null) == *$2* ]]
}

delete_helper_domains() {
    local helper_domain
    for helper_domain in $helper_domains; do defaults delete $helper_domain >/dev/null 2>&1; done
}

close_helpers() {
    local fd pid
    for fd in $helper_fds; do exec {fd}>&-; done
    for pid in $helper_pids; do
        for _ in {1..15}; do still_runs $pid /vzhelper || break; sleep 0.2; done
        still_runs $pid /vzhelper && kill -TERM $pid 2>/dev/null
    done
    helper_fds=()
    helper_pids=()
    member_fds=()
    member_ids=()
    member_names=()
    member_x=()
}

# Returns 1 when Ice is still there afterwards.
stop_ice() {
    [[ -n $ice_pid ]] || return 0
    still_runs $ice_pid $ice && kill -TERM $ice_pid 2>/dev/null
    for _ in {1..25}; do still_runs $ice_pid $ice || break; sleep 0.2; done
    still_runs $ice_pid $ice && kill -KILL $ice_pid 2>/dev/null
    for _ in {1..10}; do still_runs $ice_pid $ice || break; sleep 0.2; done
    if still_runs $ice_pid $ice; then
        note "Ice is still running"
        return 1
    fi
    note "Ice stopped"
}

report() { # <restore verdict>
    local phase helper_domain state=empty
    print -- "==== T7 回報 ===="
    print -- "run $run_id（$GIT_REV）"
    [[ -f $run/stops.txt ]] && awk 'index($0, "p0 ") == 1 { print "本輪無效：" substr($0, 4) }' $run/stops.txt
    [[ -n $references_line ]] && print -r -- "參照檢查：$references_line"
    for phase in ${(on)${(k)phase_from}}; do
        if [[ $phase == s* ]]; then
            print -- "-- 自動檢查 $phase（k = ${phase_members[${phase#s}]}）${${phase_done[$phase]:-未完成}:#1}"
        else
            print -- "-- 階段 $phase（k = ${phase_members[phase]}）${${phase_done[$phase]:-未完成}:#1}"
        fi
        [[ -f $run/answers.txt ]] && awk -F'\t' -v prefix="p$phase." 'index($2, prefix) == 1 { print "  你的回答 " $2 " = " $3 }' $run/answers.txt
        [[ -f $run/stops.txt ]] && awk -v prefix="p$phase " 'index($0, prefix) == 1 { print "  本輪無效：" substr($0, length(prefix) + 1) }' $run/stops.txt
        [[ -f $run/placement.txt ]] && awk -v prefix="p$phase " 'index($0, prefix) == 1 { print "  " substr($0, length(prefix) + 1) }' $run/placement.txt
        sed -n "${phase_from[$phase]},${phase_to[$phase]:-\$}p" $run/ice.log | t7_summary | sed 's/^/  /'
        print -- "  helper 選單開啟 $(cat $run/helper-p$phase-*.log(N) /dev/null | grep -c '"event":"open"') 次"
    done
    for helper_domain in $helper_domains; do
        t7_domain_is_empty $helper_domain || state="$helper_domain 仍有內容"
    done
    print -- "偏好還原：$1"
    print -- "helper 設定：$state"
    print -- "==== 結束 ===="
}

cleanup() {
    (( cleaned )) && return
    cleaned=1
    # Nothing interrupts the restore, whichever way cleanup was reached.
    trap '' INT TERM HUP QUIT
    local restore="未變更" ice_gone=1
    [[ -n $watchdog_pid ]] && kill $watchdog_pid 2>/dev/null
    stop_ice || ice_gone=0
    helper_fds+=($reference_fds)
    helper_pids+=($reference_pids)
    close_helpers
    [[ -n $tail_pid ]] && kill $tail_pid 2>/dev/null
    if (( restore_armed )); then
        local manual="備份在 $backup/prefs-before.plist，請執行：defaults delete $domain; defaults import $domain $backup/prefs-before.plist"
        if (( ! ice_gone )); then
            # A running Ice writes its settings back.
            restore="FAILED（Ice 還在執行，pid $ice_pid）；先結束它，$manual"
        elif t7_prefs_restore $domain $backup/prefs-before.plist; then
            restore=verified
        else
            restore="FAILED；$manual"
        fi
    fi
    delete_helper_domains
    note "cleanup: $restore"
    print
    report $restore | tee $run/report.txt
}

finish() { # <exit code>
    cleanup
    exit $1
}

mkdir $run || { print -u2 -- "run-t7: 無法建立 $run"; exit 2; }
mkdir -p $backup_root && mkdir -m 700 $backup || { print -u2 -- "run-t7: 無法建立 $backup"; exit 2; }
trap 'finish 130' INT
trap 'finish 143' TERM
trap 'finish 129' HUP
trap 'finish 131' QUIT
# A backstop for any other way out; `cleaned` makes it run once.
trap cleanup EXIT
# Gives up without a signal if this script is already gone (its pid may be reused).
perl -e 'sleep $ARGV[0]; kill "TERM", $ARGV[1] if getppid() == $ARGV[1]' $run_limit $$ &
watchdog_pid=$!
note "run $run_id rev $GIT_REV preflight $preflight"

# --- preferences (step 3) ----------------------------------------------------------

t7_prefs_export $domain $backup/prefs-before.plist || { print -u2 -- "run-t7: 無法匯出 $domain"; finish 1; }
restore_armed=1
print -- "Ice 偏好已匯出。手動還原（只有腳本沒印出「偏好還原：verified」時才需要）："
print -- "  defaults delete $domain; defaults import $domain $backup/prefs-before.plist"
defaults delete $domain >/dev/null 2>&1
for key value in $settings; do
    want=0
    [[ $value == true ]] && want=1
    defaults write $domain $key -bool $value
    [[ $(defaults read $domain $key 2>/dev/null) == $want ]] || { print -u2 -- "run-t7: $key 寫入後讀回不符"; finish 1; }
done
note "settings written: $settings"

# --- reference helpers, before Ice (section 11, G1) -----------------------------------------

# The helper's stdin stays open in this script (EOF is its quit); the newest
# one's descriptor is $helper_fds[-1].
launch_helper() { # <app> <log> <vzhelper arguments...>
    local app=$1 log=$2 fifo=$run/.fifo-$RANDOM fd
    shift 2
    mkfifo $fifo || { print -- "（無法建立 $fifo，helper $app 沒有啟動）"; return 1; }
    $shared/apps/$app/Contents/MacOS/vzhelper --controller $$ "$@" --lifetime ${launch_lifetime:-$helper_lifetime} < $fifo > $log 2>&1 &
    helper_pids+=($!)
    exec {fd}> $fifo
    rm -f $fifo
    helper_fds+=($fd)
    for _ in {1..50}; do grep -q '^up ' $log && return 0; sleep 0.2; done
    print -- "（helper $app 沒有回報啟動，見 $log）"
    return 1
}

# Before Ice, so that Ice's own items arrive on a bar that already has them;
# each with a preferred position between Ice's icon (0) and its hidden divider
# (1). Whether macOS honours that is checked by reference_gate, not assumed.
launch_references() {
    local i id launch_lifetime=$run_limit
    delete_helper_domains
    for i in {1..${#reference_glyphs}}; do
        id=vz-t7-ref$i
        defaults write $helper_domains[1] "NSStatusItem Preferred Position $id" -float $reference_positions[i]
        launch_helper Target.app $run/helper-ref-$i.log --items 1 --identifiers $id --glyphs $reference_glyphs[i] --autosave $id || return 1
        reference_fds+=($helper_fds[-1])
        reference_pids+=($helper_pids[-1])
        helper_fds[-1]=()
        helper_pids[-1]=()
        note "reference $i ($id) launched"
    done
}

if ! launch_references; then
    print -- "參照 helper 沒有啟動，本輪無效"
    print -r -- "p0 參照 helper 沒有啟動" >> $run/stops.txt
    finish 3
fi

# --- Ice (step 4) --------------------------------------------------------------------

: > $run/ice.log
OS_ACTIVITY_DT_MODE=YES OS_ACTIVITY_MODE=debug $ice $ice_arguments > $run/ice.out 2> $run/ice.log &
ice_pid=$!
note "Ice started pid $ice_pid"
started=0
for _ in {1..$((start_timeout * 5))}; do
    grep -q -E 'Passed (all|required) permissions checks' $run/ice.log && { started=1; break; }
    grep -q 'Failed required permissions checks' $run/ice.log && break
    kill -0 $ice_pid 2>/dev/null || break
    sleep 0.2
done
if (( ! started )); then
    print -u2 -- "run-t7: Ice 沒有通過權限檢查或沒有啟動（不要按 Ice 視窗裡的 Grant）。"
    finish 1
fi
print -- "Ice 已啟動（權限檢查通過）。以下 [Ice] 開頭的行是 Ice 自己的狀態。"
( exec tail -n +1 -F $run/ice.log 2>/dev/null ) > >(awk '/\[IceBar(Hiding|Press)\]/ { text = $0; sub(/^[^\]]*\] \[[^\]]*\] /, "", text); print "  [Ice " substr($2, 1, 8) "] " text; fflush() }') &
tail_pid=$!

# --- helpers and questions (step 5) ----------------------------------------------------

# Launches a member and records where its item is at once, before Ice's quiet
# period (3 s after the layout changes) lets a trial move it. Returns 1 when it
# did not start, 2 when it is not on the bar (plan F3: the phase cannot be judged).
launch_member() { # <index> <glyph>
    local log=$run/helper-p$label-$1.log rc
    launch_helper Target.app $log --items 1 --identifiers vz-t7-$2 --glyphs $2 --menu || return 1
    note "phase $label member $1 ($2) launched"
    member_fds+=($helper_fds[-1])
    member_ids+=(vz-t7-$2)
    member_names+=($1)
    snapshot_member ${#member_fds} 啟動後
    rc=$?
    if (( rc == 2 )); then
        sleep $selfread_wait
        snapshot_member ${#member_fds} 啟動後
        rc=$?
    fi
    (( rc == 0 )) || return 2
}

# Asks one member's helper where its item is and writes one placement line.
# Returns t7_placement's 0 (on the bar), 1 (off) or 2 (unknown).
snapshot_member() { # <member index> <label>
    local i=$1 before line place rc
    local log=$run/helper-p$label-$member_names[i].log
    before=$(grep -c '^selfread ' $log)
    print -u $member_fds[i] -- selfread
    for _ in {1..$((selfread_wait * 5))}; do
        if (( $(grep -c '^selfread ' $log) > before )); then
            line=$(grep '^selfread ' $log | tail -1)
            break
        fi
        sleep 0.2
    done
    if [[ -z ${line:-} ]]; then
        place="unknown $selfread_wait 秒內沒有回覆"
        rc=2
    else
        place=$(t7_placement "${line#selfread }" $member_ids[i] $display_width $bar_height)
        rc=$?
    fi
    case $rc in
        0) member_x[i]=${place#on }; place="x=${place#on } 在列上" ;;
        1) place="不在列上（${place#off }）" ;;
        *) place="unknown（${place#unknown }）" ;;
    esac
    print -r -- "p$label helper p$label-$member_names[i] $2 $place" >> $run/placement.txt
    return $rc
}

# The phase cannot be judged: say why and record it. The checklist ends the
# run there (status 3); the smoke pass goes on to the next phase, so one
# sitting shows every k. Callers return after it.
stop_phase() { # <reason>
    print -- "$1，本輪無效"
    print -r -- "p$label $1" >> $run/stops.txt
    note "phase $label stopped: $1"
    check_references "$label stopped"
    capture_bar stopped
    phase_stopped=1
    (( in_smoke )) || finish 3
}

# Waits for Ice's first `active` of this phase (plan F2). A status that stops
# hiding and is still the latest after the grace, no `active` within the limit,
# or Ice ending stops the run.
wait_for_phase_status() {
    local started=$SECONDS blocked_since= latest
    print -- "【看終端】等 Ice 校準：等到上面出現 [Ice …] IceBar hiding: active（最多 $STATUS_LIMIT 秒，期間選單列上的 helper 圖示會閃）。不用輸入。"
    while true; do
        kill -0 $ice_pid 2>/dev/null || { print -- "Ice 已經結束，中止。"; finish 1; }
        # Any `active` since the phase began counts: Ice may have moved on
        # (a long menu, a quiet period) before this loop looked.
        t7_log_has $run/ice.log ${phase_from[$label]} "${t7_ice_status_prefix}active\$" && return 0
        latest=$(t7_latest_status $run/ice.log ${phase_from[$label]})
        # `noMembers` is also Ice's normal first status, before it has seen
        # the helpers: like the others it stops the phase only if it stays.
        if [[ $latest == shown:(menuUnreadable|cannotAssess|noCleanLength|noMembers|unstableLayout) ]]; then
            [[ -n $blocked_since ]] || blocked_since=$SECONDS
            if (( SECONDS - blocked_since >= BLOCKING_GRACE )); then
                stop_phase "Ice 沒有在隱藏（原因：${latest#shown:}）"
                return 1
            fi
        else
            blocked_since=
        fi
        if (( SECONDS - started >= STATUS_LIMIT )); then
            stop_phase "Ice 沒有在隱藏（原因：$STATUS_LIMIT 秒內沒有 active）"
            return 1
        fi
        sleep 0.5
    done
}

# Every member's place after `active`: recorded, never a stop (a hidden member is
# meant to be off the bar).
snapshot_members_after_active() {
    local i
    for i in {1..${#member_fds}}; do snapshot_member $i "active 後"; done
}

yes_no='^[yn]$'
out_of_ten='^([0-9]|10)$'
number='^[0-9]+$'

# Asks until the answer fits; records it. Returns 1 when the phase cannot go on.
ask() { # <key> <pattern> <hint> <question>
    local answer
    while true; do
        if ! kill -0 $ice_pid 2>/dev/null; then
            print -- "Ice 已經結束，中止。"
            finish 1
        fi
        if [[ -n ${helper_pids[1]:-} ]] && ! kill -0 $helper_pids[1] 2>/dev/null; then
            print -- "helper 已退出（每階段上限 30 分鐘）。這個階段到此為止，可用 --phase $current_phase 重跑。"
            return 1
        fi
        print -n -- "$4 [$3] "
        if ! read -r answer; then
            print
            print -- "輸入結束，中止。"
            finish 1
        fi
        [[ $answer =~ $2 ]] && break
    done
    print -r -- "$(date +%H:%M:%S)"$'\t'"p$label.$1"$'\t'"$answer" >> $run/answers.txt
    REPLY=$answer
}

# Rows 1-4 of section 10.5, for k = 1, 2, 4, and row 1b in phase 1. Called
# after the first `active` (wait_for_phase_status).
hide_and_press_phase() {
    local k=${phase_members[current_phase]}
    print -- "【第 1 列】【看選單列】$k 個 helper 剛才在右邊那排圖示（Wi-Fi、電池、Ice）的最左端：黑白線條、像方括號的小圖示，沒有文字（啟動時位置 x = ${(j:、:)member_x}；選單列從左到右 0-$display_width）。"
    ask row1.hidden $yes_no "y/n" "【看選單列】現在 helper 全部從列上消失、列上沒有 «、Ice 圖示還在？" || return 1
    ask row1.flickerSeconds $number "秒數" "【看選單列】剛才校準時，圖示大約閃了幾秒？" || return 1
    if (( current_phase == 1 )); then
        print -- "【第 1b 列】【看選單列】點一下左上角 Terminal 的「Shell」選單，再按 Esc，然後看著 Ice 圖示下方數 $click_watch 秒。"
        ask row1b.done '^$' "Enter" "【看終端】做完就按 Enter" || return 1
        sleep $click_watch
        ask row1b.noIceBar $yes_no "y/n" "【看選單列】選單正常打開過，而且這 $click_watch 秒裡 Ice 圖示下方沒有跳出 IceBar？" || return 1
    fi
    print -- "【第 2 列】【看選單列】右鍵 Ice 圖示 > Ice Settings… > General，把 Use Ice Bar 關掉再打開，等終端出現 active；共做 10 次（每次約 1-2 分鐘）。"
    ask row2.cleanOfTen $out_of_ten "0-10" "【看選單列】10 次裡，幾次打開後 helper 全部消失且沒有 «？" || return 1
    print -- "【第 3 列】【看選單列】關掉設定視窗，左鍵點 Ice 圖示。"
    ask row3.cells $number "格數" "【看選單列】Ice 圖示下方的 IceBar 有幾格？（沒出現填 0；應為 $k）" || return 1
    ask row3.icons $yes_no "y/n" "【看選單列】每一格都有圖示？" || return 1
    print -- "【第 4 列】【看選單列】點 IceBar 的一格，看選單，按 Esc 關掉；輪流點各格，共 10 次。"
    ask row4.openedOfTen $out_of_ten "0-10" "【看選單列】10 次裡，幾次在 1 秒內開出只有「Spike」一項的選單？" || return 1
    ask row4.dimmed $yes_no "y/n" "【看選單列】有任何一格變灰（Cannot open on macOS 27）？" || return 1
}

# Rows 5-9: long menus, a new item, a Command-drag.
layout_change_phase() {
    local count=$long_menus menus_fd
    launch_helper Menus.app $run/helper-p$label-menus.log --role menus || return 1
    menus_fd=$helper_fds[-1]
    while true; do
        print -u $menus_fd -- "menus $count"
        note "menus $count sent"
        print -- "【第 5 列】【看選單列】點 Dock 上新出現的 Menus（選單列左邊會出現 M01、M02… 共 $count 個），停 10 秒。"
        ask row5.shown $yes_no "y/n" "【看選單列】helper 回到列上並一直留著？" || return 1
        t7_log_has_long_menu $run/ice.log ${phase_from[$label]} && break
        print -- "【看終端】紀錄裡沒有 longMenu（選單可能還不夠長）。"
        ask row5.retry '^([1-9]|[1-3][0-9]|40)?$' "1-40，或直接 Enter 跳過" "【看終端】要改用幾個選單再試一次？" || return 1
        [[ -z $REPLY ]] && break
        count=$REPLY
    done
    ask row5.noIceBar $yes_no "y/n" "【看選單列】此時左鍵點 Ice 圖示，IceBar 沒有出現？" || return 1
    print -- "【第 6 列】【看終端】點回這個 Terminal 視窗，等上面出現 active。"
    ask row6.hiddenAgain $yes_no "y/n" "【看選單列】helper 再次消失、沒有 «？" || return 1
    ask row6.seconds $number "秒數" "【看選單列】從點回 Terminal 到 helper 消失，大約幾秒？" || return 1
    print -- "【第 7 列】【看選單列】按 Enter 後 $NEW_ITEM_DELAY 秒會啟動一個新 helper，請盯著選單列右側。"
    ask row7.go '^$' "Enter" "【看終端】準備好了就按 Enter" || return 1
    sleep $NEW_ITEM_DELAY
    launch_member new $new_item_glyph || return 1
    ask row7.shownAtOnce $yes_no "y/n" "【看選單列】新圖示一出現，原本藏著的 helper 立刻回到列上？" || return 1
    print -- "【看終端】等上面出現 active。"
    ask row7.hiddenAgain $yes_no "y/n" "【看選單列】之後 3 個 helper 全部再次消失、沒有 «？" || return 1
    print -- "【第 8 列】【看選單列】等 helper 回到列上後（可先點一下別的 app 再點回來），按住 Command 把一個 helper 拖到 Ice 圖示右邊，放開，等終端出現 active。"
    ask row8.draggable $yes_no "y/n" "【看選單列】拖得動？" || return 1
    ask row8.shownWhileDragging $yes_no "y/n" "【看選單列】按住 Command 開始拖的時候，藏著的 helper 回到列上？" || return 1
    ask row8.backInIceBar $yes_no "y/n" "【看選單列】放開後：被拖的留在列上，其餘 2 個再次消失，IceBar 是 2 格？" || return 1
    print -- "【第 9 列】【看選單列】再用 Command 把它拖回最左側，等終端出現 active。"
    ask row9.backToThree $yes_no "y/n" "【看選單列】IceBar 回到 3 格？" || return 1
}

# One phase up to Ice's `active`: the members, the placement gate, the wait,
# the placement after, a capture before and after. Returns 1 when it stopped.
reach_active() {
    local index off_bar=0
    phase_stopped=0
    delete_helper_domains
    phase_from[$label]=$(( $(log_lines) + 1 ))
    note "phase $label begins"
    for index in {1..${phase_members[current_phase]}}; do
        launch_member $index $member_glyphs[index]
        case $? in
            1) print -- "helper 沒有全部啟動，這個階段不做（可用 --phase $current_phase 重跑）。"; return 1 ;;
            2) off_bar=1 ;;
        esac
    done
    capture_bar before
    # Recorded, not a gate: a member's arrival may have moved a reference.
    check_references "$label before-wait"
    if (( off_bar )); then
        stop_phase "helper 不在選單列上"
        return 1
    fi
    wait_for_phase_status || return 1
    snapshot_members_after_active
    capture_bar active
}

# The bar strip only (plan section 11); never the rest of the screen.
capture_bar() { # <when>
    (( CAPTURE )) || return 0
    screencapture -x -R0,0,${display_width%.*},${bar_height%.*} $run/bar-$label-$1.png 2>/dev/null
    note "capture $label $1: $(stat -f %z $run/bar-$label-$1.png 2>/dev/null || print failed) bytes"
}

end_phase() { # <completed: 0|1>
    (( $1 )) && phase_done[$label]=1
    phase_to[$label]=$(log_lines)
    note "phase $label ends (complete: $1)"
    close_helpers
}

# --- references (section 11, G1) ---------------------------------------------------------

# Runs Ice's own reference rule on the live bar. The whole line, which names
# other apps' items, goes to the run directory only; the Terminal and the
# report get counts.
check_references() { # [why it is asked]
    local line rc divider icon
    line=$($shared/apps/icewatch references 2>/dev/null)
    rc=$?
    print -r -- "$(date +%H:%M:%S) ${1:-gate} $line" >> $run/references.txt
    # Ice's icon left of its own hidden divider: there is no visible section
    # at all, and no drag of a helper can make one (run 20261007-201416-t7).
    references_inverted=0
    divider=$(t7_json_get "$line" dividerMinX) && icon=$(t7_json_get "$line" iceIconMidX) \
        && t7_is_number "$divider" && t7_is_number "$icon" && (( icon < divider )) && references_inverted=1
    references_line="參照 $(t7_json_get "$line" references || print '?') 個（讀取完整：$(t7_json_get "$line" complete || print '?')；自己的 helper $(t7_json_get "$line" helpers || print '?') 個；其他 app 的圖示：隱藏區 $(t7_json_get "$line" otherHidden || print '?') 個、可見區 $(t7_json_get "$line" otherVisible || print '?') 個）"
    return $rc
}

# Several reads, as the bar and Accessibility take a moment to settle after
# an item appears or is dragged.
poll_references() {
    for _ in {1..$reference_polls}; do
        check_references && return 0
        sleep 0.5
    done
    return 1
}

# Ice's baseline needs a reference. The helpers' preferred position should
# have put one there; if not, the owner drags one, in this same sitting.
reference_gate() {
    local try
    poll_references && return 0
    for try in {1..$reference_tries}; do
        if (( references_inverted )); then
            print -- "Ice 自己的圖示排在它的分隔線左邊：這是 Ice 的佈局錯誤，拖 helper 也沒有用，所以不請你拖。"
            return 1
        fi
        print -- "【看選單列】Ice 需要一個「參照圖示」，現在沒有。請按住 Command 鍵，把一個方括號小圖示（黑白線條、沒有文字）拖到 Ice 圖示的左邊、緊挨著它（Ice 圖示和它左邊那條分隔線之間），放開。Ice 圖示＝右鍵點它會出現「Ice Settings…」的那個。"
        print -r -- "  （目前：$references_line）"
        ask refs.drag$try '^$' "Enter" "【看終端】拖好了就按 Enter（第 $try / $reference_tries 次）" || return 1
        poll_references && return 0
    done
    return 1
}

# --- the run ---------------------------------------------------------------------------

label=0
current_phase=0
if ! reference_gate; then
    print -- "沒有參照圖示，本輪無效"
    print -r -- "p0 沒有參照圖示（Ice 的分隔線與圖示之間沒有可辨識的圖示）" >> $run/stops.txt
    note "no reference: $references_line"
    finish 3
fi
note "references: $references_line"

if (( smoke )); then
    in_smoke=1
    print
    print -- "===== 自動檢查（不用輸入，約 ${#smoke_phases} × 3 分鐘）：確認 Ice 能把 helper 藏起來 ====="
    for current_phase in $smoke_phases; do
        label=s$current_phase
        print
        print -- "--- 自動檢查 $label：${phase_members[current_phase]} 個 helper ---"
        phase_ok=1
        reach_active || phase_ok=0
        end_phase $phase_ok
    done
    in_smoke=0
    if (( ${#phase_done} != ${#smoke_phases} )); then
        print -- "自動檢查沒有全部通過，不進入問答。"
        finish 3
    fi
    print -- "自動檢查全部通過。"
    (( checklist )) || finish 0
fi

smoke_done=${#phase_done}
for current_phase in $phases; do
    label=$current_phase
    print
    print -- "===== 階段 $current_phase / 4：${phase_members[current_phase]} 個 helper（上限 30 分鐘）====="
    phase_ok=1
    if reach_active; then
        if (( current_phase == 4 )); then
            layout_change_phase || phase_ok=0
        else
            hide_and_press_phase || phase_ok=0
        fi
    else
        phase_ok=0
    fi
    end_phase $phase_ok
done

# 3: the run ended in order, but a phase was not completed.
finish $(( ${#phase_done} - smoke_done == ${#phases} ? 0 : 3 ))
