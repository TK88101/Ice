#!/bin/zsh
# A8 (plan section 7): the window-only grep over Ice/ must equal the table
# written before T9, line for line as a multiset. Exit 0 on a match.
set -euo pipefail
here=${0:A:h}
root=${here:h:h:h}
cd "$root"
expected=$(grep -v '^#' "$here/a8-expected-hits.txt" | sort)
actual=$(grep -rnE 'getWindowBounds|isWindowOnScreen|captureWindow|setWindowID|windowID' Ice/ \
    | python3 -c 'import sys
for l in sys.stdin:
    f, n, c = l.rstrip("\n").split(":", 2)
    print(f + "\t" + c.strip())' | sort)
if diff <(print -r -- "$expected") <(print -r -- "$actual"); then
    echo "A8: $(print -r -- "$actual" | wc -l | tr -d ' ') hits, as expected"
else
    echo "A8: MISMATCH (< expected, > actual)"
    exit 1
fi
