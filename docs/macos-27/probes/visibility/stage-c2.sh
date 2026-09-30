#!/bin/zsh
# C2 (docs/plans/2026-09-28-c2-protocol.md sections 2 and 7): run in the
# OWNER's account, before a sitting. Builds, copies the tools to
# /Users/Shared/IceReverse-c2 (outside ~/Documents: iCloud xattrs break
# codesign), creates the evidence directory the isolated account writes into
# (owner-owned, mode 0777, no sticky bit, so the owner can delete what the
# runner leaves), and records the guards' expected values in c2.env.
#
#   ./stage-c2.sh <isolated-account-name> [scratch-dir]
set -euo pipefail
isolated=${1:?usage: stage-c2.sh <isolated-account-name> [scratch-dir]}
scratch=${2:-/private/tmp/claude-501/visibility-live}
owner=$(id -un)
[[ $isolated != $owner ]] || { echo "stage-c2: the isolated account must not be $owner" >&2; exit 2; }

here=${0:A:h}
"$here/build.sh" "$scratch"

shared=/Users/Shared/IceReverse-c2
mkdir -p $shared/evidence
chmod 0777 $shared/evidence
# Replace only the previous staged copy of the tools, never evidence.
[[ -d $shared/apps ]] && /bin/rm -r $shared/apps
ditto "$scratch/apps" $shared/apps
cp "$here/run-c2.sh" $shared/run-c2.sh
chmod 0755 $shared/run-c2.sh

geometry=$("$shared/apps/vizprobe" c2-geometry)
cat > $shared/c2.env <<ENV
EXPECT_USER=$isolated
OWNER_USER=$owner
EXPECT_GEOMETRY=$geometry
ENV
chmod 0644 $shared/c2.env
echo "stage-c2: staged for $isolated (geometry $geometry) in $shared"
