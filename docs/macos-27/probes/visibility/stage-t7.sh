#!/bin/zsh
# IceBar build plan T7 (docs/plans/2026-10-03-icebar-build.md section 10.2): run
# in the OWNER's account before the owner's sitting, as stage-spike.sh was for
# T0. Builds the probes (U24 first) and Ice outside ~/Documents (iCloud xattrs
# break codesign), copies them to /Users/Shared/IceReverse-t7 (its own
# directory; the route C and T0 stagings are left as they are), records what
# was staged, exports the owner's own Ice preferences, and runs the dry check.
# Starts neither Ice nor a helper.
#
#   ./stage-t7.sh <isolated-account-name> [scratch-dir]
set -euo pipefail
isolated=${1:?usage: stage-t7.sh <isolated-account-name> [scratch-dir]}
scratch=${2:-/private/tmp/claude-501/t7-live}
owner=$(id -un)
[[ $isolated != $owner ]] || { echo "stage-t7: the isolated account must not be $owner" >&2; exit 2; }

here=${0:A:h}
repo=$(git -C "$here" rev-parse --show-toplevel)
source "$here/t7-lib.zsh"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
running_before=$(t7_count_ours -ax)

# What is built here is later run as the owner (the dry check).
t7_private_directory "$scratch"
"$here/build.sh" "$scratch"
bin=$(swift build -c release --package-path "$here" --scratch-path "$scratch/build" --show-bin-path)
if ! xcodebuild -project "$repo/Ice.xcodeproj" -scheme Ice -configuration Debug CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$scratch/ice-dd" build > "$scratch/xcodebuild.log" 2>&1; then
    tail -30 "$scratch/xcodebuild.log" >&2
    echo "stage-t7: Ice did not build ($scratch/xcodebuild.log)" >&2
    exit 1
fi
ice_app=$scratch/ice-dd/Build/Products/Debug/Ice.app
# Into a variable first: under pipefail a `grep -q` that stops reading early
# fails the pipeline.
signature=$(codesign -dv "$ice_app" 2>&1)
[[ $signature == *adhoc* ]] || { echo "stage-t7: the Ice build is not ad-hoc signed" >&2; exit 1; }

shared=/Users/Shared/IceReverse-t7
# /Users/Shared is world-writable: everything below is done as the owner, so
# refuse a staging directory (or a child of it) that is a symlink or that the
# owner does not own (another account could have created it first).
[[ -e $shared || -L $shared ]] || mkdir -m 755 $shared
[[ -e $shared/evidence || -L $shared/evidence ]] || mkdir $shared/evidence
for dir in $shared $shared/evidence ${shared}/apps(N) ${shared}/Ice.app(N); do
    [[ -d $dir && ! -L $dir && -O $dir ]] || { echo "stage-t7: $dir is a symlink or not owned by $owner" >&2; exit 1; }
done
chmod 0755 $shared
# Writable by the isolated account; sticky, so only a run directory's creator
# can rename or remove it.
chmod 1777 $shared/evidence
# Replace only the previous staged copy of the tools, never evidence.
/bin/rm -rf $shared/apps $shared/Ice.app
ditto "$scratch/apps" $shared/apps
cp "$bin/icewatch" $shared/apps/icewatch
ditto "$ice_app" $shared/Ice.app
cp "$here/run-t7.sh" "$here/t7-lib.zsh" $shared/
chmod 0755 $shared/run-t7.sh
chmod 0644 $shared/t7-lib.zsh
chmod -R go-w $shared/apps $shared/Ice.app

revision=$(git -C "$repo" rev-parse --short HEAD)
[[ -z $(git -C "$repo" status --porcelain --untracked-files=no) ]] || revision+=-dirty
t7_write_env $shared $isolated $owner $revision com.jordanbaird.Ice com.icespike4.target,com.icespike4.protected
chmod 0644 $shared/t7.env

# The staged copy has the release's bundle id and a higher build number: it
# must not be what LaunchServices resolves the id to (plan 10.7 R9).
staged_records() { $lsregister -dump 2>/dev/null | grep -c "^path: *$shared/Ice.app" || true; }
if (( $(staged_records) > 0 )); then
    $lsregister -u $shared/Ice.app
    (( $(staged_records) == 0 )) || { echo "stage-t7: LaunchServices still lists $shared/Ice.app" >&2; exit 1; }
fi

# The owner's own Ice preferences: a run in the isolated account does not
# write them (a per-user domain), exported so that can be checked afterwards.
# Private: the isolated account is in the owner's group.
record=$HOME/IceReverse-evidence/$(date +%Y%m%d-%H%M%S)-t7-stage
mkdir -p "${record:h}"
mkdir -m 700 "$record"
(umask 077; t7_prefs_export com.jordanbaird.Ice "$record/prefs-owner.plist"; cp $shared/t7.env "$record/t7.env")

echo "stage-t7: staged $revision for $isolated in $shared; the owner's preferences are in $record"
/bin/zsh $shared/run-t7.sh --dry-run
running_after=$(t7_count_ours -ax)
[[ $running_before == $running_after ]] || { echo "stage-t7: Ice or helper processes changed during staging ($running_before -> $running_after)" >&2; exit 1; }
echo "stage-t7: done; Ice and helper processes before and after: $running_before"
