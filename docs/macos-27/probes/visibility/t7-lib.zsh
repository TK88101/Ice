# IceBar build plan T7 (docs/plans/2026-10-03-icebar-build.md section 10):
# functions shared by stage-t7.sh and run-t7.sh, sourced by both and tested by
# test-t7.sh. Nothing here starts a process of ours.

t7_sha() { # <file>
    shasum -a 256 "$1" | cut -d' ' -f1
}

# One digest for a bundle: every file's sha256 with its relative path, and every
# symbolic link's target. A Debug build's code is in Ice.debug.dylib, not in the
# executable itself. Sorted in the C locale: the digest is made in one account
# and checked in another, whose collation may differ.
t7_sha_tree() { # <directory>
    (
        cd "$1" || exit 1
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
        find . -type l | LC_ALL=C sort | while read -r link; do print -r -- "$link -> $(readlink "$link")"; done
    ) | shasum -a 256 | cut -d' ' -f1
}

# What run-t7.sh trusts, written once at staging (and by test-t7.sh for its
# stub staging): the accounts, what was staged, and which domains the run may
# rewrite. Values are plain words; run-t7.sh reads the file, it never sources it.
t7_write_env() { # <staging directory> <isolated user> <owner> <revision> <Ice's domain> <helper domains, comma-separated> [KEY=value ...]
    local shared=$1
    print -l -- \
        "EXPECT_USER=$2" "OWNER_USER=$3" "GIT_REV=$4" "DOMAIN=$5" "HELPER_DOMAINS=$6" \
        "ICE_SHA=$(t7_sha_tree $shared/Ice.app)" \
        "TARGET_SHA=$(t7_sha $shared/apps/Target.app/Contents/MacOS/vzhelper)" \
        "MENUS_SHA=$(t7_sha $shared/apps/Menus.app/Contents/MacOS/vzhelper)" \
        "ICEWATCH_SHA=$(t7_sha $shared/apps/icewatch)" \
        "${@:7}" > $shared/t7.env
}

# The staged code against the sha256 recorded in t7.env (already read).
t7_check_staged() { # <staging directory>
    local shared=$1 problems=0 name file want
    if [[ ! -d $shared/Ice.app || $(t7_sha_tree $shared/Ice.app) != $ICE_SHA ]]; then
        print -u2 -- "t7: Ice.app is not the staged bundle ($shared/Ice.app)"
        problems=1
    fi
    for name file want in \
        Target $shared/apps/Target.app/Contents/MacOS/vzhelper "$TARGET_SHA" \
        Menus $shared/apps/Menus.app/Contents/MacOS/vzhelper "$MENUS_SHA" \
        icewatch $shared/apps/icewatch "$ICEWATCH_SHA"; do
        if [[ ! -f $file || $(t7_sha $file) != $want ]]; then
            print -u2 -- "t7: $name is not the staged file ($file)"
            problems=$((problems + 1))
        fi
    done
    return $problems
}

t7_preflight_ok() { # <icewatch preflight's line>
    [[ $1 == *'"axTrusted":true'* && $1 == *'"screenCapture":true'* ]]
}

# A value of a JSON text by key path (plutil reads JSON; a number comes back as
# e.g. 771.500000, an array as its count). Fails for bad JSON, a missing key or null.
t7_json_get() { # <json> <key path>
    print -r -- "$1" | plutil -extract "$2" raw -o - - 2>/dev/null
}

t7_is_number() { # <text>
    [[ ${1-} =~ '^-?[0-9]+(\.[0-9]+)?$' ]]
}

# `icewatch menu-frame`'s line (plan 2026-10-07-icebar-menu-frame-fix, F4):
# Ice's reader found the menu and it fits; every value the run uses is a number.
t7_menu_frame_ok() { # <line>
    local key value
    [[ $(t7_json_get "$1" verdict) == fits ]] || return 1
    for key in menuMaxX notchMinX displayWidth barHeight; do
        value=$(t7_json_get "$1" $key) && t7_is_number "$value" || return 1
    done
}

