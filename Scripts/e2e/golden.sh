#!/bin/bash
# Builds the golden Tart VM that every `e2e.sh --vm` run clones (#38). Run once; re-run to rebuild.
#
#   Scripts/e2e/golden.sh [--dry-run]            clone the base image and provision it
#   Scripts/e2e/golden.sh --update [--dry-run]   re-run guest/provision.sh on the existing golden
#                                                (#154), after cloning it to <golden>-prev
#
# DISK: pulls a macOS base image — tens of GB. It refuses to start with less than
# SPACIAL_E2E_GOLDEN_MIN_FREE_GB (default 80) free under TART_HOME. Point TART_HOME at an external
# volume if the internal disk is short:  TART_HOME=/Volumes/Scratch/tart Scripts/e2e/golden.sh
# --update pulls nothing (the backup is an APFS copy-on-write clone), so it skips that check.
#
# Env: SPACIAL_E2E_IMAGE (default ghcr.io/cirruslabs/macos-tahoe-base:latest — has Homebrew, the
# Command Line Tools, tart-guest-agent, auto-login as admin/admin and SIP disabled),
# SPACIAL_E2E_GOLDEN (VM name, default spacial-e2e-golden).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${SPACIAL_E2E_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
GOLDEN="${SPACIAL_E2E_GOLDEN:-spacial-e2e-golden}"
TART_DIR="${TART_HOME:-$HOME/.tart}"
MIN_FREE_GB="${SPACIAL_E2E_GOLDEN_MIN_FREE_GB:-80}"
DRY="" UPDATE=""
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        --update) UPDATE=1 ;;
        *) sed -n '2,15p' "$0"; exit 2 ;;
    esac
done
run() { if [ -n "$DRY" ]; then echo "+ $*"; else "$@"; fi; }
[ -n "$DRY" ] || command -v tart >/dev/null || { echo "golden: brew install cirruslabs/cli/tart" >&2; exit 4; }

if [ -n "$UPDATE" ]; then
    # Provisioning is idempotent, so an update is the same script on the image as it stands. The
    # previous image stays as <golden>-prev until the new one is verified (an e2e run passes):
    # then `tart delete <golden>-prev`, or to roll back, `tart delete <golden>` and
    # `tart rename <golden>-prev <golden>`.
    if [ -z "$DRY" ]; then
        names="$(tart list --format json | python3 -c 'import json,sys; print("\n".join(v["Name"] for v in json.load(sys.stdin)))')"
        grep -qx "$GOLDEN" <<<"$names" || { echo "golden: no $GOLDEN to update; run golden.sh" >&2; exit 4; }
        ! grep -qx "$GOLDEN-prev" <<<"$names" || {
            echo "golden: $GOLDEN-prev exists (an unverified earlier update?). Delete it first." >&2; exit 4; }
    fi
    run tart clone "$GOLDEN" "$GOLDEN-prev"
else
    # The guard runs in --dry-run too: it is the one thing that must never be skipped.
    probe="$TART_DIR"; while [ ! -d "$probe" ]; do probe="$(dirname "$probe")"; done
    FREE="$(df -g "$probe" | awk 'NR==2 {print $4}')"
    echo "golden: TART_HOME=$TART_DIR on $(df "$probe" | awk 'NR==2 {print $1}'), ${FREE} GB free (need ${MIN_FREE_GB})"
    if [ "$FREE" -lt "$MIN_FREE_GB" ]; then
        echo "golden: refusing to pull $IMAGE — not enough disk. Free space or set TART_HOME to an external volume." >&2
        [ -n "$DRY" ] || exit 4
        echo "golden: (dry run continues so the plan is visible)" >&2
    fi

    # 1. Pull + clone. `tart clone` of a remote image pulls it into TART_HOME/cache/OCIs first.
    run tart delete "$GOLDEN" 2>/dev/null || true
    run tart clone "$IMAGE" "$GOLDEN"
    # Single 1920x1080 display: the harness is scoped to single-display scenarios (multi-display,
    # #32/#33, cannot be exercised in a VM). 60 GB leaves room for the Swift build on top of the OS.
    run tart set "$GOLDEN" --cpu 4 --memory 8192 --display 1920x1080 --disk-size 60
fi

# 2. Boot and provision. The wait is agent-probe.py, not repeated `tart exec` calls: those kill
# tart's control socket against a booting guest (#149, see e2e.sh).
if [ -n "$DRY" ]; then
    echo "+ tart run --no-graphics $GOLDEN &"
else
    LOG="$(mktemp -t golden-run)"
    tart run --no-graphics "$GOLDEN" >"$LOG" 2>&1 &
    TART_PID=$!
    trap 'tart stop "$GOLDEN" >/dev/null 2>&1 || true; wait $TART_PID 2>/dev/null || true' EXIT
    t0=$SECONDS
    until python3 "$HERE/agent-probe.py" "$TART_DIR/vms/$GOLDEN/control.sock" \
            && perl -e 'alarm 30; exec @ARGV' tart exec "$GOLDEN" true 2>/dev/null; do
        kill -0 "$TART_PID" 2>/dev/null && ! grep -q "control socket" "$LOG" \
            || { echo "golden: tart run failed:" >&2; sed 's/^/  | /' "$LOG" >&2; exit 5; }
        [ $((SECONDS - t0)) -lt 600 ] || { echo "golden: guest agent never answered" >&2; exit 5; }
        sleep 3
    done
fi
if [ -n "$DRY" ]; then
    echo "+ tart exec -i $GOLDEN /bin/bash -s < $HERE/guest/provision.sh"
else
    tart exec -i "$GOLDEN" /bin/bash -s < "$HERE/guest/provision.sh"
fi
run tart stop "$GOLDEN"
if [ -n "$UPDATE" ]; then
    echo "golden: $GOLDEN updated; the previous image is $GOLDEN-prev. Verify with Scripts/e2e/e2e.sh --vm,"
    echo "golden: then tart delete $GOLDEN-prev."
else
    echo "golden: $GOLDEN ready. Run Scripts/e2e/e2e.sh --vm"
fi
