#!/bin/zsh
# Tests of the settings pass's scripts (plan 2026-11-12-settings-cleanup,
# section 6): the runner's unit tests, the driver's selftest, and one launch
# of the runner against stubs in a throwaway directory outside ~/Documents.
# Nothing real is launched and no input event is posted: Ice, vzhelper and
# settingsdrive are stubs. Side effects: the stub copy's defaults domain
# (com.icespike4.lab.r*.s6), the helpers' (com.icespike4.target/.protected)
# and a stand-in for the release's (com.icespike4.lab.s6test-release), all
# deleted. Refuses while an Ice runs, as the runner does.
#
#   test-settings.sh [<settingsdrive binary>]
set -uo pipefail
here=${0:A:h}
tmp=/private/tmp/claude-501/s6-test-$$
mkdir -p -m 700 $tmp
failures=0
release=com.icespike4.lab.s6test-release
drive=${1:-}

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if (( $? == 0 )); then ok $1; else fail $1; [[ -f $tmp/out.txt ]] && tail -25 $tmp/out.txt; fi; }
cleanup() {
    pkill -f "$tmp/" 2>/dev/null
    defaults delete $release >/dev/null 2>&1
    chmod -R u+w $tmp 2>/dev/null
    rm -rf $tmp
}
trap cleanup EXIT

python3 -I $here/test_settings_lab.py > $tmp/out.txt 2>&1
check "the runner's unit tests"

if [[ -n $drive ]]; then
    $drive selftest > $tmp/out.txt 2>&1
    check "settingsdrive selftest"
fi

# --- one launch against stubs ---------------------------------------------------------------
app=$tmp/build/Ice.app
mkdir -p $app/Contents/MacOS $tmp/shared/apps/Protected.app/Contents/MacOS $tmp/shared/apps/Target.app/Contents/MacOS
cat > $app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.icespike4.lab.s6test-stub</string>
<key>CFBundleExecutable</key><string>Ice</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
# The stub Ice: a start line, then a snapshot a second, until it is told to stop.
cat > $app/Contents/MacOS/Ice <<'STUB'
#!/bin/zsh
trap 'exit 0' TERM
print -r -- '{"event":"start","seq":1,"t":0.0}'
n=1
while true; do
    n=$((n + 1))
    print -r -- "{\"event\":\"snapshot\",\"seq\":$n,\"t\":$n.0,\"lengthApplied\":false,\"isIceBarOffered\":false,\"isIceBarPresented\":false,\"roster\":[],\"hiddenDivider\":{\"frame\":[1054,4.5,18,24]}}"
    sleep 0.3
done
STUB
for helper in Protected Target; do
    cat > $tmp/shared/apps/$helper.app/Contents/MacOS/vzhelper <<'STUB'
#!/bin/zsh
print -r -- 'up {"items":1}'
while read -r line; do [[ $line == quit ]] && exit 0; done
STUB
done
# The stub driver: refuses once for hardware input, then does as asked; a
# press on "empty" at x 5 is refused as not empty.
cat > $tmp/drive <<STUB
#!/bin/zsh
case \$1 in
    idle) print -r -- '{"hardwareIdle":60}' ;;
    gap) print -r -- '{"x":992,"y":12}' ;;
    click)
        if [[ \$2 == 5 ]]; then print -r -- '{"result":"refused","reason":"notEmpty"}'; exit 3; fi
        if [[ ! -e $tmp/refused-once ]]; then : > $tmp/refused-once; print -r -- '{"result":"refused","reason":"hardwareInput"}'; exit 3; fi
        print -r -- '{"result":"done","reason":null,"postedAt":1,"endedAt":2}' ;;
    *) print -r -- '{"result":"done","reason":null}' ;;
esac
STUB
chmod +x $app/Contents/MacOS/Ice $tmp/shared/apps/*/Contents/MacOS/vzhelper $tmp/drive
defaults write $release Marker -string untouched

export S6_SHARED=$tmp/shared S6_EVIDENCE=$tmp/evidence S6_RELEASE_DOMAIN=$release S6_DRIVE=$tmp/drive
cd $here
python3 - $app > $tmp/out.txt 2>&1 <<'PY'
import json, os, subprocess, sys, time
import settings_lab as lab

lab.IDLE_WAIT_SECONDS = 30
state = lab.begin(sys.argv[1])
run = state["run"]
assert lab.is_lab_id(state["ice_id"]), state["ice_id"]
assert state["version"] == "1.0", state["version"]
assert os.path.exists(os.path.join(state["app"], "Contents", "MacOS", state["ice_name"])), "the copy has its own executable name"
with lab.Lab(run, "stub", {"ShowOnHover": True, "RehideInterval": 2.0}, member=False) as launched:
    assert launched.default("ShowOnHover") == "1" and launched.default("UseIceBar") == "1", "the case's settings and the base are stored before launch"
    assert launched.wait(lambda s: s.get("hiddenDivider") is not None, 5, "a snapshot") is not None
    pid = launched.pid
    started = time.time()
    assert launched.click_empty() == 992, "an empty point comes from the driver"
    assert time.time() - started >= 5, "a refusal for hardware input is waited out, then tried again"
    try:
        launched.click_empty(5)
        raise SystemExit("a refused press must not pass")
    except lab.NotRun as error:
        assert "notEmpty" in str(error), error
    assert len(launched.helpers) == 1
assert subprocess.run(["/bin/kill", "-0", str(pid)], capture_output=True).returncode != 0, "the stub Ice was stopped"
steps = [json.loads(line) for line in open(os.path.join(run, "stub", "steps.jsonl"))]
assert [step["result"]["result"] for step in steps] == ["refused", "done", "refused"], steps
result = lab.finish(run)
assert result == {"leftRunning": [], "labDomainEmpty": True, "releaseSettingsUnchanged": True, "spacingKeysPresent": []}, result
assert not os.path.exists(os.path.join(run, "stage")), "the staged copy is removed"
print("stub launch ok")
PY
check "one launch against stubs: settings stored, input refused and retried, everything stopped and removed"
[[ $(defaults read $release Marker 2>/dev/null) == untouched ]]
check "the stand-in for the release's settings is as it was"

echo
(( failures == 0 )) && echo "test-settings: all passed" || echo "test-settings: $failures failed"
exit $(( failures > 0 ))
