#!/bin/zsh -f
# T10 of plan 2026-11-15-blind-at-length: stages a lab-identity copy of a Debug Ice and
# the popover helper's bundle, runs `dualband blind` against them, and deletes the copy's
# defaults. The daily Ice is quit and relaunched by the runner only if it was running;
# if the runner died after quitting it, this script relaunches it.
#   run-blind.sh <Debug Ice.app> <new evidence dir>
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
bin=${DUALBAND_BIN:-/private/tmp/claude-501/dualband-scratch/debug/dualband}
src=${1:?usage}; dir=${2:?usage}
if [[ -e $dir/blind-results.txt ]]; then
    print -- "run-blind: $dir holds an earlier run; give a new evidence dir"
    exit 2
fi
mkdir -p $dir
id=com.icespike4.lab.r$(date +%H%M%S).blind
app=$dir/stage/Ice.app
popover=$dir/stage/Popover.app
rm -rf $dir/stage && mkdir -p $dir/stage $popover/Contents/MacOS
ditto $src $app || exit 2
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $id" $app/Contents/Info.plist || exit 2
codesign --force --deep --sign - $app 2> $dir/codesign.log || exit 2
# The popover helper under the protected helper's bundle id (no new entry in the menu bar settings).
cp $bin $popover/Contents/MacOS/dualband || exit 2
cat > $popover/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.icespike4.protected</string>
    <key>CFBundleName</key><string>Popover</string>
    <key>CFBundleExecutable</key><string>dualband</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - $popover 2>> $dir/codesign.log || exit 2
defaults write $id UseIceBar -bool true
defaults write $id ShowOnHover -bool false
defaults write $id ShowOnScroll -bool false
defaults write $id EnableAlwaysHiddenSection -bool false
daily_was_running=0
pgrep -f /Applications/Ice.app/Contents/MacOS/Ice > /dev/null && daily_was_running=1
caffeinate -dis -w $$ < /dev/null &

restore() {
    defaults delete $id 2> /dev/null
    sleep 3
    (( daily_was_running )) || return
    if ! pgrep -f /Applications/Ice.app/Contents/MacOS/Ice > /dev/null; then
        pkill -f "$app/Contents/MacOS/Ice" 2> /dev/null
        sleep 2
        [[ -f $dir/prefs-before.plist ]] && defaults import io.github.tk88101.Ice $dir/prefs-before.plist
        open /Applications/Ice.app
        print -- "run-blind: relaunched the daily Ice by the wrapper (status $1)"
    fi
}

$bin blind $app $popover $dir &
runner=$!
trap 'kill $runner 2> /dev/null; wait $runner 2> /dev/null; restore signalled; exit 130' INT TERM HUP
wait $runner
rc=$?
trap - INT TERM HUP
restore $rc
exit $rc
