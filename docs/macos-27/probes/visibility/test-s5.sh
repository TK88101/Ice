#!/bin/zsh
# Tests of the owner's acceptance sitting's scripts (plan
# 2026-11-12-s5-owner-acceptance): s5-tool.py's unit tests, and run-s5.sh
# against stub binaries in a throwaway staging directory outside ~/Documents,
# the owner's answers fed from a file. Nothing real is launched: Ice, vzhelper
# and icewatch are stubs. Side effects: the stub Ice copies' defaults domains
# (com.icespike4.lab.r*.s5), the helper's (com.icespike4.target) and a
# stand-in for the release's (com.icespike4.lab.s5test-release), all deleted;
# MenuBarAgent's store and the display list are read, never written.
set -uo pipefail
here=${0:A:h}
tmp=/private/tmp/claude-501/s5-test-$$
mkdir -p -m 700 $tmp
failures=0
release=com.icespike4.lab.s5test-release

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { # <label>: the last command's status decides
    if (( $? == 0 )); then ok $1; else fail $1; [[ -f $tmp/out.txt ]] && tail -25 $tmp/out.txt; fi
}
cleanup() {
    pkill -f "$tmp/" 2>/dev/null
    defaults delete $release >/dev/null 2>&1
    chmod -R u+w $tmp 2>/dev/null
    rm -rf $tmp
}
trap cleanup EXIT

python3 -I $here/test_s5_tool.py > $tmp/out.txt 2>&1
check "s5-tool.py unit tests ($(grep -o 'Ran [0-9]* tests' $tmp/out.txt))"

# --- the stub staging --------------------------------------------------------------

shared=$tmp/shared
marks=$tmp/marks
evidence=$tmp/evidence
export LAB_STUB_MARKS=$marks LAB_STUB_FIXTURE=$tmp/fixture.jsonl LAB_STUB_EVIDENCE=$evidence LAB_STUB_RELEASE=$release

stub() { # <path> <body>
    mkdir -p ${1:h}
    print -r -- "#!/bin/zsh"$'\n'"$2" > $1
    chmod 0755 $1
}

