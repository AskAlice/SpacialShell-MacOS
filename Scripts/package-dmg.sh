#!/bin/sh
# Release .app (via bundle.sh) into a compressed DMG with an Applications drop-link.
set -e
cd "$(dirname "$0")/.."
Scripts/bundle.sh
VER=${VERSION:-$(git describe --tags --always 2>/dev/null || echo 0.1.0)}
VER=${VER#v}
STAGE=build/dmg-stage
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R build/SpacialShell.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG=build/SpacialShell-$VER.dmg
rm -f "$DMG"
hdiutil create -volname "SpacialShell $VER" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "built $DMG"
