#!/bin/bash
# Runs INSIDE the Tart guest, via `tart exec` from e2e.sh --vm. Build, install, grant, launch,
# run the scenarios. The repo is mounted read-only at $SHARE/repo; artefacts go to $SHARE/out.
#
#   guest/run.sh [--record] SCENARIO_PATH...
set -euo pipefail
SHARE="/Volumes/My Shared Files"
OUT="$SHARE/out"
SRC="$HOME/spacial-shell"
APP=/Applications/SpacialShell.app
RECORD=""
[ "${1:-}" = --record ] && { RECORD=--record; shift; }

echo "guest: $(sw_vers -productVersion), $(swift --version 2>&1 | head -1)"

# 1. Build from a private copy: the share is read-only, and .build must not leak between host and
#    guest (different SDKs, different paths).
rsync -a --delete --exclude .build --exclude build --exclude .claude "$SHARE/repo/" "$SRC/"
cd "$SRC"
Scripts/bundle.sh 2>&1 | tail -3      # no certificate in the guest: ad-hoc signed, which is fine —
                                      # the grant below is written against this exact build
pkill -x SpacialShell 2>/dev/null || true
sudo rm -rf "$APP"
sudo cp -R build/SpacialShell.app "$APP"

# 2. Grant Accessibility and Screen Recording to this build. An ad-hoc designated requirement is
#    the cdhash, which changes every build, so the app's rows are rewritten each run with the
#    build's own csreq (the golden image cannot bake them). The runner's own grants
#    (tart-guest-agent, osascript) are baked in by golden.sh. Needs SIP off — golden.sh checks.
REQ="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
echo "$REQ" | csreq -r- -b /tmp/spacial.csreq
HEX="$(xxd -p /tmp/spacial.csreq | tr -d '\n')"
for svc in kTCCServiceAccessibility kTCCServiceScreenCapture; do
    sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
        "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags)
         VALUES ('$svc', 'sh.emu.SpacialShell', 0, 2, 4, 1, X'$HEX', 0);"
done
sudo killall tccd 2>/dev/null || true   # drop tccd's cache; launchd restarts it on demand

# 3. Launch into the logged-in GUI session (the golden image auto-logs-in `admin`) and wait for
#    the control socket.
open "$APP"
for i in $(seq 1 60); do "$APP/Contents/MacOS/spacialctl" version >/dev/null 2>&1 && break; sleep 1
    [ "$i" = 60 ] && { echo "guest: SpacialShell never opened its socket" >&2; exit 3; }; done
sleep 2   # first reconcile

# 4. Scenarios. Paths arrive as $SHARE/repo/…; run them from the private copy.
SCN=()
for s in "$@"; do SCN+=("$SRC/${s#"$SHARE/repo/"}"); done
status=0
python3 Scripts/e2e/runner.py --mode vm --out "$OUT" $RECORD "${SCN[@]}" || status=$?

# 5. Anything the host wants back that is not already under $OUT.
if [ -n "$RECORD" ] && [ -d Scripts/e2e/references ]; then
    mkdir -p "$OUT/references" && cp -R Scripts/e2e/references/. "$OUT/references/"
fi
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "sh.emu.SpacialShell"' --info \
    > "$OUT/shell-full.log" 2>/dev/null || true
exit $status