# The stub Ice: writes its report from the fixture, numbering the lines (one
# second of the report's clock a line); `@H@` is the helper the stub helper
# registered. {"waitHelper":1} waits for it; {"waitStep":"<text>"} waits until
# the runner's steps hold that text; {"writeRelease":1} changes the stand-in
# for the release's settings. Then it stays until TERM.
ice_body='
id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" ${0:h:h}/Info.plist)
print -r -- "$id $*" >> $LAB_STUB_MARKS/ice
trap "exit 0" TERM
seq=0
emit() { seq=$((seq + 1)); print -r -- "${1%\}},\"seq\":$seq,\"t\":$seq}"; }
emit "{\"event\":\"start\",\"marker\":\"IceLabReport-start-v1\",\"pid\":$$,\"bundleID\":\"$id\",\"holdLength\":false}"
while IFS= read -r line; do
    case $line in
        "{\"waitHelper\":"*)
            for _ in {1..200}; do [[ -s $LAB_STUB_MARKS/members ]] && break; sleep 0.05; done
            continue ;;
        "{\"waitStep\":"*)
            want=$(/usr/bin/python3 -I -c "import json,sys; print(json.loads(sys.argv[1])[\"waitStep\"])" "$line")
            for _ in {1..400}; do grep -qF -- "$want" $LAB_STUB_EVIDENCE/*/steps.jsonl 2>/dev/null && break; sleep 0.05; done
            continue ;;
        "{\"writeRelease\":"*) defaults write $LAB_STUB_RELEASE changed -bool true; continue ;;
    esac
    line=${line//@H@/$(head -1 $LAB_STUB_MARKS/members 2>/dev/null)}
    emit "${line//@ICE@/$id}"
done < $LAB_STUB_FIXTURE
exec sleep 1000'

helper_body='
id=none
for (( i = 1; i < $#; i++ )); do [[ ${@[i]} == --identifiers ]] && id=${@[i+1]}; done
print -r -- $id >> $LAB_STUB_MARKS/members
print "up {\"pid\":$$}"
while IFS= read -r command; do :; done'

icewatch_body='
case $1 in
    preflight) print "{\"axTrusted\":${LAB_STUB_AX:-true},\"pid\":1,\"screenCapture\":true}" ;;
    menu-frame) print "{\"barHeight\":33,\"displayWidth\":1728,\"menuMaxX\":300,\"notchMinX\":700,\"verdict\":\"fits\"}" ;;
    chevron) print "{\"listed\":false}"; exit 1 ;;
esac'

build_staging() { # [key=value lines for s5.env]
    chmod -R u+w $tmp 2>/dev/null
    rm -rf $shared $marks $evidence
    mkdir -p $shared $marks
    defaults delete $release >/dev/null 2>&1
    defaults write $release kept -bool true
    stub $shared/Ice.app/Contents/MacOS/Ice $ice_body
    cat > $shared/Ice.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.jordanbaird.Ice</string>
<key>CFBundleExecutable</key><string>Ice</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
    stub $shared/apps/Target.app/Contents/MacOS/vzhelper $helper_body
    stub $shared/apps/icewatch $icewatch_body
    cp $here/run-s5.sh $here/s5-tool.py $here/lab-tool.py $shared/
    source $here/t7-lib.zsh
    print -l -- "EXPECT_USER=icetest" "OWNER_USER=$(id -un)" "GIT_REV=test" \
        "ICE_SHA=$(t7_sha_tree $shared/Ice.app)" \
        "TARGET_SHA=$(t7_sha $shared/apps/Target.app/Contents/MacOS/vzhelper)" \
        "PROTECTED_SHA=0" "MENUS_SHA=0" \
        "ICEWATCH_SHA=$(t7_sha $shared/apps/icewatch)" "TOOL_SHA=$(t7_sha $shared/lab-tool.py)" \
        "HIDE_LIMIT=150" "START_LIMIT=5" "TIME_SCALE=0.02" > $shared/lab.env
    print -l -- "S5_SHA=$(t7_sha $shared/run-s5.sh)" "S5TOOL_SHA=$(t7_sha $shared/s5-tool.py)" \
        "START_WAIT=150" "OWNER_WAIT=150" "EVIDENCE_ROOT=$evidence" "RELEASE_DOMAIN=$release" "$@" > $shared/s5.env
}

# The report of a sitting that passes, bent by the arguments: `left` (an item
# of the owner's left of the divider at the start), `unverified` (the helper
# never verified), `release` (the release's settings written while Ice runs).
fixture() {
    python3 -I - $here "$@" > $LAB_STUB_FIXTURE <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("t", sys.argv[1] + "/test_lab_tool.py")
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)
bend = set(sys.argv[2:])
H = {"namespace": "com.icespike4.target", "identifier": "@H@"}
OWN = {"namespace": "com.example.app", "identifier": "Item-0"}
BAR = [{"namespace": "com.example.a", "identifier": "x"}, OWN]
ICE = {"namespace": "@ICE@", "identifier": "Ice.ControlItem.Visible"}

def member(key):
    return dict(key, pid=41, condition="ready", pressable=True, frame=[900, 4, 14, 22])

def emit(event, **fields):
    print(json.dumps(dict(fields, event=event)))

def rest(members, visible, **fields):
    values = dict(phase="resting", status="verified", lengthSet=True, lengthApplied=True, calibratedHiddenLength=736, isIceBarOffered=True,
                  roster=[member(m) for m in members], cells=[dict(m, disabled=False) for m in members],
                  checks=[dict(m, outcome="hidden") for m in members], cacheHidden=members, cacheVisible=visible + [ICE])
    values.update(fields)
    emit("snapshot", **t.snapshot(**values))

def wait(text):
    print(json.dumps({"waitStep": text}))

emit("snapshot", **t.snapshot(cacheVisible=BAR + [ICE], cacheHidden=[OWN] if "left" in bend else []))
print(json.dumps({"waitHelper": 1}))
if "release" in bend:
    print(json.dumps({"writeRelease": 1}))
emit("snapshot", **t.snapshot(roster=[member(H)], cacheHidden=[H], cacheVisible=BAR + [ICE]))
emit("length", applied=736, decided=736, held=False)
if "unverified" in bend:
    emit("status", status="notVerified(noReference)")
    sys.exit(0)
emit("status", status="verified")
rest([H], BAR)
rest([H], BAR, isIceBarPresented=True)
others = [BAR[0]]
wait('"q":"doOwn","a":"y"')
emit("snapshot", **t.snapshot(roster=[member(H), member(OWN)], cacheHidden=[H, OWN], cacheVisible=others + [ICE]))
wait('"step":"ownSeen"')
emit("status", status="notVerified(lengthNotApplied)")
emit("status", status="verified")
rest([H, OWN], others)
rest([H, OWN], others, isIceBarPresented=True)
wait('"q":"doInvert","a":"y"')
emit("length", applied=None, decided=None, held=False)
emit("status", status="blocked(iconLeftOfDivider)")
emit("snapshot", **t.snapshot(status="blocked(iconLeftOfDivider)", iconPlacement="iconLeftOfDivider", roster=[member(H)], cacheVisible=BAR + [ICE]))
wait('"q":"paneSays"')
emit("length", applied=736, decided=736, held=False)
emit("status", status="verified")
rest([H], BAR)
wait('"q":"itemBack"')
rest([H], BAR, **{"pass": 3})
PY
}

answers() { print -l -- "$@" > $tmp/answers.txt; }
sitting() { zsh $shared/run-s5.sh < $tmp/answers.txt > $tmp/out.txt 2>&1; }
run_dir() { print $evidence/*-s5(N/[1]); }
ours_running() { pgrep -f "$tmp/" >/dev/null; }
# An emptied domain still reads, as `{}` (run-s5.sh's own check).
domain_empty() { [[ $(defaults export $1 - 2>/dev/null | plutil -p - 2>/dev/null) == $'{\n}' ]]; }
clean_after() {
    local domain
    ! ours_running && [[ $(defaults read $release kept 2>/dev/null) == 1 ]] || return 1
    for domain in com.icespike4.target $(awk '{print $1}' $marks/ice 2>/dev/null); do domain_empty $domain || return 1; done
}

# --- guards --------------------------------------------------------------------------

build_staging
zsh $shared/run-s5.sh --dry-run > $tmp/out.txt 2>&1 && grep -q 'nothing was started' $tmp/out.txt && [[ ! -e $evidence && ! -f $marks/ice ]]
check "the dry run passes its guards and starts and writes nothing"

build_staging
sed -i '' -e "s/^OWNER_USER=.*/OWNER_USER=nobodyhere/" $shared/lab.env
zsh $shared/run-s5.sh > $tmp/out.txt 2>&1 < /dev/null; (( $? == 2 )) && grep -q 'not nobodyhere' $tmp/out.txt && [[ ! -e $evidence ]]
check "another account than the owner's is refused before anything is created"

