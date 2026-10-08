#!/bin/zsh
# The lab matrix's staging (plan 2026-10-07-icebar-preference-hiding, S4
# design D5): run in the OWNER's account before the owner's sitting, as
# stage-t7.sh was for T7. Builds the probes and Ice outside ~/Documents
# (iCloud xattrs break codesign), copies them with run-lab.sh and lab-tool.py
# to /Users/Shared/IceReverse-lab (its own directory; the other stagings are
# left as they are), records their sha256 in lab.env, and runs the dry check.
# Starts neither Ice nor a helper.
#
#   ./stage-lab.sh <isolated-account-name> [scratch-dir]
set -euo pipefail
isolated=${1:?usage: stage-lab.sh <isolated-account-name> [scratch-dir]}
scratch=${2:-/private/tmp/claude-501/lab-live}
owner=$(id -un)
[[ $isolated != $owner ]] || { echo "stage-lab: the isolated account must not be $owner" >&2; exit 2; }

here=${0:A:h}
repo=$(git -C "$here" rev-parse --show-toplevel)
source "$here/t7-lib.zsh"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

t7_private_directory "$scratch"
"$here/build.sh" "$scratch"
bin=$(swift build -c release --package-path "$here" --scratch-path "$scratch/build" --show-bin-path)
if ! xcodebuild -project "$repo/Ice.xcodeproj" -scheme Ice -configuration Debug CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$scratch/ice-dd" build > "$scratch/xcodebuild.log" 2>&1; then
    tail -30 "$scratch/xcodebuild.log" >&2
    echo "stage-lab: Ice did not build ($scratch/xcodebuild.log)" >&2
    exit 1
fi
ice_app=$scratch/ice-dd/Build/Products/Debug/Ice.app
signature=$(codesign -dv "$ice_app" 2>&1)
[[ $signature == *adhoc* ]] || { echo "stage-lab: the Ice build is not ad-hoc signed" >&2; exit 1; }
# A build without the report mode would run as a normal Ice under every scenario.
grep -rqaF IceLabReport-start-v1 "$ice_app/Contents/MacOS" || { echo "stage-lab: the Ice build has no lab report mode" >&2; exit 1; }

shared=/Users/Shared/IceReverse-lab
# /Users/Shared is world-writable: refuse a staging directory (or a child of
# it) that is a symlink or that the owner does not own.
[[ -e $shared || -L $shared ]] || mkdir -m 755 $shared
[[ -e $shared/evidence || -L $shared/evidence ]] || mkdir $shared/evidence
for dir in $shared $shared/evidence ${shared}/apps(N) ${shared}/Ice.app(N); do
    [[ -d $dir && ! -L $dir && -O $dir ]] || { echo "stage-lab: $dir is a symlink or not owned by $owner" >&2; exit 1; }
done
chmod 0755 $shared
# Writable by the isolated account; sticky, so only a run directory's creator
# can rename or remove it.
chmod 1777 $shared/evidence
/bin/rm -rf $shared/apps $shared/Ice.app
mkdir $shared/apps
ditto "$scratch/apps/Target.app" $shared/apps/Target.app
ditto "$scratch/apps/Protected.app" $shared/apps/Protected.app
ditto "$scratch/apps/Menus.app" $shared/apps/Menus.app
cp "$bin/icewatch" $shared/apps/icewatch
ditto "$ice_app" $shared/Ice.app
cp "$here/run-lab.sh" "$here/lab-tool.py" $shared/
chmod 0755 $shared/run-lab.sh
chmod 0644 $shared/lab-tool.py
chmod -R go-w $shared/apps $shared/Ice.app

revision=$(git -C "$repo" rev-parse --short HEAD)
[[ -z $(git -C "$repo" status --porcelain --untracked-files=no) ]] || revision+=-dirty
print -l -- \
    "EXPECT_USER=$isolated" "OWNER_USER=$owner" "GIT_REV=$revision" \
    "ICE_SHA=$(t7_sha_tree $shared/Ice.app)" \
    "TARGET_SHA=$(t7_sha $shared/apps/Target.app/Contents/MacOS/vzhelper)" \
    "PROTECTED_SHA=$(t7_sha $shared/apps/Protected.app/Contents/MacOS/vzhelper)" \
    "MENUS_SHA=$(t7_sha $shared/apps/Menus.app/Contents/MacOS/vzhelper)" \
    "ICEWATCH_SHA=$(t7_sha $shared/apps/icewatch)" \
    "TOOL_SHA=$(t7_sha $shared/lab-tool.py)" > $shared/lab.env
chmod 0644 $shared/lab.env

# The staged copy has the release's bundle id: it must not be what
# LaunchServices resolves the id to (T7's R9). The runner's own copies are
# started by path and never registered.
staged_records() { $lsregister -dump 2>/dev/null | grep -c "^path: *$shared/Ice.app" || true; }
if (( $(staged_records) > 0 )); then
    $lsregister -u $shared/Ice.app
    (( $(staged_records) == 0 )) || { echo "stage-lab: LaunchServices still lists $shared/Ice.app" >&2; exit 1; }
fi

echo "stage-lab: staged $revision for $isolated in $shared"
/bin/zsh $shared/run-lab.sh --dry-run
