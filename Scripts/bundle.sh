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
# grant to the *designated requirement* — which for ad-hoc is `cdhash H"..."`, i.e. the code hash.
# So an ad-hoc rebuild silently revokes the grant, leaving a ticked checkbox and an app that never
# gets past Permissions.waitForAccessibility. Any certificate yields
# `certificate leaf = H"..."` instead, which is identical across rebuilds.
#
# Best available wins, so this works on a maintainer's Mac and a fresh clone alike:
#   1. SPACIAL_SIGN_IDENTITY, if set
#   2. Developer ID Application — Apple-issued, and the only one other Macs will run
#   3. Apple Development     — works with a free Apple ID, local only
#   4. SpacialShell Dev      — self-signed; see Scripts/README for the one-liner that makes it
#   5. ad-hoc, with a warning
#
# Queried without `find-identity -v`: a self-signed root reports CSSMERR_TP_NOT_TRUSTED and is
# filtered out by -v, yet signs perfectly well. Trust governs Gatekeeper verification, not signing.
identity_matching() {
    security find-identity -p codesigning 2>/dev/null \
        | sed -n 's/^ *[0-9]*) [0-9A-F]* "\(.*\)".*$/\1/p' \
        | grep -F "$1" | head -1
}

if [ -n "${SPACIAL_SIGN_IDENTITY:-}" ]; then
    SIGN="$SPACIAL_SIGN_IDENTITY"
else
    SIGN=""
    for candidate in "Developer ID Application:" "Apple Development:" "SpacialShell Dev"; do
        found=$(identity_matching "$candidate")
        if [ -n "$found" ]; then SIGN="$found"; break; fi
    done
    if [ -z "$SIGN" ]; then
        SIGN="-"
        echo "bundle.sh: no code-signing identity found; signing ad-hoc." >&2
        echo "bundle.sh: the Accessibility grant will not survive this rebuild — see Scripts/README." >&2
    fi
fi

# An Apple-issued identity fetches a secure timestamp from Apple by default, which needs the
# network and fails the whole build when it is unreachable ("A timestamp was expected but was not
# found"). A timestamp only matters for notarised distribution — it is what keeps a signature valid
# after the certificate expires — so dev bundles skip it and package-dmg.sh turns it back on.
TS="${SPACIAL_TIMESTAMP:-none}"
if [ "$TS" = "none" ]; then TSFLAG="--timestamp=none"; else TSFLAG="--timestamp"; fi

codesign --force --sign "$SIGN" $TSFLAG "$APP/Contents/MacOS/spacialctl"
codesign --force --sign "$SIGN" $TSFLAG --identifier sh.emu.SpacialShell "$APP"
echo "built $APP (signed: $SIGN)"