build_staging
print '# changed' >> $shared/s5-tool.py
zsh $shared/run-s5.sh > $tmp/out.txt 2>&1 < /dev/null; (( $? == 2 )) && grep -q 's5-tool is not the staged file' $tmp/out.txt
check "a changed staged file is refused"

build_staging
chmod go+w $shared/s5.env
zsh $shared/run-s5.sh > $tmp/out.txt 2>&1 < /dev/null; (( $? == 2 )) && grep -q 's5.env is a link, not .* or writable by others' $tmp/out.txt && [[ ! -e $evidence ]]
check "a staged file others can write is refused"

build_staging
mkdir $tmp/elsewhere && mv $shared/apps $tmp/elsewhere/apps && ln -s $tmp/elsewhere/apps $shared/apps
zsh $shared/run-s5.sh > $tmp/out.txt 2>&1 < /dev/null; (( $? == 2 )) && grep -q 'apps is a link' $tmp/out.txt
check "a staging directory that is a link is refused"

build_staging "EVIL=1"
zsh $shared/run-s5.sh > $tmp/out.txt 2>&1 < /dev/null; (( $? == 2 )) && grep -q 'does not know' $tmp/out.txt
check "an unknown s5.env line is refused"

build_staging
rm $shared/s5.env
zsh $shared/run-s5.sh > $tmp/out.txt 2>&1 < /dev/null; (( $? == 2 )) && grep -q 's5.env is missing' $tmp/out.txt
check "a staging without s5.env is refused"

build_staging
LAB_STUB_AX=false zsh $shared/run-s5.sh > $tmp/out.txt 2>&1 < /dev/null; (( $? == 2 )) && grep -q 'lacks Accessibility' $tmp/out.txt && [[ ! -e $evidence ]]
check "missing Accessibility is refused, and it says the grant is Terminal's"

