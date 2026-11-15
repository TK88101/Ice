#!/bin/zsh -f
# G1 of plan 2026-11-15-secondary-display: the owner T0 gate is compiled out of
# Release. Usage: check-owner-t0.sh <Release Ice.app> [<Debug Ice.app>]
set -u
rel=${1:?usage: check-owner-t0.sh <Release Ice.app> [<Debug Ice.app>]}
fail=0
if /usr/bin/grep -rlaq IceOwnerT0 "$rel"; then
    print -- "FAIL: Release bundle contains IceOwnerT0"; fail=1
else
    print -- "ok: Release bundle has no IceOwnerT0"
fi
if (( $# > 1 )); then
    if /usr/bin/grep -rlaq IceOwnerT0 "$2"; then
        print -- "ok: Debug bundle has the gate"
    else
        print -- "FAIL: Debug bundle lacks IceOwnerT0"; fail=1
    fi
fi
# Source: the argument name appears only inside an #if DEBUG block.
src=${0:a:h}/../../../Ice/Main/LabReport.swift
awk '/#if DEBUG/{d=1} /#else|#endif/{d=0} /IceOwnerT0/ && !d && !/^ *\/\//{bad=1} END{exit bad}' "$src" \
    && print -- "ok: IceOwnerT0 only under #if DEBUG in source" \
    || { print -- "FAIL: IceOwnerT0 outside #if DEBUG"; fail=1; }
exit $fail
