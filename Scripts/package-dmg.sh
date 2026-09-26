#!/bin/sh
# Release .app (via bundle.sh) into a compressed DMG with an Applications drop-link.
#
#   Scripts/package-dmg.sh              bundle the app, then build the DMG
#   Scripts/package-dmg.sh --app-only   bundle the app only (build/SpacialShell.app)
#   Scripts/package-dmg.sh --dmg-only   build the DMG from the build/SpacialShell.app already there
#
# notarize.sh uses the two halves so it can staple the app before it goes into the DMG (#152).
set -e
cd "$(dirname "$0")/.."

MODE=all
case "${1:-}" in
    "") ;;
    --app-only) MODE=app ;;
    --dmg-only) MODE=dmg ;;
    *) echo "usage: $0 [--app-only|--dmg-only]" >&2; exit 2 ;;
esac

# A release is the one case that needs a secure timestamp: it keeps the signature valid after the
# signing certificate expires, and notarisation refuses a build without one.
VER=${VERSION:-$(git describe --tags --always 2>/dev/null || echo 0.1.0)}
VER=${VER#v}
if [ "$MODE" != dmg ]; then
    SPACIAL_TIMESTAMP=1 SPACIAL_VERSION=$VER Scripts/bundle.sh
fi
[ "$MODE" = app ] && exit 0

[ -d build/SpacialShell.app ] || { echo "package-dmg.sh: build/SpacialShell.app not found" >&2; exit 1; }
STAGE=build/dmg-stage
rm -rf "$STAGE"
mkdir -p "$STAGE"
# ditto, not cp: it keeps the stapled ticket and every extended attribute intact.
ditto build/SpacialShell.app "$STAGE/SpacialShell.app"
ln -s /Applications "$STAGE/Applications"
DMG=build/SpacialShell-$VER.dmg
rm -f "$DMG"
hdiutil create -volname "SpacialShell $VER" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "built $DMG"
