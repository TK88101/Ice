#!/bin/zsh
# Tests of the lab matrix's scripts (plan 2026-10-07-icebar-preference-hiding,
# S4 design): lab-tool.py's unit tests, its snapshot keys against IceCore's,
# and run-lab.sh against stub binaries in a throwaway staging directory
# outside ~/Documents. Nothing real is launched: Ice, vzhelper and icewatch are
# stubs. Side effects: the stub Ice copies' defaults domains
# (com.icespike4.lab.r*) and the helpers' (com.icespike4.target, .protected),
# all of which run-lab.sh deletes and verifies empty, as it does in the lab.
set -uo pipefail
here=${0:A:h}
repo=$(git -C $here rev-parse --show-toplevel)
tmp=/private/tmp/claude-501/lab-test-$$
mkdir -p -m 700 $tmp
failures=0

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { # <label>: the last command's status decides
    if (( $? == 0 )); then ok $1; else fail $1; [[ -f $tmp/out.txt ]] && tail -20 $tmp/out.txt; fi
}
cleanup() {
    pkill -f "$tmp/" 2>/dev/null
    chmod -R u+w $tmp 2>/dev/null
    rm -rf $tmp
}
trap cleanup EXIT

# --- the tool --------------------------------------------------------------------

python3 -I $here/test_lab_tool.py > $tmp/out.txt 2>&1
check "lab-tool.py unit tests ($(grep -o 'Ran [0-9]* tests' $tmp/out.txt))"

swift_keys=$(sed -n '/public static let keys = \[/,/\]/p' $repo/Packages/IceCore/Sources/IceCore/LabReport.swift | grep -o '"[A-Za-z]*"' | tr -d '"' | tr '\n' ' ')
tool_keys=$(python3 -I -c 'import importlib.util,sys; s=importlib.util.spec_from_file_location("t",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(" ".join(m.SNAPSHOT_KEYS))' $here/lab-tool.py)
[[ -n $swift_keys && ${swift_keys% } == $tool_keys ]]
check "the tool's snapshot keys are IceCore's LabReportSnapshot.keys"

# --- the stub staging --------------------------------------------------------------

shared=$tmp/shared
marks=$tmp/marks
export LAB_STUB_MARKS=$marks LAB_STUB_FIXTURES=$tmp/fixtures

stub() { # <path> <body>
    mkdir -p ${1:h}
    print -r -- "#!/bin/zsh"$'\n'"$2" > $1
    chmod 0755 $1
}
plist() { # <app> <bundle id> <executable>
    cat > $1/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleExecutable</key><string>$3</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
}

