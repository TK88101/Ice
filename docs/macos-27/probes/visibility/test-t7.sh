#!/bin/zsh
# Tests of the T7 scripts (docs/plans/2026-10-03-icebar-build.md section 10.4):
# t7-lib.zsh's functions and run-t7.sh against stub binaries in a throwaway
# staging directory outside ~/Documents. Nothing real is launched: Ice, vzhelper
# and icewatch are stubs that leave a marker when executed. The preferences
# tests use a sacrificial domain, deleted afterwards.
set -uo pipefail
here=${0:A:h}
repo=$(git -C $here rev-parse --show-toplevel)
source $here/t7-lib.zsh
tmp=/private/tmp/claude-501/t7-test-$$
t7_private_directory $tmp || exit 1
shared=$tmp/shared
export T7_STUB_MARKS=$tmp/marks
domain=com.icespike4.t7test
helper_domain=com.icespike4.t7helper
failures=0

wipe() {
    chmod -R u+w $tmp 2>/dev/null
    rm -rf $tmp
}
cleanup() {
    defaults delete $domain >/dev/null 2>&1
    defaults delete $helper_domain >/dev/null 2>&1
    wipe
}
trap cleanup EXIT

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
# After a `[[ ... ]]` or a command: its status decides; a failure shows the
# runner's output.
expect() { # <label>
    if (( $? == 0 )); then ok $1; else fail $1; [[ -f $tmp/out.txt ]] && cat $tmp/out.txt; fi
}

# --- the stub staging ---------------------------------------------------------
stub() { # <path> <body>
    mkdir -p ${1:h}
    print -r -- "#!/bin/zsh"$'\n'"$2" > $1
    chmod 0755 $1
}
# The stub Ice logs the statuses of T7_STUB_STATUS one after the other (by
# default `checking`, then `active`, as the real one does after a calibration;
# `sleep:<s>` waits, `exit` ends it, `shown:<reason>` is a shown status) and then
# leaves a marker so that a test can wait for it. The stubs, not run-t7.sh, read
# the environment.
build_staging() { # [expected user]
    wipe
    mkdir -p $shared/evidence $T7_STUB_MARKS $tmp/backup
    stub $shared/Ice.app/Contents/MacOS/Ice 'print -r -- "$*" >> $T7_STUB_MARKS/ice
print -u2 "2026-10-05 10:00:00.100000+0900 Ice[1:1] [Permissions] Passed all permissions checks"
trap "exit 0" TERM
sleep 1
for token in ${=T7_STUB_STATUS:-checking active}; do
    case $token in
        sleep:*) sleep ${token#sleep:} ;;
        exit) exit 0 ;;
        shown:*) print -u2 "2026-10-05 10:00:02.000000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: shown(IceCore.IceBarShownReason.${token#shown:})" ;;
        *) print -u2 "2026-10-05 10:00:09.500000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: $token" ;;
    esac
done
: > $T7_STUB_MARKS/ice-active
sleep 1000 &
wait'
    # selfread answers by T7_STUB_SELFREAD: ok (on the bar), offbar, slow (1 s
    # late, still on the bar), malformed, wrongid, none.
    local helper='print -r -- "$*" >> $T7_STUB_MARKS/vzhelper
id=none
for (( i = 1; i < $#; i++ )); do [[ ${@[i]} == --identifiers ]] && id=${@[i+1]}; done
print "up {\"pid\":1}"
[[ "$*" == *--menu* ]] && print "menu {\"event\":\"open\"}"
answer() { print -r -- "selfread {\"children\":[{\"frame\":[1100,0,24,32],\"identifier\":\"vz-other\"},{\"frame\":$1,\"identifier\":\"$2\"}]}"; }
while read -r line; do
    print -r -- "$line" >> $T7_STUB_MARKS/vzhelper-stdin
    [[ $line == selfread ]] || continue
    case ${T7_STUB_SELFREAD:-ok} in
        ok) answer "[1200,0,24,32]" $id ;;
        offbar) answer "[1200,300,24,32]" $id ;;
        slow) { sleep 1; answer "[1200,0,24,32]" $id } & ;;
        malformed) print -r -- "selfread {oops" ;;
        wrongid) answer "[1200,0,24,32]" vz-someone-else ;;
    esac
