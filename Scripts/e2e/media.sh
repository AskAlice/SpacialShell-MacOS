#!/bin/bash
# Turns a `record` step's frames into README/PR loops (#8): OUT.gif and OUT.webp.
#
#   Scripts/e2e/media.sh FRAMES_DIR OUT [WIDTH] [FPS] [CROP] [START] [LENGTH]     e.g.
#   Scripts/e2e/media.sh .build/e2e/vm-…/overview/overview docs/media/live-overview 720 12
#
# CROP is ffmpeg's w:h:x:y in the recording's pixels (1024 wide), for a close-up ("" for none).
# START and LENGTH (seconds) keep only that stretch of the recording, so a loop stays under 10 s
# without the dead time around the action. WEBP_Q (default 60) is the webp quality.
# FRAMES_DIR is what record.swift wrote: fNNNNN.png plus times.txt. ScreenCaptureKit only sends a
# frame when the screen changed, so each frame is held until the next one's time: the loop plays
# at the speed it was recorded. Needs ffmpeg; the webp needs img2webp (libwebp), because
# Homebrew's ffmpeg is built without libwebp.
set -euo pipefail
DIR="$1" OUT="$2" W="${3:-720}" FPS="${4:-12}" CROP="${5:-}" START="${6:-0}" LEN="${7:-}"
LIST="$(mktemp -t media).ffconcat"
FRAMES="$(mktemp -d -t media)"
trap 'rm -rf "$LIST" "$FRAMES"' EXIT
python3 - "$DIR" "$START" "$LEN" > "$LIST" <<'PY'
import os, sys
d = os.path.abspath(sys.argv[1])
start = float(sys.argv[2])
rows = [(n, float(t)) for n, t in (l.split() for l in open(os.path.join(d, "times.txt")) if l.strip())]
end = start + float(sys.argv[3]) if sys.argv[3] else rows[-1][1] + 1.0   # untrimmed: hold the last frame 1 s
# The frame on screen at START opens the loop; each frame is held until the next one (or END).
first = max([i for i, (_, t) in enumerate(rows) if t <= start] or [0])
keep = [(n, max(t, start)) for n, t in rows[first:] if t < end]
print("ffconcat version 1.0")
for i, (name, t) in enumerate(keep):
    nxt = keep[i + 1][1] if i + 1 < len(keep) else end
    print(f"file '{os.path.join(d, name)}'\nduration {max(nxt - t, 0.02):.3f}")
print(f"file '{os.path.join(d, keep[-1][0])}'")
PY
SCALE="fps=$FPS,${CROP:+crop=$CROP,}scale=$W:-1:flags=lanczos"
# The list's closing repeat of the last frame would otherwise be held as long as the frame before
# it (seconds, after a still stretch): cap the output at the listed length.
TOTAL="$(awk '/^duration/ {s += $2} END {print s}' "$LIST")"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST" \
    -vf "$SCALE,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    -t "$TOTAL" -loop 0 "$OUT.gif"
if command -v img2webp >/dev/null; then
    ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST" -vf "$SCALE" -t "$TOTAL" "$FRAMES/w%05d.png"
    img2webp -loop 0 -lossy -q "${WEBP_Q:-60}" -m 6 -d $((1000 / FPS)) "$FRAMES"/w*.png -o "$OUT.webp" >/dev/null
else
    echo "media: no img2webp (brew install webp); wrote $OUT.gif only" >&2
fi
ls -l "$OUT".* | awk '{print $5, $9}'
