#!/bin/zsh
# Kept in the repo so a later session can rerun it; usage: zsh phase0.sh <evidence dir>. Tested 2026-09-24 (PASS twice).
# Phase 0 of docs/plans/2026-09-24-ice-first-run.md: gates and snapshots,
# read-only, then the two log streams. Prints a summary with counts and
# verdicts only (no app names); everything else goes to $E.
set -u
E=$1
APP=/private/tmp/claude-501/ice-main-build3/Build/Products/Debug/Ice.app
IW=/private/tmp/claude-501/icewatch-build/out/Products/Debug/icewatch
MBD=/private/tmp/claude-501/mbdiscovery-rel/out/Products/Release/mbdiscover
mkdir -p $E/before $E/captures
fail=0
note() { print -r -- "$1"; print -r -- "$1" >> $E/phase0-summary.txt; }

# --- gates ---
ice_running=$(ps -axo comm= | grep -c -E '/Ice\.app/Contents/(MacOS|XPCServices)/' )
note "gate ice-processes-running=$ice_running (want 0)"; [ $ice_running -eq 0 ] || fail=1
managers=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var ids=["com.surteesstudios.Bartender","com.dwarvesv.minimalbar","com.superoutman.ShiftBar","com.superoutman.ShiftBar.prototype","com.matthewpalmer.Vanilla","net.matthewpalmer.Vanilla","com.theronhaegerty.dozer","com.jordanbaird.Ice"]; var n=0; var apps=$.NSWorkspace.sharedWorkspace.runningApplications; for (var i=0;i<apps.count;i++){var b=apps.objectAtIndex(i).bundleIdentifier; if(b && ids.indexOf(ObjC.unwrap(b))>=0) n++;} n' 2>/dev/null)
note "gate other-menu-bar-managers-running=$managers (want 0)"; [ "$managers" = "0" ] || fail=1
pre=$($IW preflight); print -r -- "$pre" > $E/before/preflight.json
note "gate preflight=$pre"; print -r -- "$pre" | grep -q '"axTrusted":true' || fail=1
$MBD --census-json > $E/before/census.json 2> $E/before/census-stderr.txt
python3 - $E/before/census.json <<'PY' >> $E/phase0-gates.txt
import json,sys
data=json.load(open(sys.argv[1]))
reads=data if isinstance(data,list) else data.get('reads',data.get('processes',[]))
agent=[];items=[]
for r in reads:
    owner=(r['process'].get('bundleID') or '')
    for c in r.get('records',[]):
        f=(c.get('frame') or {}).get('value')
        if not f: continue
        x,y,w=f['minX'],f['minY'],f['width']
        if not (0<=y<33): continue
        if owner!='com.apple.MenuBarAgent' and (c.get('role') or {}).get('value')!='AXMenuBarItem': continue
        (agent if owner=='com.apple.MenuBarAgent' else items).append((x,w))
left=min([x for x,w in items], default=None)
chev=[a for a in agent if abs(a[1]-17.5)<=0.5]
pill=[a for a in agent if abs(a[1]-16)<=0.5 and left is not None and a[0]<left]
room=(left-956.5) if left is not None else -1
print(f"items_on_bar={len(items)} agent_on_bar={len(agent)} chevron={len(chev)} pill={len(pill)} free_room_pt={room:.1f}")
PY
g=$(tail -1 $E/phase0-gates.txt); note "gate census: $g"
print -r -- "$g" | grep -q 'chevron=0 pill=0' || fail=1
room=$(print -r -- "$g" | sed -E 's/.*free_room_pt=([-0-9.]+).*/\1/'); python3 -c "import sys; sys.exit(0 if float('$room')>=120 else 1)" || { note "gate free-room < 120"; fail=1; }

