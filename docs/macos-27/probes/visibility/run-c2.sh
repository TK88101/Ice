#!/bin/zsh
# C2 (docs/plans/2026-09-28-c2-protocol.md section 7): the ONE command the
# owner runs, in the isolated account's Terminal, then leaves the Mac.
#
#   /Users/Shared/IceReverse-c2/run-c2.sh A            sitting A (brackets)
#   /Users/Shared/IceReverse-c2/run-c2.sh B <length>   sitting B (collar + baseline)
set -euo pipefail
umask 000
shared=/Users/Shared/IceReverse-c2
source $shared/c2.env
sitting=${1:?usage: run-c2.sh A | run-c2.sh B <length>}
extra=()
if [[ $sitting == B ]]; then extra=(--length "${2:?sitting B needs a length}"); fi
exec $shared/apps/vizprobe c2-run --sitting $sitting "${extra[@]}" \
    --apps $shared/apps --evidence-root $shared/evidence \
    --expect-user "$EXPECT_USER" --owner-user "$OWNER_USER" --expect-geometry "$EXPECT_GEOMETRY"
