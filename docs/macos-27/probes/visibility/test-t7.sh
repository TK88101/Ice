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
# The stub Ice logs `active` a moment after it starts, as the real one does
# after a calibration, and leaves a marker so that a test can wait for it.
build_staging() { # [expected user]
    wipe
    mkdir -p $shared/evidence $T7_STUB_MARKS $tmp/backup
    stub $shared/Ice.app/Contents/MacOS/Ice 'print -r -- "$*" >> $T7_STUB_MARKS/ice
print -u2 "2026-10-05 10:00:00.100000+0900 Ice[1:1] [Permissions] Passed all permissions checks"
trap "exit 0" TERM
sleep 1
print -u2 "2026-10-05 10:00:01.000000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: checking"
print -u2 "2026-10-05 10:00:09.500000+0900 Ice[1:1] [IceBarHiding] IceBar hiding: active"
: > $T7_STUB_MARKS/ice-active
sleep 1000 &
wait'
    local helper='print -r -- "$*" >> $T7_STUB_MARKS/vzhelper
print "up {\"pid\":1}"
[[ "$*" == *--menu* ]] && print "menu {\"event\":\"open\"}"
while read -r line; do print -r -- "$line" >> $T7_STUB_MARKS/vzhelper-stdin; done'
    stub $shared/apps/Target.app/Contents/MacOS/vzhelper $helper
    stub $shared/apps/Menus.app/Contents/MacOS/vzhelper $helper
    stub $shared/apps/icewatch 'print -r -- "$*" >> $T7_STUB_MARKS/icewatch
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
[[ $(cat $T7_STUB_MARKS/icewatch 2>/dev/null) == preflight ]]; expect "dry run calls icewatch with preflight only"
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
answer_when_active $tmp/answers y 60 10 1 y 10 n
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

# --- phase 4: the menus helper, a new item ------------------------------------------
build_staging
# ready, row 5 (shown, no longMenu in the stub's log: Enter skips the retry, no
# IceBar), row 6, row 7 (Enter, two answers), row 8, row 9.
answer_when_active $tmp/answers y y '' y y 20 '' y y y y y y
run $tmp/answers --phase 4; expect "phase 4 runs to the end"
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
