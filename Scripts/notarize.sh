#!/bin/sh
# #16: a DMG that opens on someone else's Mac. Developer ID + hardened runtime + secure timestamp
# (package-dmg.sh → bundle.sh), then notarise and staple the app (#152), build the DMG around the
# stapled app, sign the DMG, notarise it, staple its own ticket, and check both.
#
# The app gets its own ticket so a copy taken out of the DMG (drag to /Applications,
# `brew install --cask`) passes Gatekeeper offline on first launch, not only the mounted DMG.
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
set --

Scripts/package-dmg.sh --app-only
APP=build/SpacialShell.app

# The identity bundle.sh actually used, as the SHA-1 of the leaf certificate: signing by hash is
# unambiguous where a common name is not (this Mac has two Developer IDs; see Scripts/sign-identity).
WORK=$(mktemp -d)
MNT=""
cleanup() {
    [ -n "$MNT" ] && hdiutil detach "$MNT" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT
codesign -d --extract-certificates="$WORK/c" "$APP" 2>/dev/null || true
if ! codesign -dvv "$APP" 2>&1 | grep -q "^Authority=Developer ID Application:"; then
    echo "notarize.sh: $APP is not signed with a Developer ID Application certificate;" >&2
    echo "notarize.sh: Apple only notarises Developer ID. See docs/release.md." >&2
    exit 1
fi
SIGN=$(shasum -a 1 "$WORK/c0" | cut -d" " -f1 | tr a-f A-F)
codesign --verify --deep --strict --verbose=2 "$APP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    set -- --keychain-profile "$NOTARY_PROFILE"
elif [ -n "${ASC_KEY_PATH:-}" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    set -- --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
fi

# notarise FILE CREDENTIALS... — submits, waits, and on anything but Accepted prints Apple's log
# (it names every offending binary and why; its developerLogUrl is the one to keep) and fails.
notarise() {
    file=$1; shift
    echo "notarize.sh: submitting $file to Apple's notary service (this waits)"
    result="$WORK/submit.json"
    xcrun notarytool submit "$file" "$@" --wait --output-format json > "$result" || true
    status=$(plutil -extract status raw -o - "$result" 2>/dev/null || echo "no response")
    id=$(plutil -extract id raw -o - "$result" 2>/dev/null || echo "")
    if [ "$status" != "Accepted" ]; then
        echo "notarize.sh: notarisation of $file FAILED: status=$status id=${id:-none}" >&2
        cat "$result" >&2
        [ -n "$id" ] && xcrun notarytool log "$id" "$@" >&2 || true
        exit 1
    fi
    echo "notarize.sh: $file accepted (submission $id)"
}

# 1. The app. notarytool takes a zip, not a bundle; the ticket is keyed on the cdhash, so it
#    staples onto the bundle the zip was made from.
if [ $# -gt 0 ]; then
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/SpacialShell.zip"
    notarise "$WORK/SpacialShell.zip" "$@"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
fi

# 2. The DMG, around the (stapled) app.
Scripts/package-dmg.sh --dmg-only
DMG=$(ls -t build/SpacialShell-*.dmg | head -1)
codesign --force --sign "$SIGN" --timestamp "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
echo "notarize.sh: signed $DMG ($SIGN)"

if [ $# -eq 0 ]; then
    echo "notarize.sh: Gatekeeper's view of the unnotarised build:"
    spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 || true
    spctl -a -vv -t exec "$APP" 2>&1 || true
    echo "notarisation skipped: no credentials (set NOTARY_PROFILE, or ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID)." >&2
    echo "notarize.sh: $DMG is Developer ID signed but NOT notarised — Gatekeeper rejects it on other Macs." >&2
    exit "$REQUIRE"
fi

notarise "$DMG" "$@"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"

# 3. The app as it ships: mounted from the DMG, it carries its own stapled ticket (#152).
MNT=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
xcrun stapler validate "$MNT/SpacialShell.app"
spctl -a -vv -t exec "$MNT/SpacialShell.app"
hdiutil detach "$MNT" >/dev/null
rmdir "$MNT" 2>/dev/null || true
MNT=""
echo "notarize.sh: $DMG and the app inside it are signed, notarised and stapled"