# --- snapshots (read-only) ---
/usr/sbin/screencapture -x -t png -R 0,0,1728,33 $E/captures/before-strip.png
defaults export com.jordanbaird.Ice $E/before/prefs.plist
plutil -lint $E/before/prefs.plist >/dev/null || { note "prefs export unreadable"; fail=1; }
defaults export com.apple.MenuBarAgent $E/before/menubaragent.plist
defaults read com.apple.controlcenter 2>/dev/null | grep 'NSStatusItem' > $E/before/controlcenter.txt
defaults -currentHost read com.apple.controlcenter 2>/dev/null | grep 'NSStatusItem' > $E/before/controlcenter-host.txt
{ defaults -currentHost read -globalDomain NSStatusItemSpacing; defaults -currentHost read -globalDomain NSStatusItemSelectionPadding; } > $E/before/spacing.txt 2>&1
python3 - $E/before/census.json $E/before/app-statusitem-keys.txt <<'PY'
import json,sys,os,subprocess
data=json.load(open(sys.argv[1])); reads=data if isinstance(data,list) else data.get('reads',data.get('processes',[]))
out=open(sys.argv[2],'w')
for r in reads:
    b=r['process'].get('bundleID')
    if not b or b=='com.apple.MenuBarAgent' or not r.get('records'): continue
    if not os.path.exists(os.path.expanduser(f'~/Library/Preferences/{b}.plist')): continue
    try: txt=subprocess.run(['defaults','read',b],capture_output=True,text=True,timeout=10).stdout
    except Exception: continue
    for line in txt.splitlines():
        if 'NSStatusItem' in line: out.write(f"{b}\t{line.strip()}\n")
PY
defaults read com.apple.dock recent-apps 2>/dev/null | grep -E 'bundle-identifier|_CFURLString"' > $E/before/dock-recents.txt
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump 2>/dev/null | awk '/^-{10,}/{if(rec ~ /identifier: +com\.jordanbaird\.Ice\n/) print rec; rec=""; next} {rec=rec $0 "\n"}' | grep -E '^(path|identifier|version|reg date):' > $E/before/lsregister.txt
sfltool dumpbtm 2>/dev/null | grep -B3 -A12 'jordanbaird' > $E/before/btm.txt
for d in "$HOME/Library/Saved Application State" "$HOME/Library/Caches/com.jordanbaird.Ice" "$HOME/Library/HTTPStorages/com.jordanbaird.Ice"; do [ -e "$d" ] && print -r -- "exists $d" || print -r -- "absent $d"; done > $E/before/paths.txt
ls "$HOME/Library/Logs/DiagnosticReports" > $E/before/diagnostic-reports.txt 2>/dev/null
note "snapshots: lsregister-records=$(grep -c '^path:' $E/before/lsregister.txt) btm-lines=$(wc -l < $E/before/btm.txt | tr -d ' ') dock-recents=$(grep -c bundle-identifier $E/before/dock-recents.txt) app-statusitem-keys=$(wc -l < $E/before/app-statusitem-keys.txt | tr -d ' ')"

# --- log streams ---
/usr/bin/log stream --level debug --style ndjson --predicate 'processImagePath CONTAINS "ice-main-build3/Build/Products/Debug/Ice.app/"' > $E/ice-log.ndjson 2>&1 &
print $! > $E/ice-log.pid
/usr/bin/log stream --level debug --style ndjson --predicate 'process == "tccd"' > $E/tccd.ndjson 2>&1 &
print $! > $E/tccd-log.pid
for i in {1..20}; do [ -s $E/ice-log.ndjson ] && [ -s $E/tccd.ndjson ] && break; perl -e 'select(undef,undef,undef,0.25)'; done
alive=0; kill -0 $(cat $E/ice-log.pid) 2>/dev/null && [ -s $E/ice-log.ndjson ] && alive=1
note "log-stream alive=$alive"; [ $alive -eq 1 ] || fail=1
note "phase0 verdict: $([ $fail -eq 0 ] && echo PASS || echo FAIL)"
exit $fail
