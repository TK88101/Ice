#!/bin/zsh
# A10 (plan section 7): nothing under Shared/ or MenuBarItemService/ changed,
# and ControlItem.swift, AppState.swift and the layout pane changed exactly
# as the expected-lines files written before T9 say. Exit 0 on a match.
set -euo pipefail
here=${0:A:h}
root=${here:h:h:h}
cd "$root"
git diff --quiet af4baf1 -- Shared MenuBarItemService || { echo "A10: Shared/ or MenuBarItemService/ changed"; exit 1; }
failed=0
for pair in \
    "Ice/MenuBar/ControlItem/ControlItem.swift:a10-ControlItem.expected" \
    "Ice/Main/AppState.swift:a10-AppState.expected" \
    "Ice/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift:a10-MenuBarLayoutSettingsPane.expected"
do
    file=${pair%%:*}
    expected=$here/${pair##*:}
    if diff "$expected" <(git diff -U0 af4baf1 -- "$file" | grep -E '^[+-][^+-]' || true); then
        echo "A10: $file as expected"
    else
        echo "A10: $file MISMATCH (< expected, > actual)"
        failed=1
    fi
done
exit $failed
