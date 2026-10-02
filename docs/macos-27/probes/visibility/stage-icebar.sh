#!/bin/zsh
# Route C (docs/plans/2026-10-03-icebar-c-runner.md, section 4): run in the
# OWNER's account before a sitting, as stage-c2.sh does for C2. Builds (U24
# first), copies the tools to /Users/Shared/IceReverse-icebar (outside
# ~/Documents: iCloud xattrs break codesign), copies K1 (the chevron template's
# source) there after checking its pre-registered sha256, creates the evidence
# directory the isolated account writes into, and records the guards' values.
#
#   ./stage-icebar.sh <isolated-account-name> [scratch-dir]
set -euo pipefail
isolated=${1:?usage: stage-icebar.sh <isolated-account-name> [scratch-dir]}
scratch=${2:-/private/tmp/claude-501/visibility-live}
owner=$(id -un)
[[ $isolated != $owner ]] || { echo "stage-icebar: the isolated account must not be $owner" >&2; exit 2; }

here=${0:A:h}
# Runner plan section 7: nothing is staged unless every frozen source still
# equals the pre-S0 manifest (written before S0, its sha256 in the
# pre-registration's section 9 addendum).
swift run --package-path "$here" --scratch-path "$scratch/build" -c release icebarfreeze verify \
    --manifest "$here/../../../plans/2026-10-03-icebar-c-pre-s0-manifest.json"
"$here/build.sh" "$scratch"

k1=$HOME/IceReverse-evidence/20260918-204150-m-mid/captures/00011-probe-mid-20.png
k1sha=a3bcce60c95dc037ca2085cb6acc6f51539d749d69d2c3871d707639a36739e6
[[ $(shasum -a 256 "$k1" | cut -d' ' -f1) == $k1sha ]] || { echo "stage-icebar: K1 is not the pre-registered file" >&2; exit 1; }

shared=/Users/Shared/IceReverse-icebar
mkdir -p $shared/evidence $shared/k
# /Users/Shared is world-writable: everything below is done as the owner, so
# refuse a staging directory (or a child of it) that is a symlink or that the
# owner does not own (another account could have created it first).
for dir in $shared $shared/k $shared/evidence ${shared}/apps(N); do
    [[ ! -L $dir && -O $dir ]] || { echo "stage-icebar: $dir is a symlink or not owned by $owner" >&2; exit 1; }
done
chmod 0777 $shared/evidence
# Replace only the previous staged copy of the tools, never evidence.
[[ -d $shared/apps ]] && /bin/rm -r $shared/apps
ditto "$scratch/apps" $shared/apps
cp "$k1" $shared/k/
chmod 0644 $shared/k/*
cp "$here/run-icebar.sh" $shared/run-icebar.sh
chmod 0755 $shared/run-icebar.sh

# The owner's own build, never the shared copy the isolated account can write to.
geometry=$("$scratch/apps/vizprobe" c2-geometry)
cat > $shared/icebar.env <<ENV
EXPECT_USER=$isolated
OWNER_USER=$owner
EXPECT_GEOMETRY=$geometry
ICEBAR_K_DIR=$shared/k
ENV
chmod 0644 $shared/icebar.env
echo "stage-icebar: staged for $isolated (geometry $geometry) in $shared"
