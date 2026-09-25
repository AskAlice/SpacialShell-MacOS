#!/bin/bash
# Builds the golden Tart VM that every `e2e.sh --vm` run clones (#38). Run once; re-run to rebuild.
#
#   Scripts/e2e/golden.sh [--dry-run]
#
# DISK: pulls a macOS base image — tens of GB. It refuses to start with less than
# SPACIAL_E2E_GOLDEN_MIN_FREE_GB (default 80) free under TART_HOME. Point TART_HOME at an external
# volume if the internal disk is short:  TART_HOME=/Volumes/Scratch/tart Scripts/e2e/golden.sh
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
DRY=""
[ "${1:-}" = --dry-run ] && DRY=1
run() { if [ -n "$DRY" ]; then echo "+ $*"; else "$@"; fi; }

# The guard runs in --dry-run too: it is the one thing that must never be skipped.
probe="$TART_DIR"; while [ ! -d "$probe" ]; do probe="$(dirname "$probe")"; done
FREE="$(df -g "$probe" | awk 'NR==2 {print $4}')"
echo "golden: TART_HOME=$TART_DIR on $(df "$probe" | awk 'NR==2 {print $1}'), ${FREE} GB free (need ${MIN_FREE_GB})"
if [ "$FREE" -lt "$MIN_FREE_GB" ]; then
    echo "golden: refusing to pull $IMAGE — not enough disk. Free space or set TART_HOME to an external volume." >&2
    [ -n "$DRY" ] || exit 4
    echo "golden: (dry run continues so the plan is visible)" >&2
fi
[ -n "$DRY" ] || command -v tart >/dev/null || { echo "golden: brew install cirruslabs/cli/tart" >&2; exit 4; }

# 1. Pull + clone. `tart clone` of a remote image pulls it into TART_HOME/cache/OCIs first.
run tart delete "$GOLDEN" 2>/dev/null || true
run tart clone "$IMAGE" "$GOLDEN"
# Single 1920x1080 display: the harness is scoped to single-display scenarios (multi-display,
# #32/#33, cannot be exercised in a VM). 60 GB leaves room for the Swift build on top of the OS.
run tart set "$GOLDEN" --cpu 4 --memory 8192 --display 1920x1080 --disk-size 60

# 2. Boot and provision.
if [ -n "$DRY" ]; then
    echo "+ tart run --no-graphics $GOLDEN &"
else
    tart run --no-graphics "$GOLDEN" >/dev/null 2>&1 &
    TART_PID=$!
    trap 'tart stop "$GOLDEN" >/dev/null 2>&1 || true; wait $TART_PID 2>/dev/null || true' EXIT
    for i in $(seq 1 90); do tart exec "$GOLDEN" true 2>/dev/null && break; sleep 2
        [ "$i" = 90 ] && { echo "golden: guest agent never answered" >&2; exit 5; }; done
fi
if [ -n "$DRY" ]; then
    echo "+ tart exec -i $GOLDEN /bin/bash -s < $HERE/guest/provision.sh"
else
    tart exec -i "$GOLDEN" /bin/bash -s < "$HERE/guest/provision.sh"
fi
run tart stop "$GOLDEN"
echo "golden: $GOLDEN ready. Run Scripts/e2e/e2e.sh --vm"
