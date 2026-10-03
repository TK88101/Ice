#!/bin/zsh
# U24 (docs/plans/2026-09-30-icebar-c-prereg.md section 7; runner plan T9): A3
# and A4 -- Packages/MenuBarCapture and the ten frozen detector files are
# byte-identical to af4baf1 (the list of 2026-09-25-residuals.md section 2), and
# nothing new appears under MenuBarCapture. Any difference, or git failing,
# exits non-zero; probes/visibility/build.sh runs this first.
#
#   check-a3a4.sh [repository]      default: the repository holding this script
set -euo pipefail
repo=${1:-$(git -C "${0:A:h}" rev-parse --show-toplevel)}
frozen=(
    Packages/MenuBarCapture
    Packages/IceCore/Sources/IceCore/{DetectorParameters,Ink,StripImage,Template,TemplateMatcher,CaptureStability,FoldWitness,StripAssessor,MenuBarItemVisibility,MenuBarItemCacheState}.swift
)
if ! git -C "$repo" diff --quiet af4baf1 -- "${frozen[@]}"; then
    echo "U24: frozen files differ from af4baf1:" >&2
    git -C "$repo" diff --stat af4baf1 -- "${frozen[@]}" >&2
    exit 1
fi
added=$(git -C "$repo" ls-files --others --exclude-standard -- Packages/MenuBarCapture)
if [[ -n $added ]]; then
    echo "U24: files added under Packages/MenuBarCapture:" >&2
    echo "$added" >&2
    exit 1
fi