done'
    stub $shared/apps/Target.app/Contents/MacOS/vzhelper $helper
    stub $shared/apps/Menus.app/Contents/MacOS/vzhelper $helper
    stub $shared/apps/icewatch 'print -r -- "$*" >> $T7_STUB_MARKS/icewatch
if [[ $1 == menu-frame ]]; then
    print -r -- "${T7_STUB_MENU:-{\"barHeight\":33,\"displayWidth\":1728,\"menuMaxX\":574,\"notchMinX\":771.5,\"verdict\":\"fits\"}}"
    exit 0
fi
print "{\"axTrusted\":${T7_STUB_AX:-true},\"pid\":1,\"screenCapture\":true}"'
    cp $here/run-t7.sh $here/t7-lib.zsh $shared/
    t7_write_env $shared ${1:-$(id -un)} $(id -un) test $domain $helper_domain BACKUP_ROOT=$tmp/backup NEW_ITEM_DELAY=0
    # As the real staging: nothing but evidence/ is writable by the runner.
    chmod -R a-w $shared
    chmod 1777 $shared/evidence
}
# Changes one staged file the way another account could not: for the guards.
tamper() { # <file> <line to append>
    chmod u+w ${1:h} $1 2>/dev/null
    print -r -- "$2" >> $1
    chmod a-w ${1:h} $1
}
run() { # <stdin file> <args...>
    local input=$1
    shift
    /bin/zsh $shared/run-t7.sh "$@" < $input > $tmp/out.txt 2>&1
}
# The answers, once the stub Ice has logged its `active`.
answer_when_active() { # <fifo> <answers...>
    local fifo=$1
    shift
    mkfifo $fifo
    { until [[ -e $T7_STUB_MARKS/ice-active ]]; do sleep 0.1; done; print -l -- "$@" } > $fifo &
}
stub_ice_running() { pgrep -f "$shared/Ice.app/Contents/MacOS/Ice" >/dev/null; }

# --- t7-lib: preferences ------------------------------------------------------
defaults delete $domain >/dev/null 2>&1
defaults write $domain Text -string before
defaults write $domain Flag -bool true
defaults write $domain Nested -dict a 1 b 2
t7_prefs_export $domain $tmp/before.plist
plutil -lint $tmp/before.plist >/dev/null; expect "export is a readable plist"
t7_prefs_same $domain $tmp/before.plist; expect "an unchanged domain is the same as its export"
defaults write $domain Text -string after
defaults write $domain Added -bool true
! t7_prefs_same $domain $tmp/before.plist; expect "a changed domain differs from its export"
# The added key survives a plain import (it merges), so this is the
# delete-and-import path.
t7_prefs_restore $domain $tmp/before.plist; expect "restore gives the export back"
t7_prefs_same $domain $tmp/before.plist; expect "restored domain is the same as its export"
! defaults read $domain Added >/dev/null 2>&1; expect "the added key is gone"
defaults delete $domain
t7_prefs_export $domain $tmp/absent.plist
t7_prefs_is_empty $tmp/absent.plist; expect "an absent domain exports as empty"
defaults write $domain UseIceBar -bool true
t7_prefs_restore $domain $tmp/absent.plist; expect "restore of an empty export"
t7_domain_is_empty $domain; expect "an absent domain stays empty"

# --- t7-lib: digests and directories ---------------------------------------------
mkdir -p $tmp/tree/sub && print one > $tmp/tree/sub/file && ln -s file $tmp/tree/sub/link
before=$(t7_sha_tree $tmp/tree)
[[ $before == $(t7_sha_tree $tmp/tree) ]]; expect "a tree's digest is stable"
ln -sf /etc/hosts $tmp/tree/sub/link
[[ $before != $(t7_sha_tree $tmp/tree) ]]; expect "a retargeted link changes the digest"
mkdir $tmp/order && touch $tmp/order/{_A,a,B}
[[ $(LC_ALL=C t7_sha_tree $tmp/order) == $(LC_ALL=en_US.UTF-8 t7_sha_tree $tmp/order) ]]; expect "a tree's digest does not depend on the locale"
ln -s $tmp/tree $tmp/linked
! t7_private_directory $tmp/linked 2>/dev/null; expect "a symlinked directory is refused"
! t7_private_directory /private/tmp/t7-test-$$ 2>/dev/null; expect "a directory under a parent that is not ours is refused"
[[ ! -e /private/tmp/t7-test-$$ ]]; expect "and is not created"

