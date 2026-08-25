#!/bin/sh
# Assembles a minimal .app so the TCC (Accessibility) identity is stable across rebuilds.
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/SpacialShell.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SpacialShell "$APP/Contents/MacOS/SpacialShell"
cp .build/release/spacialctl "$APP/Contents/MacOS/spacialctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/MacOS/spacialctl"
codesign --force --sign - --identifier me.askalice.SpacialShell "$APP"
echo "built $APP"