zsh $shared/run-s5.sh nosuch > $tmp/out.txt 2>&1; (( $? == 64 ))
check "an unknown argument is refused"

# --- the sitting ------------------------------------------------------------------------

build_staging
fixture
answers "" y y y "my item" y y y y y y
sitting; code=$?
run=$(run_dir)
(( code == 0 )) && grep -q 'S5 結果：通過' $tmp/out.txt && [[ $(< $run/verdict.json) == *'"result": "pass"'* ]]
check "a sitting where Ice and the owner both say yes passes"
[[ $(stat -f %Lp $run) == 700 && ! -e $run/stage && -s $run/prefs-before.plist && -s $run/store-before.json && -s $run/report.txt ]]
check "its evidence is private, holds both exports and the report, and the staged copy is gone"
grep -q -- '-IceLabReport YES' $marks/ice && grep -q 'com.icespike4.lab.r.*\.s5 ' $marks/ice
check "Ice ran as a copy of its own lab identity with the report on"
clean_after
check "nothing of the sitting is left running, its domains are empty and the release's settings are as they were"
grep -q '"step":"ownName".*"name":"my item"' $run/steps.jsonl && grep -q '"member":{"identifier": "Item-0"' $run/steps.jsonl
check "the owner's name for the item and the member Ice saw are in the evidence"

build_staging
fixture
answers "" y y s s
sitting; code=$?
(( code == 1 )) && grep -q 'S5 結果：部分通過' $tmp/out.txt && grep -q 'helper only' $tmp/out.txt && grep -q 'C5 skipped  C6 skipped' $tmp/out.txt
check "skipping the own item and the icon drag is partial, and says helper only"

build_staging
fixture
answers "" y n s s
sitting; code=$?
(( code == 1 )) && grep -q 'S5 結果：沒通過' $tmp/out.txt && grep -q 'C4: the owner answered n to helperMenu' $tmp/out.txt
check "a no from the owner fails, with the question named"

build_staging
fixture
answers "" x y y s s
sitting
grep -q '請輸入 y、n 或 s' $tmp/out.txt && grep -q 'S5 結果：部分通過' $tmp/out.txt
check "an answer that is not y, n or s is asked again"

build_staging
fixture left
answers ""
sitting; code=$?
(( code == 1 )) && grep -q 'S5 結果：沒法開始' $tmp/out.txt && grep -q "left of the hidden divider" $tmp/out.txt && [[ ! -s $marks/members ]]
check "an item of the owner's left of the divider at the start ends the sitting before the helper starts"
clean_after
check "and it is cleaned up as any other"

build_staging
fixture unverified
answers ""
sitting; code=$?
(( code == 1 )) && grep -q 'S5 結果：沒通過' $tmp/out.txt && grep -q 'wait for verified ran out (last status: notVerified(noReference))' $tmp/out.txt && ! grep -q '第 1 步' $tmp/out.txt
check "a helper that stays unverified fails with its status, and the owner is asked nothing"

build_staging
fixture release
answers "" y y s s
sitting; code=$?
run=$(run_dir)
(( code == 1 )) && grep -q "the release Ice's settings changed" $tmp/out.txt && grep -q "defaults import $release $run/prefs-before.plist" $tmp/out.txt
check "changed release settings fail the sitting and the restore command is printed"

build_staging
fixture
answers "" y
sitting; code=$?
(( code == 1 )) && grep -q 'the sitting ended early: no answer to helperMenu' $tmp/out.txt && clean_after
check "input that ends early ends the sitting as cut short, cleaned up"

build_staging
fixture
mkfifo $tmp/answers.fifo
zsh $shared/run-s5.sh < $tmp/answers.fifo > $tmp/out.txt 2>&1 &
runner=$!
exec {feed}> $tmp/answers.fifo
print -u $feed ""
for _ in {1..200}; do grep -q '第 1 步' $tmp/out.txt && break; sleep 0.05; done
kill -TERM $runner
wait $runner; code=$?
exec {feed}>&-
(( code == 1 )) && grep -q 'the sitting ended early: terminated' $tmp/out.txt && clean_after
check "a TERM in the middle stops Ice and the helper, deletes the domains and prints the verdict"

echo
if (( failures )); then echo "$failures FAILED"; exit 1; fi
echo "all passed"