# --- t7-lib: the log summary ---------------------------------------------------
cat > $tmp/ice.log <<'LOG'
2026-10-05 10:00:01.000000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: checking
2026-10-05 10:00:02.000000+0900 Ice[1:1] [IceBarHiding] IceBar baseline: ok true
2026-10-05 10:00:05.000000+0900 Ice[1:1] [IceBarHiding] IceBar trial: length 736.0 outcome hiddenClean
2026-10-05 10:00:08.000000+0900 Ice[1:1] [IceBarHiding] IceBar trial: length 752.0 outcome unknown
2026-10-05 10:00:11.000000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: active
2026-10-05 10:01:00.000000+0900 Ice[1:1] [IceBarHiding] A fold appeared at rest; showing the hidden section
2026-10-05 10:01:00.500000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: checking
2026-10-05 10:01:20.500000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: active
2026-10-05 10:02:00.000000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: shown(IceCore.IceBarShownReason.longMenu)
2026-10-05 10:02:30.000000+0900 Ice[1:1] [IceBarHiding] IceBar baseline: ok false
2026-10-05 10:02:31.000000+0900 Ice[1:1] [IceBarPress] Press failed, disabling the IceBar cell for x
2026-10-05 10:02:40.000000+0900 Ice[1:1] [MenuBarItemManager] unrelated
LOG
summary=$(t7_summary < $tmp/ice.log)
for line in \
    "active 2 次" \
    "checking→active 秒數：中位 15.0（最短 10.0，最長 20.0）" \
    "shown longMenu 1" \
    "靜止時出現 « 1 次" \
    "按壓失敗 1 次" \
    "試長度結果：hiddenClean 1 / folded 0 / drawn 0 / unknown 1" \
    "baseline：成功 1 / 失敗 1" \
    "Ice 的 IceBar 紀錄 11 行，讀懂 11 行"; do
    [[ $summary == *$line* ]] && [[ $summary != *讀不懂* ]]; expect "summary: $line"
done
summary=$(print "2026-10-05 10:00:01.000000+0900 Ice[1:1] [IceBarHiding] IceBar state: resting" | t7_summary)
[[ $summary == *"紀錄 1 行，讀懂 0 行（有讀不懂的行"* ]]; expect "summary: a line it cannot read is flagged"
summary=$(print "2026-10-05 10:00:01.000000+0900 Ice[1:1] [Other] Press failed, IceBar hiding: active" | t7_summary)
[[ $summary == *"active 0 次"* && $summary == *"按壓失敗 0 次"* && $summary == *"紀錄 0 行"* ]]; expect "summary: another category's line is not counted"
t7_log_has_long_menu $tmp/ice.log 1; expect "long menu found in the log"
! t7_log_has_long_menu $tmp/ice.log 10; expect "long menu not found after its line"

