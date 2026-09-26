#!/bin/bash
# One measured pass of the #140 re-tile benchmark, run INSIDE the Tart guest by
# Scripts/e2e/scenarios/perf/retile.scn (through `sh` steps, which set E2E_OUT).
#
#   retile-pass.sh begin TAG    note the time; start Instruments' Time Profiler on SpacialShell
#   retile-pass.sh end TAG      stop it; leave TAG.trace and TAG.log (the app's `retile N=…`
#                               lines for the pass) in $E2E_OUT
#
# Instruments comes from the host's Xcode, shared in by `SPACIAL_E2E_XCODE=/Applications/Xcode.app
# Scripts/e2e/e2e.sh --vm …` (the guest has the Command Line Tools only, which have no xctrace).
# Without it the pass still logs its numbers, with no trace.
set -uo pipefail
CMD="$1" TAG="$2"
OUT="${E2E_OUT:?run from an e2e scenario}"
STATE="/tmp/retile-pass-$TAG"
XCODE="/Volumes/My Shared Files/xcode/Contents/Developer"

xctrace() {
    if [ -d "$XCODE" ]; then DEVELOPER_DIR="$XCODE" "$XCODE/usr/bin/xctrace" "$@"
    else xcrun xctrace "$@"; fi
}

case "$CMD" in
begin)
    date '+%Y-%m-%d %H:%M:%S' > "$STATE.t0"
    if xctrace version >/dev/null 2>&1; then
        pid="$(pgrep -x SpacialShell | head -1)"
        # Recorded in the guest's own /tmp (a trace bundle is thousands of small writes), copied
        # out at the end. sudo: Time Profiler's kernel sampling wants root to attach.
        rm -rf "/tmp/$TAG.trace"
        sudo -E env DEVELOPER_DIR="$XCODE" "$XCODE/usr/bin/xctrace" record --template 'Time Profiler' \
            --attach "$pid" --time-limit 120s --output "/tmp/$TAG.trace" \
            > "$STATE.xctrace.log" 2>&1 < /dev/null &
        echo $! > "$STATE.pid"
        # Instruments needs a moment before it samples.
        for _ in $(seq 1 40); do grep -q "Ctrl-C to stop" "$STATE.xctrace.log" 2>/dev/null && break; sleep 0.5; done
        sleep 1
    else
        echo "retile-pass: no xctrace in the guest (set SPACIAL_E2E_XCODE); numbers only" | tee "$STATE.xctrace.log"
    fi
    ;;
end)
    if [ -f "$STATE.pid" ]; then
        pid="$(cat "$STATE.pid")"
        sudo pkill -INT -f "xctrace record.*$TAG.trace" 2>/dev/null
        for _ in $(seq 1 240); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
        rm -rf "$OUT/$TAG.trace"
        [ -d "/tmp/$TAG.trace" ] && sudo cp -R "/tmp/$TAG.trace" "$OUT/$TAG.trace" && sudo chown -R "$(id -u)" "$OUT/$TAG.trace"
    fi
    cp "$STATE.xctrace.log" "$OUT/$TAG.xctrace.log" 2>/dev/null
    sleep 1   # the last landing's log line
    /usr/bin/log show --start "$(cat "$STATE.t0")" --style compact \
        --predicate 'subsystem == "sh.emu.SpacialShell" AND category == "motion"' \
        | grep -E 'retile N=|(switch|retile) (instant|animating)' > "$OUT/$TAG.log"
    echo "retile-pass: $TAG: $(grep -c 'retile N=[0-9]* capture' "$OUT/$TAG.log") re-tiles measured"
    ;;
*) echo "usage: retile-pass.sh begin|end TAG" >&2; exit 2 ;;
esac
