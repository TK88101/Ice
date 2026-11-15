#!/bin/zsh -f
# The T0 sitting of plan 2026-11-15-secondary-display, with a last-resort
# restore: if dualband ends and no daily Ice runs, the exported preferences are
# imported and /Applications/Ice.app is opened by path (G3).
#   run-dualband.sh <Debug Ice.app> <evidence dir> [--resume]
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
bin=${DUALBAND_BIN:-/private/tmp/claude-501/dualband-scratch/debug/dualband}
app=${1:?usage}; dir=${2:?usage}; shift 2
mkdir -p $dir
caffeinate -dis -w $$ < /dev/null &
$bin run $app $dir "$@"
rc=$?
sleep 3
if ! pgrep -f /Applications/Ice.app/Contents/MacOS/Ice > /dev/null; then
    pkill -f "$app/Contents/MacOS/Ice" 2> /dev/null
    sleep 2
    [[ -f $dir/prefs-before.plist ]] && defaults import io.github.tk88101.Ice $dir/prefs-before.plist
    open /Applications/Ice.app
    print -- "run-dualband: restored the daily Ice by the wrapper (status $rc)"
fi
exit $rc