# --- t7-lib: the latest status, menu-frame, helper placement (plan 2026-10-07 F2-F4) ---
[[ $(t7_latest_status $tmp/ice.log 1) == shown:longMenu ]]; expect "latest status: a shown reason"
[[ $(t7_latest_status $tmp/ice.log 5) == shown:longMenu && $(t7_latest_status $tmp/ice.log 1 7) == checking ]]; expect "latest status: within a slice"
[[ $(t7_latest_status $tmp/ice.log 1 5) == active ]]; expect "latest status: active"
[[ -z $(t7_latest_status $tmp/ice.log 12) ]]; expect "latest status: none after the last line"
fits='{"barHeight":33,"displayWidth":1728,"menuMaxX":574,"notchMinX":771.5,"verdict":"fits"}'
t7_menu_frame_ok $fits; expect "menu-frame: fits with every number is ok"
for bad in '{"barHeight":33,"displayWidth":1728,"menuMaxX":null,"notchMinX":771.5,"verdict":"unreadable"}' \
    '{"barHeight":33,"displayWidth":1728,"menuMaxX":null,"notchMinX":771.5,"verdict":"fits"}' \
    '{"barHeight":33,"displayWidth":1728,"menuMaxX":900,"notchMinX":771.5,"verdict":"crossesNotch"}' \
    '{"barHeight":33,"menuMaxX":574,"notchMinX":771.5,"verdict":"fits"}' \
    'menuMaxX 574 fits' ''; do
    ! t7_menu_frame_ok $bad; expect "menu-frame refused: ${bad[1,60]}"
done
[[ $(t7_json_get $fits displayWidth) == 1728 ]]; expect "json: a number by key"
reply() { # <identifier> <frame>
    print -r -- '{"children":[{"frame":[1100,0,24,32],"identifier":"vz-other"},{"frame":'$2',"identifier":"'$1'"}],"trusted":true}'
}
[[ $(t7_placement "$(reply vz-t7-hidden2 '[1210.5,0,24,32]')" vz-t7-hidden2 1728 33) == 'on 1210.5' ]]; expect "placement: on the bar, its own child"
t7_placement "$(reply vz-t7-hidden2 '[1210.5,0,24,32]')" vz-t7-hidden2 1728 33 >/dev/null; expect "placement: on the bar returns 0"
for frame in '[1210,200,24,32]' '[-40,0,24,32]' '[1720,0,24,32]' '[1210,0,0,32]' '[1210,0,24,40]'; do
    t7_placement "$(reply vz-t7-hidden2 $frame)" vz-t7-hidden2 1728 33 >/dev/null
    [[ $? == 1 ]]; expect "placement: off the bar $frame"
done
for json in "$(reply vz-t7-other2 '[1210,0,24,32]')" "$(reply vz-t7-hidden2 '"x"')" '{"children":[{"identifier":"vz-t7-hidden2"}]}' '{"error":"unencodable"}' 'garbage' ''; do
    t7_placement "$json" vz-t7-hidden2 1728 33 >/dev/null
    [[ $? == 2 ]]; expect "placement: unknown for ${json[1,50]}"
done

# What t7_summary reads is what Ice's sources write.
ice27=$repo/Ice/MenuBar/IceBar27
core=$repo/Packages/IceCore/Sources/IceCore
for literal in 'IceBar hiding: ' 'IceBar trial: length ' 'IceBar baseline: ok ' 'A fold appeared at rest' 'category: "IceBarHiding"'; do
    grep -q -F -- $literal $ice27/IceBarHidingCoordinator.swift; expect "Ice still logs: $literal"
done
grep -q -F 'Press failed' "$ice27/MenuBarItemManager+IceBar27.swift" && grep -q -F 'category: "IceBarPress"' "$ice27/MenuBarItemManager+IceBar27.swift"
expect "Ice still logs: Press failed"
# Each enum's own declaration only: `Phase` has an `off` and a `shown` of its own.
enum_has() { # <file> <enum> <case, as a regex>
    awk -v start="enum $2[: ]" '$0 ~ start, /^}/' $1 | grep -q -E "^ +case $3( |\$)"
}
for name in checking active off 'shown[(]IceBarShownReason[)]'; do
    enum_has $core/IceBarHidingMachine.swift IceBarHidingStatus $name; expect "IceBarHidingStatus still has: $name"
done
enum_has $core/IceBarHidingMachine.swift IceBarShownReason longMenu; expect "IceBarShownReason still has: longMenu"
for name in hiddenClean folded drawn unknown; do
    enum_has $core/HiddenLengthCalibrator.swift HiddenLengthOutcome $name; expect "HiddenLengthOutcome still has: $name"
done
! enum_has $core/IceBarHidingMachine.swift IceBarHidingStatus resting; expect "a case of another enum is not found"

