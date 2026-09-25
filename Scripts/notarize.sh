#!/bin/sh
# #16: a DMG that opens on someone else's Mac. Developer ID + hardened runtime + secure timestamp
# (package-dmg.sh → bundle.sh), then sign the DMG, notarise it, staple the ticket, and check it.
#
#   Scripts/notarize.sh [--require-notarization]
#
# Credentials, from the environment and never from the repo — the first that is set wins:
#   NOTARY_PROFILE                         a `xcrun notarytool store-credentials` keychain profile
#   ASC_KEY_PATH + ASC_KEY_ID + ASC_ISSUER_ID  an App Store Connect API key (.p8)
# With neither, everything up to the submission still runs and the DMG is left signed but not
# notarised; the exit code is 0 unless --require-notarization says a notarised DMG was the point.
# VERSION= names the DMG, as for package-dmg.sh.
set -e
cd "$(dirname "$0")/.."

REQUIRE=0
for arg in "$@"; do
    case "$arg" in
        --require-notarization) REQUIRE=1 ;;
        *) echo "usage: $0 [--require-notarization]" >&2; exit 2 ;;
    esac
done

Scripts/package-dmg.sh
APP=build/SpacialShell.app
DMG=$(ls -t build/SpacialShell-*.dmg | head -1)

# The identity bundle.sh actually used, as the SHA-1 of the leaf certificate: signing by hash is
# unambiguous where a common name is not (this Mac has two Developer IDs; see Scripts/sign-identity).
CERTS=$(mktemp -d)
trap 'rm -rf "$CERTS"' EXIT
codesign -d --extract-certificates="$CERTS/c" "$APP" 2>/dev/null || true
if ! codesign -dvv "$APP" 2>&1 | grep -q "^Authority=Developer ID Application:"; then
    echo "notarize.sh: $APP is not signed with a Developer ID Application certificate;" >&2
    echo "notarize.sh: Apple only notarises Developer ID. See docs/release.md." >&2
    exit 1
fi
SIGN=$(shasum -a 1 "$CERTS/c0" | cut -d" " -f1 | tr a-f A-F)

codesign --verify --deep --strict --verbose=2 "$APP"
codesign --force --sign "$SIGN" --timestamp "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
echo "notarize.sh: signed $DMG ($SIGN)"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    set -- --keychain-profile "$NOTARY_PROFILE"
elif [ -n "${ASC_KEY_PATH:-}" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    set -- --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
else
    echo "notarize.sh: Gatekeeper's view of the unnotarised build:"
    spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 || true
    spctl -a -vv -t exec "$APP" 2>&1 || true
    echo "notarisation skipped: no credentials (set NOTARY_PROFILE, or ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID)." >&2
    echo "notarize.sh: $DMG is Developer ID signed but NOT notarised — Gatekeeper rejects it on other Macs." >&2
    exit "$REQUIRE"
fi

echo "notarize.sh: submitting to Apple's notary service (this waits)"
RESULT="$CERTS/submit.json"
xcrun notarytool submit "$DMG" "$@" --wait --output-format json > "$RESULT" || true
STATUS=$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || echo "no response")
ID=$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || echo "")
if [ "$STATUS" != "Accepted" ]; then
    echo "notarize.sh: notarisation FAILED: status=$STATUS id=${ID:-none}" >&2
    cat "$RESULT" >&2
    # The log names every offending binary and why; its developerLogUrl is the one to keep.
    [ -n "$ID" ] && xcrun notarytool log "$ID" "$@" >&2 || true
    exit 1
fi

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"
# The app as Gatekeeper sees it once mounted from the DMG — the ticket covers it by cdhash.
MNT=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
spctl -a -vv -t exec "$MNT/SpacialShell.app" || { hdiutil detach "$MNT" >/dev/null; exit 1; }
hdiutil detach "$MNT" >/dev/null
echo "notarize.sh: $DMG is signed, notarised and stapled"
