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
# Release version (package-dmg.sh passes it): Sparkle compares CFBundleVersion, so every release
# must carry its own. Dev bundles keep the plist's.
if [ -n "${SPACIAL_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SPACIAL_VERSION" \
        -c "Set :CFBundleVersion $SPACIAL_VERSION" "$APP/Contents/Info.plist"
elif [ -z "${SPACIAL_UPDATES:-}" ]; then
    # A dev bundle keeps the plist's 0.1.0, so its updater would offer to replace it with the
    # latest release. Without SUPublicEDKey the app never starts Sparkle (Updates.swift);
    # SPACIAL_UPDATES=1 keeps the key, to try the updater from a dev build.
    /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$APP/Contents/Info.plist" 2>/dev/null || true
fi
# #58: Sparkle is a binary framework SwiftPM leaves next to the executable. An app looks for
# frameworks in Contents/Frameworks, so copy it there and give the executable that rpath.
mkdir -p "$APP/Contents/Frameworks"
cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/SpacialShell"
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
    # Pinned locally (Scripts/sign-identity, gitignored): this Mac has two Developer ID certificates, and
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

# Hardened runtime (notarisation requires it) whenever there is a real identity. Not ad-hoc: library
# validation wants the app and Sparkle.framework to share a team ID, and ad-hoc has none, so an
# ad-hoc hardened app would refuse to load Sparkle and die at launch. No entitlements file:
# Accessibility and Screen Recording are TCC grants, and nothing here needs a cs.* exception
# (no JIT, no unsigned executable memory, no DYLD variables, no third-party plug-ins).
if [ "$SIGN" = "-" ]; then RT=""; else RT="--options runtime"; fi

# Inside out, as Sparkle documents: XPC services, helpers, then the framework. Sparkle arrives
# signed by its own team; re-signing puts it under ours, which library validation requires.
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign "$SIGN" $TSFLAG $RT "$SPK/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN" $TSFLAG $RT --preserve-metadata=entitlements "$SPK/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN" $TSFLAG $RT "$SPK/Autoupdate"
codesign --force --sign "$SIGN" $TSFLAG $RT "$SPK/Updater.app"
codesign --force --sign "$SIGN" $TSFLAG $RT "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN" $TSFLAG $RT "$APP/Contents/MacOS/spacialctl"
codesign --force --sign "$SIGN" $TSFLAG $RT --identifier sh.emu.SpacialShell "$APP"
echo "built $APP (signed: $SIGN)"
