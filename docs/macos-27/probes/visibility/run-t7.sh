#!/bin/zsh
# IceBar build plan T7 (docs/plans/2026-10-03-icebar-build.md section 10.3): the
# ONE command the owner runs, in the isolated account's Terminal, at the time
# the owner named. It starts the staged Ice and the sacrificial helpers, walks
# the checklist of section 10.5 with the owner, and on every exit path stops
# them, restores Ice's preferences and prints the report.
#
#   /Users/Shared/IceReverse-t7/run-t7.sh [--phase 1|2|3|4]
#   /Users/Shared/IceReverse-t7/run-t7.sh --dry-run     starts neither Ice nor a helper
#
# Everything it trusts is in its own directory, written by stage-t7.sh: no
# environment variable changes what it does.
set -uo pipefail
umask 022

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
usage="usage: run-t7.sh [--dry-run] [--phase 1|2|3|4]"

dry_run=0
phases=(1 2 3 4)
while (( $# )); do
    case $1 in
        --dry-run) dry_run=1 ;;
        --phase)
            [[ ${2:-} == [1-4] ]] || { print -u2 -- $usage; exit 64; }
            phases=($2)
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
required=(EXPECT_USER OWNER_USER GIT_REV DOMAIN HELPER_DOMAINS ICE_SHA TARGET_SHA MENUS_SHA ICEWATCH_SHA)
optional=(BACKUP_ROOT NEW_ITEM_DELAY)
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
(( guard_failed )) && exit 2

if (( dry_run )); then
    print -- "run-t7 dry-run：檢查通過（$GIT_REV；preflight $preflight）。正式執行會做："
    print -- "  1. 匯出 $domain 到 $backup_root/<run id>/prefs-before.plist，清空後寫入：$settings"
    print -- "  2. 啟動 OS_ACTIVITY_DT_MODE=YES OS_ACTIVITY_MODE=debug $ice $ice_arguments"
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
    for phase in ${(on)${(k)phase_from}}; do
        print -- "-- 階段 $phase（k = ${phase_members[phase]}）${${phase_done[$phase]:-未完成}:#1}"
        [[ -f $run/answers.txt ]] && awk -F'\t' -v prefix="p$phase." 'index($2, prefix) == 1 { print "  你的回答 " $2 " = " $3 }' $run/answers.txt
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

# The helper's stdin stays open in this script (EOF is its quit); the newest
# one's descriptor is $helper_fds[-1].
launch_helper() { # <app> <log> <vzhelper arguments...>
    local app=$1 log=$2 fifo=$run/.fifo-$RANDOM fd
    shift 2
    mkfifo $fifo || { print -- "（無法建立 $fifo，helper $app 沒有啟動）"; return 1; }
    $shared/apps/$app/Contents/MacOS/vzhelper --controller $$ "$@" --lifetime $helper_lifetime < $fifo > $log 2>&1 &
    helper_pids+=($!)
    exec {fd}> $fifo
    rm -f $fifo
    helper_fds+=($fd)
    for _ in {1..50}; do grep -q '^up ' $log && return 0; sleep 0.2; done
    print -- "（helper $app 沒有回報啟動，見 $log）"
    return 1
}

launch_member() { # <index> <glyph>
    launch_helper Target.app $run/helper-p$current_phase-$1.log --items 1 --identifiers vz-t7-$2 --glyphs $2 --menu || return 1
    note "phase $current_phase member $1 ($2) launched"
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
    print -r -- "$(date +%H:%M:%S)"$'\t'"p$current_phase.$1"$'\t'"$answer" >> $run/answers.txt
    REPLY=$answer
}

# Rows 1-4 of section 10.5, for k = 1, 2, 4.
hide_and_press_phase() {
    local k=${phase_members[current_phase]}
    print -- "【第 1 列】$k 個 helper 已啟動，會先出現在列上最左側。等上面出現 [Ice …] IceBar hiding: active（約 1-2 分鐘，期間圖示會閃）。"
    ask row1.hidden $yes_no "y/n" "active 之後：helper 全部從列上消失、列上沒有 «、Ice 圖示還在？" || return 1
    ask row1.flickerSeconds $number "秒數" "這次首次校準，圖示大約閃了幾秒？" || return 1
    print -- "【第 2 列】右鍵 Ice 圖示 > Ice Settings… > General，把 Use Ice Bar 關掉再打開，等 active；共做 10 次（每次約 1-2 分鐘）。"
    ask row2.cleanOfTen $out_of_ten "0-10" "10 次裡，幾次打開後 helper 全部消失且沒有 «？" || return 1
    print -- "【第 3 列】關掉設定視窗，左鍵點 Ice 圖示。"
    ask row3.cells $number "格數" "Ice 圖示下方的 IceBar 有幾格？（沒出現填 0；應為 $k）" || return 1
    ask row3.icons $yes_no "y/n" "每一格都有圖示？" || return 1
    print -- "【第 4 列】點 IceBar 的一格，看選單，按 Esc 關掉；輪流點各格，共 10 次。"
    ask row4.openedOfTen $out_of_ten "0-10" "10 次裡，幾次在 1 秒內開出只有「Spike」一項的選單？" || return 1
    ask row4.dimmed $yes_no "y/n" "有任何一格變灰（Cannot open on macOS 27）？" || return 1
}

