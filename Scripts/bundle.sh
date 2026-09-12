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
# Signing identity. Ad-hoc signatures change on every rebuild, and macOS keys the Accessibility
# grant to the signature — so an ad-hoc rebuild silently revokes it, leaving a ticked checkbox and
# an untrusted app (Scripts/README). A stable self-signed identity keeps the grant across rebuilds.
#
# Create one once: Keychain Access > Certificate Assistant > Create a Certificate,
#   name "SpacialShell Dev", Identity Type "Self Signed Root", Certificate Type "Code Signing".
# Override with SPACIAL_SIGN_IDENTITY=... to use a different one.
IDENTITY="${SPACIAL_SIGN_IDENTITY:-SpacialShell Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    SIGN="$IDENTITY"
else
    SIGN="-"
    echo "bundle.sh: no '$IDENTITY' code-signing identity; signing ad-hoc." >&2
    echo "bundle.sh: the Accessibility grant will not survive this rebuild — see Scripts/README." >&2
fi

codesign --force --sign "$SIGN" "$APP/Contents/MacOS/spacialctl"
codesign --force --sign "$SIGN" --identifier sh.emu.SpacialShell "$APP"
echo "built $APP (signed: $SIGN)"
