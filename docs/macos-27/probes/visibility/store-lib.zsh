# MenuBarAgent's store of remembered status-item positions, as the runners read
# it (run-trace.sh, run-remembered.sh). Read with `defaults export` from here,
# not from a staged app: another app's group container read from Ice could
# raise a privacy prompt. Never written.
menubar_store="$HOME/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar"
store_settle_tries=10 # x 1 s

export_store() { # <output json>
    defaults export "$menubar_store" - | plutil -convert json -o "$1" -
}

settled_store() { # <output json>: read until two reads a second apart agree
    local previous=$1.previous tries=0
    export_store $previous || return 1
    while (( tries++ < store_settle_tries )); do
        sleep 1
        export_store $1 || return 1
        cmp -s $previous $1 && { rm -f -- $previous; return 0; }
        mv -- $1 $previous
    done
    print -u2 -- "MenuBarAgent's store did not settle"
    return 1
}
