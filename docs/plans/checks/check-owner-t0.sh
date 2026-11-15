#!/bin/zsh -f
# Plan 2026-11-15-secondary-display, G1: the owner T0 gate served one sitting and
# was removed after it (simcodex round 1). This asserts it stays gone from the
# source tree and, if given, from a built bundle.
#   check-owner-t0.sh [<Ice.app>]
set -u
root=${0:a:h}/../../..
fail=0
if /usr/bin/grep -rIq IceOwnerT0 "$root/Ice" "$root/Packages" "$root/Shared"; then
    print -- "FAIL: IceOwnerT0 in the source tree"; fail=1
else
    print -- "ok: no IceOwnerT0 in the source tree"
fi
if (( $# > 0 )); then
    if /usr/bin/grep -rlaq IceOwnerT0 "$1"; then print -- "FAIL: $1 contains IceOwnerT0"; fail=1
    else print -- "ok: $1 has no IceOwnerT0"; fi
fi
exit $fail
