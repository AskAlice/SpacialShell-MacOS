#!/bin/bash
# End-to-end scenarios against the real shell (#38). One entry point, two places to run:
#
#   Scripts/e2e/e2e.sh --host [--record] [scenario.scn ...]   the app installed and running here
#   Scripts/e2e/e2e.sh --vm   [--record] [--keep] [--dry-run] [scenario.scn ...]
#                                                              a throwaway clone of the golden
#                                                              Tart image (Scripts/e2e/golden.sh)
#   Scripts/e2e/e2e.sh --check                                 parse every scenario, run nothing
#   --suite NAME                                               the scenarios in scenarios/NAME/ (e.g.
#                                                              snapshots, #81) instead of scenarios/*.scn
#
# No scenario or suite given = all of Scripts/e2e/scenarios/*.scn. Artefacts (screenshots, diffs,
# state.ndjson transcript, shell.log) land in .build/e2e/<mode>-<timestamp>/<scenario>/.
# See Scripts/e2e/README.md.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

MODE="" RECORD="" KEEP="" DRY="" SUITE=""
SCENARIOS=()
prev=""
for a in "$@"; do
    if [ "$prev" = --suite ]; then SUITE="$a"; prev=""; continue; fi
    prev="$a"
    case "$a" in
        --suite) ;;
        --host|--vm|--check) MODE="${a#--}" ;;
        --record) RECORD=--record ;;
        --keep) KEEP=1 ;;
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) SCENARIOS+=("$a") ;;
    esac
done
[ -n "$MODE" ] || { sed -n '2,15p' "$0"; exit 2; }
if [ -n "$SUITE" ]; then
    [ -d "$HERE/scenarios/$SUITE" ] || { echo "e2e: no suite scenarios/$SUITE" >&2; exit 2; }
    SCENARIOS+=("$HERE/scenarios/$SUITE"/*.scn)
fi
[ ${#SCENARIOS[@]} -gt 0 ] || SCENARIOS=("$HERE"/scenarios/*.scn)

if [ "$MODE" = check ]; then
    exec python3 "$HERE/runner.py" --mode host --out /dev/null --check "${SCENARIOS[@]}"
fi

OUT="$REPO/.build/e2e/$MODE-$(date +%Y%m%d-%H%M%S)"

if [ "$MODE" = host ]; then
    CTL="${SPACIALCTL:-/Applications/SpacialShell.app/Contents/MacOS/spacialctl}"
    "$CTL" version >/dev/null || { echo "e2e: SpacialShell is not running ($CTL)" >&2; exit 3; }
    mkdir -p "$OUT"
    exec python3 "$HERE/runner.py" --mode host --out "$OUT" $RECORD "${SCENARIOS[@]}"
fi

# ---- --vm --------------------------------------------------------------------------------------
# Tart keeps images and clones under TART_HOME (default ~/.tart); point it at an external volume
# to keep the internal disk free. A clone of a local VM is an APFS copy-on-write clone, so a run
# costs only what the guest writes (build products, screenshots) — a few GB, not the image size.
GOLDEN="${SPACIAL_E2E_GOLDEN:-spacial-e2e-golden}"
VM="spacial-e2e-$$"
TART_DIR="${TART_HOME:-$HOME/.tart}"
MIN_FREE_GB="${SPACIAL_E2E_MIN_FREE_GB:-15}"

run() { if [ -n "$DRY" ]; then echo "+ $*"; else "$@"; fi; }

free_gb() { df -g "$1" | awk 'NR==2 {print $4}'; }
probe="$TART_DIR"; while [ ! -d "$probe" ]; do probe="$(dirname "$probe")"; done
FREE="$(free_gb "$probe")"
if [ "$FREE" -lt "$MIN_FREE_GB" ]; then
    echo "e2e: only ${FREE} GB free under $TART_DIR (need ${MIN_FREE_GB}). Set TART_HOME to a bigger volume." >&2
    exit 4
fi

if [ -z "$DRY" ]; then
    command -v tart >/dev/null || { echo "e2e: tart not installed (brew install cirruslabs/cli/tart)" >&2; exit 4; }
    tart list --format json | python3 -c "import json,sys; sys.exit(0 if any(v['Name']=='$GOLDEN' for v in json.load(sys.stdin)) else 1)" \
        || { echo "e2e: no golden VM '$GOLDEN' — run Scripts/e2e/golden.sh first" >&2; exit 4; }
    # Apple's licence: at most two macOS VMs per Mac. This run adds one.
    RUNNING="$(tart list --format json | python3 -c "import json,sys; print(sum(v.get('State')=='running' for v in json.load(sys.stdin)))")"
    [ "$RUNNING" -lt 2 ] || { echo "e2e: $RUNNING macOS VMs already running; the licence allows two" >&2; exit 4; }
fi

mkdir -p "$OUT"
# The guest's build products, kept between runs (#81): every clone starts from the golden image
# with no .build, and a cold release build of the OpenTelemetry packages is most of a run.
# guest/run.sh unpacks it before building and packs it afterwards; SwiftPM's own incremental
# build decides what is stale (the rsync keeps the checkout's mtimes). Keyed in the guest by
# macOS build and Swift version, so a rebuilt golden image never reuses foreign products.
CACHE="${SPACIAL_E2E_CACHE:-$REPO/.build/e2e/guest-cache}"
mkdir -p "$CACHE"
cleanup() {
    run tart stop "$VM" >/dev/null 2>&1 || true
    if [ -z "$KEEP" ]; then run tart delete "$VM" >/dev/null 2>&1 || true
    else echo "e2e: kept $VM (tart run $VM / tart delete $VM)"; fi
    [ -n "${TART_PID:-}" ] && wait "$TART_PID" 2>/dev/null || true
}
trap cleanup EXIT

run tart clone "$GOLDEN" "$VM"
# The repo goes in read-only (the guest builds from its own copy); artefacts come out through
# the writable share, so there is nothing to copy back afterwards.
if [ -n "$DRY" ]; then
    echo "+ tart run --no-graphics --dir=repo:$REPO:ro --dir=out:$OUT --dir=cache:$CACHE $VM &"
else
    tart run --no-graphics "--dir=repo:$REPO:ro" "--dir=out:$OUT" "--dir=cache:$CACHE" "$VM" >"$OUT/tart-run.log" 2>&1 &
    TART_PID=$!
    echo "e2e: waiting for the guest agent…"
    for i in $(seq 1 90); do tart exec "$VM" true 2>/dev/null && break; sleep 2
        [ "$i" = 90 ] && { echo "e2e: guest agent never answered" >&2; exit 5; }; done
fi

SHARE="/Volumes/My Shared Files"
GUEST_SCENARIOS=()
for s in "${SCENARIOS[@]}"; do
    abs="$(cd "$(dirname "$s")" && pwd)/$(basename "$s")"
    GUEST_SCENARIOS+=("$SHARE/repo/${abs#"$REPO"/}")
done
status=0
run tart exec "$VM" /bin/bash "$SHARE/repo/Scripts/e2e/guest/run.sh" $RECORD "${GUEST_SCENARIOS[@]}" || status=$?

# --record in the guest writes references into its own copy of the repo; bring them home.
if [ -n "$RECORD" ] && [ -d "$OUT/references" ]; then
    run cp -R "$OUT/references/." "$HERE/references/"
fi
echo "e2e: artefacts in $OUT"
exit $status
