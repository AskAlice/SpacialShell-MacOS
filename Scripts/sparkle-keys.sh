#!/bin/sh
# #58: the EdDSA keypair Sparkle verifies updates with. One-time, on the maintainer's Mac.
#
#   Scripts/sparkle-keys.sh                 create the key (or reuse the existing one) and write
#                                           its PUBLIC half into Resources/Info.plist (SUPublicEDKey)
#   Scripts/sparkle-keys.sh --upload-secret also store the PRIVATE half as the GitHub Actions
#                                           secret SPARKLE_ED_PRIVATE_KEY, via gh, never on screen
#
# The private key lives in the login keychain (item "Private key for signing Sparkle updates"),
# put there by Sparkle's own generate_keys. It is never printed and never written into the repo.
# Lose it and installed copies can no longer be updated — back the keychain item up.
set -e
cd "$(dirname "$0")/.."

BIN=.build/artifacts/sparkle/Sparkle/bin
[ -x "$BIN/generate_keys" ] || swift package resolve
[ -x "$BIN/generate_keys" ] || { echo "sparkle-keys.sh: $BIN/generate_keys not found" >&2; exit 1; }

# Creates the key if the keychain has none; otherwise leaves it alone. Prints only the public key.
"$BIN/generate_keys" >/dev/null
PUB=$("$BIN/generate_keys" -p)
PLIST=Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUB" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUB" "$PLIST"
echo "sparkle-keys.sh: SUPublicEDKey = $PUB (in $PLIST — commit it; it is public)"

if [ "${1:-}" = "--upload-secret" ]; then
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    "$BIN/generate_keys" -x "$TMP/key"
    gh secret set SPARKLE_ED_PRIVATE_KEY < "$TMP/key"
    echo "sparkle-keys.sh: stored the private key as the SPARKLE_ED_PRIVATE_KEY secret"
fi
