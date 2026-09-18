#!/bin/zsh
# Builds the safe-width instruments outside ~/Documents and assembles the helper
# apps there. ~/Documents is iCloud-managed; the extended attributes it attaches
# make codesign reject anything built inside it.
#
#   ./build.sh [scratch-dir]      default: ${TMPDIR}safewidth-build
#
# Output: <scratch>/apps/{Target,Protected,F}.app and <scratch>/apps/swctl
set -euo pipefail

here=${0:A:h}
scratch=${1:-${TMPDIR:-/tmp/}safewidth-build}
build=$scratch/build
apps=$scratch/apps

swift build -c release --package-path "$here" --scratch-path "$build"
bin=$(swift build -c release --package-path "$here" --scratch-path "$build" --show-bin-path)

rm -rf "$apps"
mkdir -p "$apps"

# make_app <name> <executable> <bundle id> <LSUIElement true|false>
make_app() {
    local name=$1 executable=$2 bundle=$3 agent=$4
    local app=$apps/$name.app
    mkdir -p "$app/Contents/MacOS"
    cp "$bin/$executable" "$app/Contents/MacOS/$executable"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$bundle</string>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleExecutable</key><string>$executable</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><$agent/>
</dict>
</plist>
PLIST
    codesign --force --sign - "$app" >/dev/null
}

make_app Target swhelper com.icespike4.target true
make_app Protected swhelper com.icespike4.protected true
# F's app menu shows its bundle name; one letter keeps the narrow config narrow.
make_app F swfront com.icespike4.front false

cp "$bin/swctl" "$apps/swctl"
codesign --force --sign - "$apps/swctl" >/dev/null

echo "$apps"
