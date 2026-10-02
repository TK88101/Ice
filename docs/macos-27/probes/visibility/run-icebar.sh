#!/bin/zsh
# Route C (docs/plans/2026-10-03-icebar-c-runner.md): the ONE command the owner
# runs, in the isolated account's Terminal, at the time the owner named; then
# leaves the Mac. The last line is route C 7a's 結果：…｜…｜… .
#
#   /Users/Shared/IceReverse-icebar/run-icebar.sh
set -euo pipefail
umask 000
shared=/Users/Shared/IceReverse-icebar
source $shared/icebar.env
export ICEBAR_K_DIR
exec $shared/apps/vizprobe icebar-run --apps $shared/apps --evidence-root $shared/evidence \
    --expect-user "$EXPECT_USER" --owner-user "$OWNER_USER" --expect-geometry "$EXPECT_GEOMETRY"
