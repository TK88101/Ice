#!/bin/zsh
# IceBar build plan T0: the ONE command the owner runs, in the isolated
# account's Terminal, at the time the owner named; then leaves the Mac. The
# last lines are the two answers (藏得住幾個 / 點得開嗎) and 結果：… .
#
#   /Users/Shared/IceReverse-spike/run-spike.sh [--members 1,2] [--menus short] [--lengths from:through:step] [--no-b]
set -euo pipefail
umask 000
shared=/Users/Shared/IceReverse-spike
source $shared/spike.env
export ICEBAR_K_DIR
exec $shared/apps/vizprobe spike-run --apps $shared/apps --evidence-root $shared/evidence \
    --expect-user "$EXPECT_USER" --owner-user "$OWNER_USER" --expect-geometry "$EXPECT_GEOMETRY" "$@"
