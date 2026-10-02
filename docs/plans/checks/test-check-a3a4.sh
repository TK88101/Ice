#!/bin/zsh
# U24's own test (docs/plans/2026-10-03-icebar-c-runner.md, T9): check-a3a4.sh
# passes on an untouched tree and fails when a frozen file changes or a new
# file appears under Packages/MenuBarCapture. Runs in a throwaway worktree
# outside ~/Documents (iCloud), removed afterwards; the real tree is never touched.
set -uo pipefail
here=${0:A:h}
repo=$(git -C "$here" rev-parse --show-toplevel)
check=$here/check-a3a4.sh
scratch=/private/tmp/claude-501/u24-$$
failures=0

cleanup() {
    git -C "$repo" worktree remove --force "$scratch" >/dev/null 2>&1
    rm -rf "$scratch"
}
trap cleanup EXIT

expect() { # expect <0|nonzero> <label>
    local want=$1 label=$2 got
    "$check" "$scratch" >/dev/null 2>&1
    got=$?
    if [[ $want == 0 && $got == 0 ]] || [[ $want == nonzero && $got != 0 ]]; then
        echo "ok   $label"
    else
        echo "FAIL $label (exit $got)"
        failures=$((failures + 1))
    fi
}

[[ -x $check ]] || { echo "FAIL check-a3a4.sh missing or not executable"; exit 1; }
git -C "$repo" worktree add --detach --quiet "$scratch" HEAD || { echo "FAIL cannot create the worktree"; exit 1; }

expect 0 "untouched tree passes"
printf '\n' >> "$scratch/Packages/IceCore/Sources/IceCore/FoldWitness.swift"
expect nonzero "a frozen detector file changed fails"
git -C "$scratch" checkout --quiet -- Packages/IceCore/Sources/IceCore/FoldWitness.swift
printf '\n' >> "$scratch/Packages/MenuBarCapture/Sources/MenuBarCapture/Sampler.swift"
expect nonzero "a MenuBarCapture file changed fails"
git -C "$scratch" checkout --quiet -- Packages/MenuBarCapture/Sources/MenuBarCapture/Sampler.swift
touch "$scratch/Packages/MenuBarCapture/Sources/MenuBarCapture/Added.swift"
expect nonzero "a file added under MenuBarCapture fails"
rm "$scratch/Packages/MenuBarCapture/Sources/MenuBarCapture/Added.swift"
expect 0 "restored tree passes"

exit $failures
