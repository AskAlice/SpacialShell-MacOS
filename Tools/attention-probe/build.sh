#!/bin/sh
# Builds ./probe and ./AttentionBouncer.app (a bundle so it gets a proper Dock item and bundle id).
set -e
cd "$(dirname "$0")"
swiftc -O probe.swift -o probe
mkdir -p AttentionBouncer.app/Contents/MacOS
swiftc -O bouncer.swift -o AttentionBouncer.app/Contents/MacOS/AttentionBouncer
cat > AttentionBouncer.app/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>me.askalice.spacialshell.attention-bouncer</string>
<key>CFBundleName</key><string>AttentionBouncer</string>
<key>CFBundleExecutable</key><string>AttentionBouncer</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PL
codesign -s - --force AttentionBouncer.app
