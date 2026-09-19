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
# Resolves a name prefix to a SHA-1 hash, and signs by hash rather than by name. Two certificates
# can share a common name — renewing a Developer ID gives you exactly that — and `codesign --sign`
# on an ambiguous name fails outright, which is a confusing way to discover you renewed something.
identity_hashes() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/^ *[0-9]*) \([0-9A-F][0-9A-F]*\) "\(.*\)"$/\1 \2/p' \
        | grep -F " $1" | cut -d" " -f1
}

PINNED=$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' Scripts/sign-identity 2>/dev/null | head -1 | tr -d '[:space:]')

if [ -n "${SPACIAL_SIGN_IDENTITY:-}" ]; then
    SIGN="$SPACIAL_SIGN_IDENTITY"
elif [ -n "$PINNED" ] && security find-identity -p codesigning 2>/dev/null | grep -qi "$PINNED"; then
    # Pinned in the repo (Scripts/sign-identity): this Mac has two Developer ID certificates, and
    # picking the wrong one silently invalidates the Accessibility grant. Only honoured when the
    # certificate is actually present, so a fresh clone elsewhere still falls through to the search.
    SIGN="$PINNED"
else
    SIGN=""
    for candidate in "Developer ID Application:" "Apple Development:" "SpacialShell Dev"; do
        found=$(identity_hashes "$candidate")
        count=$(printf "%s\n" "$found" | grep -c . || true)
        if [ "$count" -gt 1 ]; then
            echo "bundle.sh: $count identities match \"$candidate\" — using the first." >&2
            echo "bundle.sh: set SPACIAL_SIGN_IDENTITY to a SHA-1 hash to choose, or remove the stale one:" >&2
            printf "%s\n" "$found" | sed 's/^/bundle.sh:   /' >&2
        fi
        first=$(printf "%s\n" "$found" | head -1)
        if [ -n "$first" ]; then SIGN="$first"; break; fi
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