# Where a helper's item is, from its `selfread` reply (plan F3): its own child,
# found by identifier, and its whole frame inside the main display's bar band.
# Prints `on <x>`, `off <x,y,w,h>` or `unknown <reason>`; returns 0, 1 or 2.
t7_placement() { # <selfread json> <identifier> <display width> <bar height>
    local json=$1 count i x y w h
    count=$(t7_json_get "$json" children) && [[ $count == <-> ]] || { print -r -- "unknown 回覆讀不懂"; return 2; }
    for (( i = 0; i < count; i++ )); do
        [[ $(t7_json_get "$json" children.$i.identifier) == $2 ]] || continue
        x=$(t7_json_get "$json" children.$i.frame.0) && y=$(t7_json_get "$json" children.$i.frame.1) \
            && w=$(t7_json_get "$json" children.$i.frame.2) && h=$(t7_json_get "$json" children.$i.frame.3) \
            && t7_is_number "$x" && t7_is_number "$y" && t7_is_number "$w" && t7_is_number "$h" \
            || { print -r -- "unknown 讀不到 $2 的位置"; return 2; }
        if (( w > 0 && h > 0 && x >= 0 && x + w <= $3 && y >= 0 && y + h <= $4 )); then
            printf 'on %g\n' $x
            return 0
        fi
        printf 'off %g,%g,%g,%g\n' $x $y $w $h
        return 1
    done
    print -r -- "unknown 沒有 $2 這個項目"
    return 2
}

# How many Ice or vzhelper processes `ps <arguments>` lists: by executable
# path, not by name (the release Ice has the same name).
t7_count_ours() { # <ps arguments...>
    ps "$@" -o comm= | grep -c -E '/Ice\.app/Contents/MacOS/Ice$|/vzhelper$' || true
}

# A directory this account can build or test in: neither it nor its parent is
# a symbolic link or someone else's (/private/tmp is world-writable and emptied
# at boot, so another account could have created either first).
t7_private_directory() { # <directory>
    local dir
    for dir in ${1:h} $1; do
        [[ -e $dir || -L $dir ]] || mkdir -m 700 $dir || return 1
        [[ -d $dir && ! -L $dir && -O $dir ]] || { print -u2 -- "t7: $dir is a symlink or not this account's"; return 1; }
    done
}

# --- preferences ----------------------------------------------------------------

t7_prefs_export() { # <domain> <file>
    defaults export "$1" "$2" && plutil -lint "$2" >/dev/null
}

# An absent domain exports as an empty dictionary.
t7_prefs_is_empty() { # <file>
    [[ $(plutil -p "$1") == $'{\n}' ]]
}

# After a delete `defaults read` can still answer `{}` (exit 0) for a while, so
# "absent" is judged by content: no keys.
t7_domain_is_empty() { # <domain>
    local now result=1
    now=$(mktemp -t t7prefs) || return 1
    defaults export "$1" $now 2>/dev/null && t7_prefs_is_empty $now && result=0
    rm -f $now
    return $result
}

# Compared as XML, whose writer sorts the keys.
t7_prefs_same() { # <domain> <file>
    local now result=1
    now=$(mktemp -t t7prefs) || return 1
    if defaults export "$1" $now 2>/dev/null \
        && [[ $(plutil -convert xml1 -o - $now) == $(plutil -convert xml1 -o - "$2") ]]; then
        result=0
    fi
    rm -f $now
    return $result
}

# icewatch's order (Supervisor.swift, `restore`): import and compare; only on a
# difference delete the domain and import again. An empty export means the
# domain did not exist, so it is deleted.
t7_prefs_restore() { # <domain> <file>
    local domain=$1 file=$2
    if t7_prefs_is_empty $file; then
        defaults delete $domain >/dev/null 2>&1
        t7_domain_is_empty $domain
        return
    fi
    defaults import $domain $file && t7_prefs_same $domain $file && return 0
    defaults delete $domain >/dev/null 2>&1
    defaults import $domain $file && t7_prefs_same $domain $file
}

# --- Ice's log (stderr with OS_ACTIVITY_DT_MODE) -----------------------------------
# The wording below is Ice's: `IceBarHidingCoordinator.swift` (status, baseline,
# trial, fold) and `MenuBarItemManager+IceBar27.swift` (press). test-t7.sh checks
# that those files still say it.