# The stub Ice: writes its report from fixtures/<scenario>.jsonl (the
# scenario is its bundle id's last part), numbering the lines; `@M<n>@` is the
# n-th member the stub helpers registered; {"waitMembers": n} waits for them;
# {"sleep": s} waits. Then it stays until TERM.
ice_body='
id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" ${0:h:h}/Info.plist)
scenario=${${id##*.}##[0-9]}
print -r -- "$id $*" >> $LAB_STUB_MARKS/ice
# Each start counts the members started after it.
: > $LAB_STUB_MARKS/members
print -u2 "2026-10-08 10:00:00.100000+0900 Ice[1:1] [Permissions] Passed all permissions checks"
trap "exit 0" TERM
seq=0
emit() { seq=$((seq + 1)); print -r -- "${1%\}},\"seq\":$seq,\"t\":$seq}"; }
emit "{\"event\":\"start\",\"marker\":\"IceLabReport-start-v1\",\"pid\":$$,\"bundleID\":\"$id\",\"holdLength\":false}"
if [[ -f $LAB_STUB_FIXTURES/$scenario.jsonl ]]; then
    while IFS= read -r line; do
        if [[ $line == "{\"waitMembers\":"* ]]; then
            want=${line//[^0-9]/}
            for _ in {1..100}; do (( $(wc -l < $LAB_STUB_MARKS/members 2>/dev/null || print 0) >= want )) && break; sleep 0.05; done
            continue
        fi
        [[ $line == "{\"sleep\":"* ]] && { sleep ${${line#*:}%\}}; continue; }
        n=1
        for member in ${(f)"$(cat $LAB_STUB_MARKS/members 2>/dev/null)"}; do line=${line//@M$n@/$member}; n=$((n + 1)); done
        emit "$line"
    done < $LAB_STUB_FIXTURES/$scenario.jsonl
fi
sleep 1000 &
wait'

# The stub helper: `up`, then its stdin: `selfread`, `stall`, `closemenu`; EOF ends it.
helper_body='
id=none
for (( i = 1; i < $#; i++ )); do [[ ${@[i]} == --identifiers ]] && id=${@[i+1]}; done
# Members only: the references run under the Protected app.
[[ $0 == */Target.app/* ]] && print -r -- ${id%%,*} >> $LAB_STUB_MARKS/members
print "up {\"pid\":$$}"
while IFS= read -r command; do
    case $command in
        selfread) print "selfread {\"children\":[{\"identifier\":\"${id%%,*}\",\"frame\":[900,4,14,22]}]}" ;;
        stall*) print "stalling {}"; sleep 0.2; print "resumed {}" ;;
    esac
done'

icewatch_body='
case $1 in
    preflight) print "{\"axTrusted\":${LAB_STUB_AX:-true},\"pid\":1,\"screenCapture\":true}" ;;
    menu-frame) print "{\"barHeight\":33,\"displayWidth\":1728,\"menuMaxX\":300,\"notchMinX\":700,\"verdict\":\"fits\"}" ;;
    chevron) print "{\"listed\":false}"; exit 1 ;;
    activate) print "{\"frontmost\":true}" ;;
esac'

build_staging() { # [key=value lines for lab.env]
    chmod -R u+w $tmp 2>/dev/null
    rm -rf $shared $marks
    mkdir -p $shared/evidence $marks $LAB_STUB_FIXTURES
    chmod 1777 $shared/evidence
    stub $shared/Ice.app/Contents/MacOS/Ice $ice_body
    plist $shared/Ice.app com.jordanbaird.Ice Ice
    for app in Target Protected Menus; do
        stub $shared/apps/$app.app/Contents/MacOS/vzhelper $helper_body
    done
    stub $shared/apps/icewatch $icewatch_body
    cp $here/run-lab.sh $here/lab-tool.py $shared/
    source $here/t7-lib.zsh
    print -l -- "EXPECT_USER=$(id -un)" "OWNER_USER=$(id -un)" "GIT_REV=test" \
        "ICE_SHA=$(t7_sha_tree $shared/Ice.app)" \
        "TARGET_SHA=$(t7_sha $shared/apps/Target.app/Contents/MacOS/vzhelper)" \
        "PROTECTED_SHA=$(t7_sha $shared/apps/Protected.app/Contents/MacOS/vzhelper)" \
        "MENUS_SHA=$(t7_sha $shared/apps/Menus.app/Contents/MacOS/vzhelper)" \
        "ICEWATCH_SHA=$(t7_sha $shared/apps/icewatch)" "TOOL_SHA=$(t7_sha $shared/lab-tool.py)" \
        "STATUS_LIMIT=4" "START_LIMIT=5" "TIME_SCALE=0.02" "CAPTURE=0" "ROUNDS=1" "$@" > $shared/lab.env
    chmod -R a-w $shared/Ice.app $shared/apps $shared/run-lab.sh $shared/lab-tool.py $shared/lab.env
    chmod a-w $shared
}

# A verified hide of k members, as the real report would carry it.
verified_fixture() { # <scenario> <member count>
    local i roster= cells= checks= hidden= sep=
    for (( i = 1; i <= $2; i++ )); do
        roster+="$sep{\"namespace\":\"com.icespike4.target\",\"identifier\":\"@M$i@\",\"pid\":41,\"condition\":\"ready\",\"pressable\":true,\"frame\":[900,4,14,22]}"
        cells+="$sep{\"namespace\":\"com.icespike4.target\",\"identifier\":\"@M$i@\",\"disabled\":false}"
        checks+="$sep{\"namespace\":\"com.icespike4.target\",\"identifier\":\"@M$i@\",\"outcome\":\"hidden\"}"
        hidden+="$sep{\"namespace\":\"com.icespike4.target\",\"identifier\":\"@M$i@\"}"
        sep=,
    done
    local common='"isIceBarPresented":false,"isInteracting":false,"blockers":[],"cacheVisible":[],"cacheAlwaysHidden":[],"iconPlacement":null,"hiddenBoundaryUsable":true,"icon":{"frame":[1500,0,28,30],"usable":true},"hiddenDivider":{"frame":[880,0,18,30],"usable":true},"alwaysHiddenDivider":null,"completeness":"complete","pass":3,"chevronListed":false'
    print -l -- "{\"waitMembers\":$2}" \
        "{\"event\":\"snapshot\",\"phase\":\"quiet\",\"status\":\"notVerified(lengthNotApplied)\",\"lengthSet\":false,\"lengthApplied\":false,\"calibratedHiddenLength\":null,\"isIceBarOffered\":false,\"roster\":[$roster],\"cells\":[],\"cacheHidden\":[$hidden],\"checks\":[],$common}" \
        '{"event":"length","applied":736,"decided":736,"held":false}' \
        '{"event":"status","status":"verified"}' \
        "{\"event\":\"snapshot\",\"phase\":\"resting\",\"status\":\"verified\",\"lengthSet\":true,\"lengthApplied\":true,\"calibratedHiddenLength\":736,\"isIceBarOffered\":true,\"roster\":[$roster],\"cells\":[$cells],\"cacheHidden\":[$hidden],\"checks\":[$checks],$common}" \
        > $LAB_STUB_FIXTURES/$1.jsonl
}

ours_running() { pgrep -f "$tmp/" >/dev/null; }

# --- guards --------------------------------------------------------------------------

build_staging
zsh $shared/run-lab.sh --dry-run > $tmp/out.txt 2>&1 && grep -q 'nothing was started' $tmp/out.txt && [[ -z $(ls $shared/evidence) && ! -f $marks/ice ]]
check "the dry run passes its guards and starts and writes nothing"

build_staging "EXPECT_USER=nobodyhere"
zsh $shared/run-lab.sh sparse > $tmp/out.txt 2>&1; code=$?
(( code == 2 )) && [[ -z $(ls $shared/evidence) ]] && grep -q 'not nobodyhere' $tmp/out.txt
check "another account is refused before anything is created"

build_staging
chmod u+w $shared $shared/lab-tool.py; print '# changed' >> $shared/lab-tool.py; chmod a-w $shared/lab-tool.py $shared
zsh $shared/run-lab.sh sparse > $tmp/out.txt 2>&1; code=$?
(( code == 2 )) && grep -q 'lab-tool is not the staged file' $tmp/out.txt
check "a changed staged file is refused"

build_staging
chmod u+w $shared $shared/lab.env; print 'EVIL=1' >> $shared/lab.env; chmod a-w $shared/lab.env $shared
zsh $shared/run-lab.sh sparse > $tmp/out.txt 2>&1; (( $? == 2 )) && grep -q 'does not know' $tmp/out.txt
check "an unknown lab.env line is refused"

build_staging
LAB_STUB_AX=false zsh $shared/run-lab.sh sparse > $tmp/out.txt 2>&1; (( $? == 2 )) && grep -q 'lacks Accessibility' $tmp/out.txt
check "missing Accessibility is refused"

zsh $shared/run-lab.sh nosuch > $tmp/out.txt 2>&1; (( $? == 64 ))
check "an unknown scenario is refused"

# --- one scenario ------------------------------------------------------------------------

build_staging
verified_fixture sparse 1
zsh $shared/run-lab.sh sparse > $tmp/out.txt 2>&1; code=$?
run=$(print $shared/evidence/*(N/[1]))
(( code == 0 )) && grep -q '1 sparse: pass' $tmp/out.txt && [[ $(< $run/1-sparse/verdict.json) == *'"result": "pass"'* ]]
check "sparse with a verified report passes, judged from Ice's report"
! ours_running
check "no stub process of the run is left"
grep -q 'defaults domains of the run: verified' $tmp/out.txt && ! grep -q 'STILL HAS DEFAULTS' $tmp/out.txt
check "the run's defaults domains are deleted and verified empty"
grep -q -- '-IceLabReport YES' $marks/ice && grep -q 'com.icespike4.lab.r' $marks/ice && [[ -z $(ls $run/stage 2>/dev/null) ]]
check "Ice ran as a staged copy of its own identity with the report on, and the copy is gone"
grep -q '"step":"chevronAtStart"' $run/1-sparse/steps.jsonl
check "the scenario recorded « at its start"

build_staging
verified_fixture sparse 1
sed -i '' -e 's/"status":"verified"/"status":"notVerified(noReference)"/' $LAB_STUB_FIXTURES/sparse.jsonl
zsh $shared/run-lab.sh sparse > $tmp/out.txt 2>&1
grep -q '1 sparse: fail' $tmp/out.txt && ! ours_running
check "a run that never verifies fails after its limit and cleans up"

build_staging
print -r -- 'not json' > $LAB_STUB_FIXTURES/sparse.jsonl
zsh $shared/run-lab.sh sparse > $tmp/out.txt 2>&1
grep -q '1 sparse: aborted' $tmp/out.txt
check "a damaged report is aborted, never a pass"

build_staging
print -l -- '{"sleep":5}' > $LAB_STUB_FIXTURES/sparse.jsonl
zsh $shared/run-lab.sh sparse > $tmp/out.txt 2>&1 &
runner=$!
sleep 2
kill -INT $runner
wait $runner; code=$?
(( code == 130 )) && grep -q '==== lab matrix' $tmp/out.txt && ! ours_running
check "an interrupted run stops Ice and the helpers and prints its report (exit 130)"

# --- the matrix's stop rule --------------------------------------------------------------

build_staging "ROUNDS=3"
verified_fixture sparse 1
zsh $shared/run-lab.sh > $tmp/out.txt 2>&1; cp $tmp/out.txt /private/tmp/claude-501/lab-round-out.txt
run=$(print $shared/evidence/*(N/[1]))
grep -q 'round 1 is not clean' $tmp/out.txt && [[ -z $(print $run/2-*(N)) ]] && grep -q 'S4 DoD: not met' $tmp/out.txt && ! ours_running
check "an unclean round 1 ends the matrix there, with the report saying the DoD is not met"
[[ -z $(print $run/*/judge.err(N.L+0)) ]]
check "no judge failed on any scenario of the round"
for err in $run/*/judge.err(N.L+0); do print -- "--- $err"; tail -5 $err; done
grep -q '1 inverted-moved: notRun' $tmp/out.txt && grep -q '1 noref: ' $tmp/out.txt
check "every scenario of round 1 ran, noref first, scenario 14's second half as notRun"

echo
(( failures == 0 )) && echo "test-lab: all passed" || echo "test-lab: $failures FAILED"
exit $(( failures > 0 ))