# Rows 5-9: long menus, a new item, a Command-drag.
layout_change_phase() {
    local count=$long_menus menus_fd
    print -- "先等 [Ice …] IceBar hiding: active（2 個 helper 藏好）。"
    ask ready $yes_no "y/n" "已經 active、helper 都消失了？" || return 1
    launch_helper Menus.app $run/helper-p$current_phase-menus.log --role menus || return 1
    menus_fd=$helper_fds[-1]
    while true; do
        print -u $menus_fd -- "menus $count"
        note "menus $count sent"
        print -- "【第 5 列】點 Dock 上新出現的 Menus（選單列左邊會出現 M01、M02… 共 $count 個），停 10 秒。"
        ask row5.shown $yes_no "y/n" "helper 回到列上並一直留著？" || return 1
        t7_log_has_long_menu $run/ice.log ${phase_from[$current_phase]} && break
        print -- "紀錄裡沒有 longMenu（選單可能還不夠長）。"
        ask row5.retry '^([1-9]|[1-3][0-9]|40)?$' "1-40，或直接 Enter 跳過" "要改用幾個選單再試一次？" || return 1
        [[ -z $REPLY ]] && break
        count=$REPLY
    done
    ask row5.noIceBar $yes_no "y/n" "此時左鍵點 Ice 圖示，IceBar 沒有出現？" || return 1
    print -- "【第 6 列】點回這個 Terminal 視窗，等 active。"
    ask row6.hiddenAgain $yes_no "y/n" "helper 再次消失、沒有 «？" || return 1
    ask row6.seconds $number "秒數" "從點回 Terminal 到 helper 消失，大約幾秒？" || return 1
    print -- "【第 7 列】按 Enter 後 $NEW_ITEM_DELAY 秒會啟動一個新 helper，請盯著選單列右側。"
    ask row7.go '^$' "Enter" "準備好了就按 Enter" || return 1
    sleep $NEW_ITEM_DELAY
    launch_member new $new_item_glyph || return 1
    ask row7.shownAtOnce $yes_no "y/n" "新圖示一出現，原本藏著的 helper 立刻回到列上？" || return 1
    print -- "等 active。"
    ask row7.hiddenAgain $yes_no "y/n" "之後 3 個 helper 全部再次消失、沒有 «？" || return 1
    print -- "【第 8 列】等 helper 回到列上後（可先點一下別的 app 再點回來），按住 Command 把一個 helper 拖到 Ice 圖示右邊，放開，等 active。"
    ask row8.draggable $yes_no "y/n" "拖得動？" || return 1
    ask row8.shownWhileDragging $yes_no "y/n" "按住 Command 開始拖的時候，藏著的 helper 回到列上？" || return 1
    ask row8.backInIceBar $yes_no "y/n" "放開後：被拖的留在列上，其餘 2 個再次消失，IceBar 是 2 格？" || return 1
    print -- "【第 9 列】再用 Command 把它拖回最左側，等 active。"
    ask row9.backToThree $yes_no "y/n" "IceBar 回到 3 格？" || return 1
}

for current_phase in $phases; do
    print
    print -- "===== 階段 $current_phase / 4：${phase_members[current_phase]} 個 helper（上限 30 分鐘）====="
    delete_helper_domains
    phase_from[$current_phase]=$(( $(log_lines) + 1 ))
    note "phase $current_phase begins"
    phase_ok=1
    for index in {1..${phase_members[current_phase]}}; do
        launch_member $index $member_glyphs[index] || phase_ok=0
    done
    if (( ! phase_ok )); then
        print -- "helper 沒有全部啟動，這個階段不做（可用 --phase $current_phase 重跑）。"
    elif (( current_phase == 4 )); then
        layout_change_phase || phase_ok=0
    else
        hide_and_press_phase || phase_ok=0
    fi
    (( phase_ok )) && phase_done[$current_phase]=1
    phase_to[$current_phase]=$(log_lines)
    note "phase $current_phase ends (complete: $phase_ok)"
    close_helpers
done

# 3: the run ended in order, but a phase was not completed.
finish $(( ${#phase_done} == ${#phases} ? 0 : 3 ))