t7_log_has() { # <log> <first line> <extended regex>
    awk -v from=$2 -v pattern=$3 'NR >= from && $0 ~ pattern { found = 1 } END { exit !found }' $1
}

t7_log_has_long_menu() { # <log> <first line>
    t7_log_has $1 $2 "${t7_ice_status_prefix}shown[(].*longMenu"
}

# The start of one of Ice's own status lines, from the log line's date to the
# status: another app's text that Ice logs (an item's title) cannot pass for
# one in the middle of a line (security review, plan 2026-10-07 Phase 3).
# Best effort: such text with a newline in it could still start a line.
t7_ice_status_prefix='^[0-9-]+ [0-9:.+-]+ Ice[[][0-9:]+[]] [[]IceBarHiding[]] IceBar hiding: '

# The latest `IceBar hiding:` status between two lines: active, checking, off,
# shown:<reason>, or nothing (plan 2026-10-07-icebar-menu-frame-fix, F2).
t7_latest_status() { # <log> <first line> [last line]
    awk -v from=$2 -v to=${3:-0} -v prefix="$t7_ice_status_prefix" '
    NR >= from && (to == 0 || NR <= to) && $0 ~ prefix {
        status = $0
        sub(prefix, "", status)
        if (status ~ /^shown[(]/) {
            sub(/.*IceBarShownReason\./, "", status)
            sub(/[^A-Za-z].*/, "", status)
            status = "shown:" status
        }
        latest = status
    }
    END { print latest }' $1
}

# Reads a log slice on stdin. The last line says how many of Ice's IceBar lines
# were understood: a log whose wording has changed must not read as "nothing
# happened".
t7_summary() {
    awk '
    function seconds(clock,  part) { split(clock, part, /[:+]/); return part[1] * 3600 + part[2] * 60 + part[3] }
    # Only the two IceBar categories, each line counted once.
    !/\[IceBar(Hiding|Press)\]/ { next }
    { lines++; known++ }
    /IceBar hiding: off/ { next }
    /IceBar hiding: checking/ { if (since == "") since = seconds($2); next }
    /IceBar hiding: active/ {
        active++
        if (since != "") {
            took = seconds($2) - since
            if (took < 0) took += 86400
            times[++count] = took
            since = ""
        }
        next
    }
    /IceBar hiding: shown\(/ {
        reason = $0
        sub(/.*IceBarShownReason\./, "", reason)
        sub(/[^A-Za-z].*/, "", reason)
        shown[reason]++
        since = ""
        next
    }
    /A fold appeared at rest/ { folds++; next }
    /Press failed/ { presses++; next }
    /IceBar trial: / { outcome[$NF]++; next }
    /IceBar baseline: ok true/ { baselineOK++; next }
    /IceBar baseline: ok false/ { baselineFailed++; next }
    { known-- }
    END {
        printf "active %d 次\n", active
        if (count == 0) {
            print "checking→active 秒數：無"
        } else {
            for (i = 2; i <= count; i++) {
                value = times[i]
                for (j = i - 1; j >= 1 && times[j] > value; j--) times[j + 1] = times[j]
                times[j + 1] = value
            }
            median = count % 2 ? times[(count + 1) / 2] : (times[count / 2] + times[count / 2 + 1]) / 2
            printf "checking→active 秒數：中位 %.1f（最短 %.1f，最長 %.1f）\n", median, times[1], times[count]
        }
        none = 1
        for (reason in shown) { printf "shown %s %d\n", reason, shown[reason]; none = 0 }
        if (none) print "shown 0"
        printf "靜止時出現 « %d 次\n", folds
        printf "按壓失敗 %d 次\n", presses
        printf "試長度結果：hiddenClean %d / folded %d / drawn %d / unknown %d\n", outcome["hiddenClean"], outcome["folded"], outcome["drawn"], outcome["unknown"]
        printf "baseline：成功 %d / 失敗 %d\n", baselineOK, baselineFailed
        printf "Ice 的 IceBar 紀錄 %d 行，讀懂 %d 行%s\n", lines, known, (lines > known ? "（有讀不懂的行：上面的數字可能偏少，請把 ice.log 交給 Claude）" : "")
    }'
}
