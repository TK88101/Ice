#!/bin/zsh -f
# T5 of plan 2026-11-15-cover: stages a lab-identity copy of a Debug Ice, runs
# `dualband cover` against it, deletes the copy's defaults, and restores the daily Ice
# if the runner died without doing so.
#   run-cover.sh <Debug Ice.app> <evidence dir>
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
bin=${DUALBAND_BIN:-/private/tmp/claude-501/dualband-scratch/debug/dualband}
src=${1:?usage}; dir=${2:?usage}
mkdir -p $dir
id=com.icespike4.lab.r$(date +%H%M%S).cover
app=$dir/stage/Ice.app
rm -rf $dir/stage && mkdir -p $dir/stage
ditto $src $app || exit 2
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $id" $app/Contents/Info.plist || exit 2
codesign --force --deep --sign - $app 2> $dir/codesign.log || exit 2
defaults write $id UseIceBar -bool true
defaults write $id ShowOnHover -bool false
defaults write $id ShowOnScroll -bool false
defaults write $id EnableAlwaysHiddenSection -bool false
caffeinate -dis -w $$ < /dev/null &
$bin cover $app $dir
rc=$?
defaults delete $id 2> /dev/null
sleep 3
if ! pgrep -f /Applications/Ice.app/Contents/MacOS/Ice > /dev/null; then
    pkill -f "$app/Contents/MacOS/Ice" 2> /dev/null
    sleep 2
    [[ -f $dir/prefs-before.plist ]] && defaults import io.github.tk88101.Ice $dir/prefs-before.plist
    open /Applications/Ice.app
    print -- "run-cover: restored the daily Ice by the wrapper (status $rc)"
fi
exit $rc
