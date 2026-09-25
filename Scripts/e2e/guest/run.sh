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

# 0. macOS's Tips daemon posts a persistent "See what's new" banner half an hour after boot, into
#    whatever is on screen then. A run can last that long, so it is switched off before anything.
launchctl disable "gui/$(id -u)/com.apple.tipsd" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.apple.tipsd" 2>/dev/null || true

# 1. Build from a private copy: the share is read-only, and .build must not leak between host and
#    guest (different SDKs, different paths).
rsync -a --delete --exclude .build --exclude build --exclude .git --exclude .claude --exclude .remember "$SHARE/repo/" "$SRC/"
cd "$SRC"
# Last run's build products (e2e.sh's cache share), if they were built by this same OS and
# toolchain. SwiftPM rebuilds whatever the rsync changed; the untouched packages stay built.
CACHE="$SHARE/cache"
KEY="build-$( (sw_vers -buildVersion; swift --version 2>&1) | shasum | cut -c1-12).tar"
if [ -f "$CACHE/$KEY" ]; then
    echo "guest: reusing build products ($KEY)"
    tar -xf "$CACHE/$KEY"
fi
rm -rf .build/e2e   # runner.py's helpers: compiled from this checkout, never from a cache
t0=$SECONDS
Scripts/bundle.sh 2>&1 | tail -3      # no certificate in the guest: ad-hoc signed, which is fine —
                                      # the grant below is written against this exact build
echo "guest: build took $((SECONDS - t0)) s"
if [ -d "$CACHE" ]; then
    tar -cf "$CACHE/$KEY.$$.partial" --exclude .build/e2e .build && mv "$CACHE/$KEY.$$.partial" "$CACHE/$KEY"
    find "$CACHE" -name 'build-*.tar' ! -name "$KEY" -delete   # one toolchain's worth, not a pile
fi
pkill -x SpacialShell 2>/dev/null || true
sudo rm -rf "$APP"
sudo cp -R build/SpacialShell.app "$APP"

# 2. Grant Accessibility and Screen Recording to this build. An ad-hoc designated requirement is
#    the cdhash, which changes every build, so the app's rows are rewritten each run with the
#    build's own csreq (the golden image cannot bake them). The runner's own grants
#    (tart-guest-agent: Accessibility, Screen Recording) are baked in by golden.sh. Needs SIP off — golden.sh checks.
REQ="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^#\{0,1\} *designated => //p')"
echo "$REQ" | csreq -r- -b /tmp/spacial.csreq
HEX="$(xxd -p /tmp/spacial.csreq | tr -d '\n')"
for svc in kTCCServiceAccessibility kTCCServiceScreenCapture; do
    sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
        "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags)
         VALUES ('$svc', 'sh.emu.SpacialShell', 0, 2, 4, 1, X'$HEX', 0);"
done
sudo killall tccd 2>/dev/null || true   # drop tccd's cache; launchd restarts it on demand

# macOS 15+ also asks, on top of the TCC row, whether a client may "bypass the system private
# window picker" (replayd), and asks again every month. For the app the dialog lands in every
# screenshot; for tart-guest-agent (the runner's screencapture) it comes due a month after the
# golden image was provisioned. So both are marked as alerted far in the future. replayd keys an
# app by bundle id and a bare binary by its real path.
AGENT="$(realpath /opt/homebrew/bin/tart-guest-agent)" python3 - <<'PY'
import datetime, os, plistlib
p = os.path.expanduser("~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist")
d = plistlib.load(open(p, "rb")) if os.path.exists(p) else {}
far = datetime.datetime(3000, 1, 1)
for key in ("sh.emu.SpacialShell", os.environ["AGENT"]):
    d[key] = {"kScreenCaptureApprovalLastAlerted": far, "kScreenCaptureApprovalLastUsed": far,
              "kScreenCapturePrivacyHintDate": far}
plistlib.dump(d, open(p, "wb"))
PY
killall replayd 2>/dev/null || true

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