# --- run-t7.sh --dry-run --------------------------------------------------------
build_staging
run /dev/null --dry-run; expect "dry run exits 0"
[[ ! -e $T7_STUB_MARKS/ice && ! -e $T7_STUB_MARKS/vzhelper ]]; expect "dry run starts neither Ice nor a helper"
[[ $(cat $T7_STUB_MARKS/icewatch 2>/dev/null) == $'preflight\nmenu-frame' ]]; expect "dry run calls icewatch with preflight and menu-frame only"
t7_domain_is_empty $domain; expect "dry run leaves the domain empty"
[[ -z $(ls $shared/evidence) && -z $(ls $tmp/backup) ]]; expect "dry run writes nothing"

# --- guards: each exits 2 with nothing started -----------------------------------
refused() { [[ $? == 2 && ! -e $T7_STUB_MARKS/ice && ! -e $T7_STUB_MARKS/pwned ]]; }
build_staging nobody
run /dev/null; refused; expect "a wrong user exits 2 before anything starts"
build_staging
tamper $shared/apps/icewatch '# changed'
run /dev/null --dry-run; refused; expect "a changed staged binary exits 2"
build_staging
tamper $shared/Ice.app/Contents/MacOS/Ice.debug.dylib code
run /dev/null --dry-run; refused; expect "a file added to the staged Ice.app exits 2"
build_staging
T7_STUB_AX=false run /dev/null --dry-run; refused; expect "a false preflight exits 2"
for menu in '{"barHeight":33,"displayWidth":1728,"menuMaxX":null,"notchMinX":771.5,"verdict":"unreadable"}' 'garbage'; do
    build_staging
    T7_STUB_MENU=$menu run /dev/null --dry-run; refused; expect "menu-frame ${menu[1,40]} exits 2 in a dry run"
    build_staging
    T7_STUB_MENU=$menu run /dev/null --phase 1; refused; expect "menu-frame ${menu[1,40]} exits 2 before anything starts"
done
build_staging
tamper $shared/t7.env "X=\$(touch $T7_STUB_MARKS/pwned)"
run /dev/null --dry-run; refused; expect "a command in t7.env exits 2 and is not run"
build_staging
chmod u+w $shared/t7-lib.zsh && print -r -- ": > $T7_STUB_MARKS/pwned" >> $shared/t7-lib.zsh
run /dev/null; refused; expect "a library this account can rewrite exits 2 and is not sourced"
build_staging
chmod u+w $shared && mv $shared/t7-lib.zsh $shared/real-lib.zsh && ln -s real-lib.zsh $shared/t7-lib.zsh && chmod a-w $shared
run /dev/null --dry-run; refused; expect "a symlinked library exits 2, in a dry run too"

