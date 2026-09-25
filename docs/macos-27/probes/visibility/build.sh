#!/bin/zsh
# Builds vzhelper and vizprobe outside ~/Documents and assembles vzhelper's
# three .app bundles there. ~/Documents is iCloud-managed; the extended
# attributes it attaches make codesign reject anything built inside it
# (docs/macos-27/probes/safewidth/build.sh, the same reason).
#
#   ./build.sh [scratch-dir]      default: /private/tmp/claude-501/visibility-live
#
# Output: <scratch>/apps/{Target,Protected,Twin}.app and <scratch>/apps/vizprobe
set -euo pipefail

here=${0:A:h}
scratch=${1:-/private/tmp/claude-501/visibility-live}
build=$scratch/build
apps=$scratch/apps

swift build -c release --package-path "$here" --scratch-path "$build"
bin=$(swift build -c release --package-path "$here" --scratch-path "$build" --show-bin-path)

rm -rf "$apps"
mkdir -p "$apps"

# make_app <name> <bundle id>
make_app() {
    local name=$1 bundle=$2
    local app=$apps/$name.app
    mkdir -p "$app/Contents/MacOS"
    cp "$bin/vzhelper" "$app/Contents/MacOS/vzhelper"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$bundle</string>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleExecutable</key><string>vzhelper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
    codesign --force --sign - "$app" >/dev/null
}

# Target and Protected reuse the bundle ids probes/safewidth's own swhelper
# already registered with the system, so T13's DoD holds: no new entry in
# the menu bar settings for either (Opus P2-13). Twin is new on purpose --
# it exists only for the ambiguity control of plan section 6.1 step 6(c),
# launched, observed once and quit within the same run; --role, not the
# bundle id, is what tells vzhelper to draw the target's own glyph for it.
make_app Target com.icespike4.target
make_app Protected com.icespike4.protected
# The twin reuses the protected helper's already-registered bundle id: a new
# id would add a permanent entry to the system's menu bar settings, which is a
# side effect this run is not allowed to leave behind.
make_app Twin com.icespike4.protected
# C1's spacer (docs/plans/2026-09-26-c1-protocol.md) reuses the same id for the
# same reason; `--role spacer`, not the bundle id, makes it the spacer.
make_app Spacer com.icespike4.protected

cp "$bin/vizprobe" "$apps/vizprobe"
codesign --force --sign - "$apps/vizprobe" >/dev/null

echo "$apps"
