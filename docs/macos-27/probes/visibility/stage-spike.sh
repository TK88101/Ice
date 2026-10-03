#!/bin/zsh
# IceBar build plan T0 (docs/plans/2026-10-03-icebar-build.md, section 7 note
# 1): run in the OWNER's account before the owner's sitting, as stage-icebar.sh
# does for route C. Builds (U24 first), copies the tools to
# /Users/Shared/IceReverse-spike (outside ~/Documents: iCloud xattrs break
# codesign), copies K1 (the chevron template's source) there after checking its
# sha256, creates the evidence directory the isolated account writes into,
# records the guards' values, and runs the dry check (nothing launched).
#
#   ./stage-spike.sh <isolated-account-name> [scratch-dir]
set -euo pipefail
isolated=${1:?usage: stage-spike.sh <isolated-account-name> [scratch-dir]}
scratch=${2:-/private/tmp/claude-501/visibility-live}
owner=$(id -un)
[[ $isolated != $owner ]] || { echo "stage-spike: the isolated account must not be $owner" >&2; exit 2; }

here=${0:A:h}
"$here/build.sh" "$scratch"

k1=$HOME/IceReverse-evidence/20260918-204150-m-mid/captures/00011-probe-mid-20.png
k1sha=a3bcce60c95dc037ca2085cb6acc6f51539d749d69d2c3871d707639a36739e6
[[ $(shasum -a 256 "$k1" | cut -d' ' -f1) == $k1sha ]] || { echo "stage-spike: K1 is not the recorded file" >&2; exit 1; }

shared=/Users/Shared/IceReverse-spike
mkdir -p $shared/evidence $shared/k
# /Users/Shared is world-writable: everything below is done as the owner, so
# refuse a staging directory (or a child of it) that is a symlink or that the
# owner does not own (another account could have created it first).
for dir in $shared $shared/k $shared/evidence ${shared}/apps(N); do
    [[ ! -L $dir && -O $dir ]] || { echo "stage-spike: $dir is a symlink or not owned by $owner" >&2; exit 1; }
done
chmod 0777 $shared/evidence
# Replace only the previous staged copy of the tools, never evidence.
[[ -d $shared/apps ]] && /bin/rm -r $shared/apps
ditto "$scratch/apps" $shared/apps
cp "$k1" $shared/k/
chmod 0644 $shared/k/*
cp "$here/run-spike.sh" $shared/run-spike.sh
chmod 0755 $shared/run-spike.sh

# The owner's own build, never the shared copy the isolated account can write to.
geometry=$("$scratch/apps/vizprobe" c2-geometry)
cat > $shared/spike.env <<ENV
EXPECT_USER=$isolated
OWNER_USER=$owner
EXPECT_GEOMETRY=$geometry
ICEBAR_K_DIR=$shared/k
ENV
chmod 0644 $shared/spike.env
echo "stage-spike: staged for $isolated (geometry $geometry) in $shared"
ICEBAR_K_DIR=$shared/k "$scratch/apps/vizprobe" spike-dry --apps "$scratch/apps"