# --- one phase, start to report ---------------------------------------------------
build_staging
defaults write $domain Text -string before
# row 1 (two answers), row 1b (Enter, then y), rows 2-4.
answer_when_active $tmp/answers y 60 '' y 10 1 y 10 n
run $tmp/answers --phase 1; expect "phase 1 runs to the end"
grep -q '==== T7 回報 ====' $tmp/out.txt && grep -q '==== 結束 ====' $tmp/out.txt; expect "the report has both markers"
grep -q '偏好還原：verified' $tmp/out.txt; expect "the report says the restore is verified"
[[ $(defaults read $domain Text 2>/dev/null) == before ]] && ! defaults read $domain UseIceBar >/dev/null 2>&1; expect "the domain is what it was"
[[ -e $T7_STUB_MARKS/ice && $(grep -c -- '--menu' $T7_STUB_MARKS/vzhelper) == 1 ]]; expect "Ice and one member were started"
grep -q -- '-SUEnableAutomaticChecks NO -SUAutomaticallyUpdate NO' $T7_STUB_MARKS/ice; expect "Sparkle is off by launch arguments"
! stub_ice_running; expect "Ice is gone after the run"
backup=($tmp/backup/*(N))
[[ ${#backup} == 1 && -f $backup[1]/prefs-before.plist && $(stat -f %Lp $backup[1]) == 700 ]]; expect "the private backup is kept, mode 700"
grep -q 'active 1 次' $tmp/out.txt && grep -q '紀錄 2 行，讀懂 2 行' $tmp/out.txt; expect "the report counts the log"
grep -q 'helper 選單開啟 1 次' $tmp/out.txt; expect "the report counts the helpers' menu opens"
grep -q 'p1.row4.openedOfTen = 10' $tmp/out.txt; expect "the report lists the answers"
[[ $(grep -c 'p1.row1b.noIceBar = y' $tmp/out.txt) == 1 ]] && [[ $(grep -c '「Shell」' $tmp/out.txt) == 1 ]]; expect "row 1b is asked once and recorded"
grep -q 'helper p1-1 啟動後 x=1200 在列上' $tmp/out.txt && grep -q 'helper p1-1 active 後 x=1200 在列上' $tmp/out.txt; expect "the report places the helper at both snapshots"
grep -q '右邊那排圖示（Wi-Fi、電池、Ice）的最左端' $tmp/out.txt && grep -q 'x = 1200' $tmp/out.txt; expect "row 1 says where to look"
# Every question and every row's instruction says where to look.
! grep -E '^ *ask ' $here/run-t7.sh | grep -v -E '"【看(選單列|終端)】' >/dev/null; expect "every question carries a tag"
! grep -E '^ *print -- "【第' $here/run-t7.sh | grep -v -E '【第 [0-9]+b? 列】【看(選單列|終端)】' >/dev/null; expect "every row's instruction carries a tag"

# --- Ice not hiding: the phase stops by itself (plan 2026-10-07 F2) ------------------------
stops_cleanly() { # <exit code wanted>
    [[ $? == $1 ]] && grep -q '偏好還原：verified' $tmp/out.txt && ! stub_ice_running && ! grep -q '【第 1 列】' $tmp/out.txt
}
build_staging
T7_STUB_STATUS="checking shown:menuUnreadable" run /dev/null --phase 1 --test-limits 30 1
stops_cleanly 3 && grep -q 'Ice 沒有在隱藏（原因：menuUnreadable），本輪無效' $tmp/out.txt; expect "menuUnreadable that stays: exit 3, said, no row prompt"
grep -q -- '-- 階段 1（k = 1）未完成' $tmp/out.txt && grep -q '本輪無效：Ice 沒有在隱藏（原因：menuUnreadable）' $tmp/out.txt; expect "the report says why the phase stopped"
build_staging
answer_when_active $tmp/answers y 60 '' y 10 1 y 10 n
T7_STUB_STATUS="checking shown:menuUnreadable active" run $tmp/answers --phase 1 --test-limits 30 5; expect "menuUnreadable then active within the grace: the phase goes on"
build_staging
T7_STUB_STATUS="checking" run /dev/null --phase 1 --test-limits 2 1
stops_cleanly 3 && grep -q 'Ice 沒有在隱藏（原因：2 秒內沒有 active），本輪無效' $tmp/out.txt; expect "no active within the limit: exit 3"
build_staging
T7_STUB_STATUS="checking exit" run /dev/null --phase 1 --test-limits 30 1
stops_cleanly 1 && grep -q 'Ice 已經結束' $tmp/out.txt; expect "Ice ends while waiting: exit 1"
for reason in cannotAssess noCleanLength; do
    build_staging
    T7_STUB_STATUS="checking shown:$reason" run /dev/null --phase 1 --test-limits 30 1
    stops_cleanly 3 && grep -q "原因：$reason" $tmp/out.txt; expect "$reason that stays: exit 3"
done

# --- where the helper is: the first snapshot gates the phase (plan F3) ---------------------
build_staging
T7_STUB_SELFREAD=offbar run /dev/null --phase 1 --test-limits 30 1
stops_cleanly 3 && grep -q 'helper 不在選單列上，本輪無效' $tmp/out.txt && grep -q 'helper p1-1 啟動後 不在列上（1200,300,24,32）' $tmp/out.txt; expect "a helper below the bar: exit 3 before any row"
for mode in malformed wrongid none; do
    build_staging
    T7_STUB_SELFREAD=$mode run /dev/null --phase 1 --test-limits 30 1
    stops_cleanly 3 && grep -q 'helper p1-1 啟動後 unknown' $tmp/out.txt && [[ $(grep -c -x selfread $T7_STUB_MARKS/vzhelper-stdin) == 2 ]]; expect "selfread $mode: asked twice, then exit 3"
done
build_staging
answer_when_active $tmp/answers y 60 '' y 10 1 y 10 n
T7_STUB_SELFREAD=slow run $tmp/answers --phase 1; expect "a selfread reply 1 s late still counts"
grep -q 'helper p1-1 啟動後 x=1200 在列上' $tmp/out.txt; expect "and places the helper"

# --- phase 4: the menus helper, a new item ------------------------------------------
build_staging
# Row 5 (shown, no longMenu in the stub's log: Enter skips the retry, no
# IceBar), row 6, row 7 (Enter, two answers), row 8, row 9. A longMenu after the
# first active is not a stop.
answer_when_active $tmp/answers y '' y y 20 '' y y y y y y
T7_STUB_STATUS="checking active shown:longMenu" run $tmp/answers --phase 4 --test-limits 20 1; expect "phase 4 runs to the end"
grep -q -- '--role menus' $T7_STUB_MARKS/vzhelper && grep -q -x 'menus 24' $T7_STUB_MARKS/vzhelper-stdin; expect "the menus helper got its count"
[[ $(grep -c -- '--menu ' $T7_STUB_MARKS/vzhelper) == 3 ]] && grep -q 'vz-t7-gamma' $T7_STUB_MARKS/vzhelper; expect "two members and the new item were started"
grep -q 'p4.row9.backToThree = y' $tmp/out.txt; expect "the report lists phase 4's answers"

# --- end of input and signals: cleanup still runs ----------------------------------
build_staging
defaults write $domain Text -string before
print -l y > $tmp/answers
! run $tmp/answers --phase 1 && grep -q '偏好還原：verified' $tmp/out.txt && ! stub_ice_running; expect "end of input: cleanup ran"
grep -q -- '-- 階段 1（k = 1）未完成' $tmp/out.txt; expect "end of input: the phase is reported as not completed"

# --- a helper that does not start: the phase is skipped, the run says so ---------------
build_staging
chmod u+w $shared/apps/Target.app/Contents/MacOS{,/vzhelper} && print -r -- "#!/bin/zsh"$'\n'"exit 1" > $shared/apps/Target.app/Contents/MacOS/vzhelper
chmod u+w $shared $shared/t7.env && t7_write_env $shared $(id -un) $(id -un) test $domain $helper_domain BACKUP_ROOT=$tmp/backup NEW_ITEM_DELAY=0 && chmod -R a-w $shared && chmod 1777 $shared/evidence
run /dev/null --phase 1
[[ $? == 3 ]] && grep -q '未完成' $tmp/out.txt && grep -q '偏好還原：verified' $tmp/out.txt && ! stub_ice_running; expect "a helper that does not start: exit 3, phase not completed, cleanup ran"

for signal in TERM HUP INT QUIT; do
    build_staging
    defaults write $domain Text -string before
    mkfifo $tmp/fifo
    # A background job of a non-interactive shell starts with SIGINT and SIGQUIT
    # ignored; perl puts the defaults back before the script starts.
    perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec @ARGV' /bin/zsh $shared/run-t7.sh --phase 1 < $tmp/fifo > $tmp/out.txt 2>&1 &
    pid=$!
    exec {hold}> $tmp/fifo
    for _ in {1..100}; do [[ -e $T7_STUB_MARKS/vzhelper ]] && break; sleep 0.1; done
    kill -$signal $pid
    wait $pid
    exec {hold}>&-
    grep -q '偏好還原：verified' $tmp/out.txt && ! stub_ice_running && [[ $(defaults read $domain Text 2>/dev/null) == before ]]
    expect "SIG$signal: cleanup ran"
done

exit $failures
