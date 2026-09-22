# Window animation feasibility — measured results

Throwaway probe. Not shipped, not imported by any target, not in `Package.swift`. Public API only:
`nm -u probe` contains no `_AX*`, `SLS*`, `CGS*` or SkyLight symbol (checked on the committed source,
2026-09-12).

```
swiftc -O probe.swift -o probe
./probe all <outdir> 4          # full matrix, 4 reps per condition; JSONL on stdout, summary.txt in <outdir>
ONLY=stepped ./probe all ...    # one half of the matrix (ONLY=overlay for the other)
SHOW_WAIT_MS=100 ./probe all ...# how long the overlay gets before the real window is parked (default 25)
./probe calib                   # what cadence each capture instrument can see (below)
./probe sandboxcheck <bundle>   # AX + capture, run from inside App Sandbox (see "Sandbox")
```

Sandboxed build. A bare binary carrying the entitlement dies in `secinit` with SIGTRAP ("Unable to get
bundle identifier because Info.plist from code signature information has no value"), so it needs a bundle:

```
mkdir -p ProbeSandboxed.app/Contents/MacOS && cp probe ProbeSandboxed.app/Contents/MacOS/probe
# Info.plist: CFBundleIdentifier sh.emu.probe.window-animation, CFBundleExecutable probe, CFBundlePackageType APPL
codesign -f -s - --entitlements sandbox.entitlements ProbeSandboxed.app
```

## Machine and conditions

- macOS 26.5 (25F71), Apple M4 Pro, Swift 6.3.3. Main display 2560×1440 @ **144 Hz**, scale 1.0
  (all animation on this display); two more displays attached (1512×982 @120 Retina, 1920×1080 @120).
- **SpacialShell was not running** during any probe run (`ps` checked) — no tiling interference.
- TCC: `AXIsProcessTrusted() == true`, `CGPreflightScreenCaptureAccess() == true`, both attributed to
  the launching process (a Claude Code shell), not to the probe binary.
- Every animated window was opened by the probe: its own child app (`probe target`, an AppKit window
  whose content is an `NSTextView` with ~180 KB of wrapping text), or TextEdit (a ~480 KB plain-text file)
  / Calculator / Preview (`Mac Yellow.heic`) / Activity Monitor launched with `open -F`. The probe refuses
  an app that is already running, and quits every app afterwards.
- Endpoints: A = (120, 131, 900×620), B = (1100, 331, 1300×900), top-left points; per app, the frames the
  app actually accepted for A and B are used. Duration **300 ms**, cubic ease-in-out. A magenta
  probe-owned backdrop window sits under the whole animation region.

## Instruments and their ceilings

| instrument | what it sees | ceiling (measured) |
|---|---|---|
| AX write latency | wall time around `AXUIElementSetAttributeValue` | — |
| geometry poller | `CGWindowListCopyWindowInfo(.optionIncludingWindow)` bounds changes | 86–171 polls/s observed — geometry rates are lower bounds |
| window stream | `SCStream` on one window; a `.complete` frame = its pixels changed | 112 /s for a continuous CA animation (calib) |
| screen stream | `SCStream` on the display region, sRGB, 1/4 scale — hole detection only | 82–90 /s (calib) — **sampled**, not every displayed frame |

`./probe calib` — a CALayer animating continuously in a probe-owned overlay on the 144 Hz display, 1 s
window per config:

| config | updates/s | max gap |
|---|---|---|
| display region, 600×305, pixels copied | 83 | 20.8 ms |
| display region, 600×305, no copy | 85 | 20.8 ms |
| display region, full 2400×1220 | 90 | 20.8 ms |
| whole display, 640×360 | 82 | 27.8 ms |
| overlay window only (`desktopIndependentWindow`) | 112 | 70.7 ms (single outlier) |

No capture instrument here sees 144 Hz. Rates below are **lower bounds on what reached the screen** and
must be read against these ceilings, not against 144. The per-window "content" rate the probe also
records (98–123 /s in every stepped cell, including moves that change no pixels of the window) did not
discriminate between conditions and is not used for any conclusion.

A **hole** is a screen-stream frame where more than 3% of the pixels inside the rect the window (or the
overlay) must occupy are backdrop magenta — nothing was drawn there.

## Sandbox

Same Calculator window (launched with `open -F`, quit after), same TCC grants, run back to back:

| | sandboxed (ad-hoc bundle, `com.apple.security.app-sandbox` only) | unsandboxed control |
|---|---|---|
| `AXIsProcessTrusted()` | **true** | true |
| AX read `kAXRoleAttribute` on the app | **-25204** (`kAXErrorCannotComplete`) | 0 |
| AX read `kAXWindowsAttribute` | **-25204** | 0 |
| AX window found (15 s of polling) | **no** | yes |
| 61 stepped `kAXPosition` writes | not possible | 0 errors, p50 1.6 / p95 3.2 / max 4.8 ms |
| `SCShareableContent` (n=5) | p50 34.3 / max 52.4 ms | p50 29.0 / max 32.8 ms |
| `SCScreenshotManager.captureImage` 460×816 (n=5) | p50 46.3 / max 130.7 ms, image returned | p50 53.1 / max 82.2 ms |

No `Sandbox` denial line appeared in `log show` for the run. `AXIsProcessTrusted()` reporting true
while every call fails means a sandboxed build cannot use it as a health check.

## Endpoints each app accepted

| target | A | B | resizable |
|---|---|---|---|
| child (AppKit `NSTextView`) | 120,131 900×620 | 1100,331 1300×900 | yes |
| TextEdit | 900×620 | 1300×900 | yes |
| Calculator | 230×408 | 230×408 | **no** — every size write fails (176–177 AX errors per 4 resize runs) |
| Preview | 900×620 | 1300×900 | yes |
| Activity Monitor | 900×620 | 1300×900 | yes |

## Capture cost (n=10 per app, unsandboxed)

| target | image px | `SCShareableContent` p50 / max ms | `captureImage` p50 / p95 / max ms |
|---|---|---|---|
| child | 1300×900 | 31.5 / 34.0 | 41.3 / 88.9 / 88.9 |
| TextEdit | 1300×900 | 35.7 / 79.2 | 44.9 / 135.8 / 135.8 |
| Calculator | 230×408 | 31.6 / 50.9 | 39.1 / 49.2 / 49.2 |
| Preview | 1300×900 | 34.7 / 63.2 | 38.3 / 48.1 / 48.1 |
| Activity Monitor | 1300×900 | 31.9 / 39.6 | 40.3 / 44.2 / 44.2 |

Capture cost is flat in image size here (230×408 ≈ 1300×900): the floor is the round trip, not pixels.

## Mechanism 1 — stepped AX writes (and 3a, hybrid)

Wall-clock-driven loop capped at the display rate; each iteration writes the eased frame for "now", so a
slow app drops frames instead of stretching the animation. Modes: `move` (position only), `resize` (size
only), `both` (position then size each step), `hybrid` (one size write up front, then position only).
n = 4 runs per cell, alternating direction. Medians across runs; "worst" = worst single run.

Run `stepped2`. Hole metric: pixels inside **both** the geometry sample before the frame and the one after
it, inset 24 pt — a moving window cannot fake a hole by being one poll ahead.

| target | mode | writes/s | pos p50 / worst p95 ms | size p50 / worst p95 ms | geometry updates/s | longest stall med / worst ms | tail after loop med / max ms | hole frames / checked | worst hole % |
|---|---|---|---|---|---|---|---|---|---|
| child | move | 146.1 | 0.5 / 3.7 | – | 98.3 | 34.9 / 49.6 | 0 / 0.2 | 1 / 130 | 11.8 |
| child | resize | 98.7 | – | 9.9 / 37.1 | 52.5 | 60.9 / 93.9 | 0 / 27.4 | 0 / 127 | 1.1 |
| child | both | 86.0 | 1.9 / 12.3 | 7.6 / 37.9 | 55.5 | 46.2 / 82.5 | 0.6 / 10.5 | 1 / 126 | 5.2 |
| child | hybrid | 146.3 | 0.8 / 9.3 | 6.6 / 25.2 (once) | 86.4 | 31.0 / 40.1 | 0 / 0 | 0 / 121 | 0 |
| TextEdit | move | 145.8 | 1.1 / 7.1 | – | 77.8 | 42.2 / 54.0 | 0 / 1.1 | 1 / 147 | 5.4 |
| TextEdit | resize | 67.8 | – | 12.1 / 50.1 | 33.5 | 55.3 / 79.4 | 8.4 / 29.4 | 2 / 146 | 16.7 |
| TextEdit | both | 52.5 | 5.0 / 39.6 | 6.8 / 39.5 | 38.6 | 59.5 / 81.8 | 15.9 / 25.5 | 1 / 143 | 10.5 |
| TextEdit | hybrid | 145.8 | 0.6 / 10.1 | 14.9 / 33.0 (once) | 50.3 | 58.7 / 69.4 | 0 / 0.2 | 0 / 127 | 2.6 |
| Calculator | move | 146.1 | 1.9 / 8.8 | – | 65.8 | 40.8 / 55.6 | 0 / 1.6 | 3 / 108 | 59.8 |
| Calculator | both | 146.2 | 1.0 / 7.3 | 0.2 / 3.7 (fails) | 76.3 | 34.1 / 36.3 | 0 / 10.8 | 1 / 111 | 10.2 |
| Calculator | hybrid | 146.0 | 1.1 / 6.5 | 0.1 (fails) | 69.7 | 40.5 / 53.2 | 0 / 0 | 0 / 111 | 0.3 |
| Preview | move | 146.3 | 1.1 / 10.4 | – | 74.8 | 37.2 / 55.9 | 0 / 9.6 | 1 / 127 | 5.6 |
| Preview | resize | 97.5 | – | 8.9 / 32.4 | 53.0 | 49.0 / 59.8 | 0 / 10.1 | 1 / 122 | 7.3 |
| Preview | both | 43.2 | 1.9 / 17.3 | 19.4 / 55.0 | 30.2 | 65.0 / 87.5 | 5.3 / 14.2 | 2 / 125 | 20.9 |
| Preview | hybrid | 146.2 | 1.0 / 18.1 | 9.8 / 25.3 (once) | 83.9 | 23.4 / 61.1 | 0 / 1.1 | 1 / 108 | 48.2 |
| Activity Monitor | move | 145.9 | 0.8 / 6.4 | – | 80.3 | 40.2 / 57.2 | 0 / 0 | 1 / 122 | 5.9 |
| Activity Monitor | resize | 73.5 | – | 11.9 / 36.1 | 38.4 | 78.5 / 95.5 | 2.4 / 15.9 | 0 / 114 | 0 |
| Activity Monitor | both | 77.7 | 3.8 / 10.0 | 7.2 / 44.3 | 57.9 | 43.1 / 58.0 | 2.5 / 19.4 | 2 / 110 | 78.8 |
| Activity Monitor | hybrid | 145.9 | 1.0 / 9.3 | 17.6 / 28.7 (once) | 88.6 | 22.1 / 32.1 | 0 / 10.2 | 1 / 101 | 5.0 |

Calculator `resize` is omitted: its size is fixed, it produced 0 geometry updates and 176 AX errors.
"Longest stall" = the largest gap between geometry changes inside the animation, per run.

The first full run (`full`: same matrix, hole metric = the geometry-before rect only, inset 40 pt) agrees
on every rate and latency within run-to-run noise. For example TextEdit resize measured 46.0 writes/s and
25.5 geometry updates/s, and child both measured 70.8 and 48.1. It reported more holes, though (Calculator
move 8 of 113 frames at 100%). Those were poll-alignment artifacts: a 230 pt window moving ~47 pt per
display frame outruns a one-sided check, which is why `stepped2` changed the metric.

Visual check of the worst `stepped2` frame (TextEdit resize, 16.7%): the window server's frame is ahead of
TextEdit's drawing. The bottom band of the window rect shows backdrop, and the last text line is drawn
below where the frame says the window ends. That is a real content/geometry mismatch, not an instrument
artifact.

## Mechanism 2 — snapshot overlay (and 3b, resize while parked)

Sequence:
1. Create a persistent click-through overlay window at `.floating`, before timing starts.
2. Call `SCShareableContent`.
3. Call `SCScreenshotManager.captureImage` at 1×.
4. Put the image in a `CALayer` at the window's frame.
5. Wait `SHOW_WAIT_MS` (25).
6. Park the real window at the main display's bottom-right sliver with one AX position write. `parkresize`
   also writes the final size while it is parked there.
7. Animate the layer's frame with an implicit CA animation, 300 ms ease-in-ease-out.
8. Make the final AX write(s): `endwrite` does size + position + size; `parkresize` does position only.
9. Remove the overlay:
   - `immediate`: as soon as the write returns.
   - `settled`: when the poller sees the target frame.
   - `settled2f`: settled plus 2 display frames.

n = 4 per cell, alternating A↔B, which is a move **and** a resize.

Run `overlay3` — the only overlay run whose numbers are used (see "Superseded overlay runs"):

| target | variant / removal | cmd→motion med / max ms | capture med / max ms | overlay render updates/s | park write med ms | final write med / max ms | settle after write med / max ms | overlay removed after write, med ms | show-hole frames | hand-off hole frames / checked | worst hand-off hole % | swap pop (med, 0–255) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| child | endwrite-immediate | 105.8 / 128.9 | 47.8 / 59.1 | 107.7 | 0.6 | 28.6 / 46.8 | 55.7 / 58.4 | 28.6 | 0 | **1 / 60** | 100 | 56.2 |
| child | endwrite-settled | 102.3 / 125.9 | 35.1 / 45.8 | 109.1 | 0.6 | 36.5 / 49.2 | 53.0 / 74.4 | 54.2 | 0 | 0 / 60 | 0 | 56.1 |
| child | endwrite-settled2f | 100.8 / 107.6 | 36.9 / 48.6 | 107.8 | 0.6 | 31.8 / 53.2 | 48.8 / 68.4 | 64.9 | 0 | 0 / 62 | 0 | 56.1 |
| child | parkresize-immediate | 113.0 / 179.3 | 39.1 / 50.0 | 108.0 | 12.0 | 0.6 / 0.6 | 38.3 / 45.9 | 0.6 | 0 | **2 / 59** | 100 | 56.3 |
| child | parkresize-settled | 119.5 / 149.5 | 42.5 / 48.0 | 107.2 | 18.0 | 1.0 / 1.5 | 35.4 / 48.1 | 37.5 | 0 | 0 / 60 | 0 | 56.1 |
| child | parkresize-settled2f | 127.5 / 157.0 | 41.7 / 48.9 | 106.2 | 29.4 | 0.9 / 1.4 | 28.6 / 29.2 | 45.2 | 0 | 0 / 66 | 0 | 56.1 |
| TextEdit | endwrite-immediate | 112.8 / 143.5 | 47.2 / 57.2 | 107.9 | 1.3 | 61.2 / 115.5 | 111.7 / 124.4 | 61.2 | 0 | **2 / 54** | 100 | 41.1 |
| TextEdit | endwrite-settled | 105.4 / 112.4 | 35.5 / 36.9 | 107.7 | 1.4 | 41.5 / 81.9 | 95.5 / 125.7 | 97.2 | 0 | 0 / 61 | 0 | 41.2 |
| TextEdit | endwrite-settled2f | 110.4 / 117.3 | 34.4 / 44.0 | 109.2 | 1.2 | 56.7 / 60.2 | 89.3 / 117.5 | 105.6 | 0 | 0 / 66 | 0 | 41.2 |
| TextEdit | parkresize-immediate | 183.2 / 196.8 | 45.4 / 53.1 | 107.8 | 62.5 | 1.4 / 2.1 | 51.9 / 66.3 | 1.4 | 0 | **3 / 57** | 100 | 41.4 |
| TextEdit | parkresize-settled | 164.7 / 177.7 | 33.8 / 45.6 | 106.1 | 62.2 | 1.4 / 1.7 | 57.9 / 69.6 | 59.0 | 0 | 0 / 58 | 0 | 41.2 |
| TextEdit | parkresize-settled2f | 126.6 / 175.3 | 33.8 / 45.9 | 107.6 | 16.4 | 1.0 / 6.1 | 50.9 / 73.2 | 68.8 | 0 | 0 / 63 | 0 | 41.2 |
| Calculator | endwrite-immediate | 122.4 / 135.5 | 45.5 / 56.0 | 109.0 | 2.1 | 29.6 / 31.2 | 67.0 / 70.9 | 29.6 | 0 | 0 / 51 | 0 | 0.6 |
| Calculator | endwrite-settled | 119.9 / 135.4 | 39.2 / 51.5 | 111.0 | 2.3 | 30.7 / 33.0 | 58.5 / 71.0 | 59.6 | 0 | 0 / 66 | 0 | 5.8 |
| Calculator | endwrite-settled2f | 117.7 / 136.0 | 39.0 / 41.1 | 107.4 | 2.3 | 29.1 / 29.5 | 55.2 / 63.0 | 72.0 | 0 | 0 / 59 | 0 | 5.9 |
| Calculator | parkresize-immediate | 130.1 / 153.6 | 37.7 / 46.3 | 108.0 | 23.2 | 2.8 / 5.3 | 58.8 / 67.7 | 2.8 | 0 | **4 / 56** | 100 | 21.9 |
| Calculator | parkresize-settled | 135.6 / 174.0 | 35.2 / 65.9 | 107.3 | 31.4 | 2.1 / 2.2 | 55.3 / 60.5 | 56.0 | 0 | 0 / 61 | 0 | 5.8 |
| Calculator | parkresize-settled2f | 148.8 / 164.7 | 42.0 / 49.3 | 107.8 | 30.6 | 2.1 / 5.1 | 62.0 / 67.6 | 79.1 | 0 | 0 / 57 | 0 | 5.9 |
| Preview | endwrite-immediate | 136.1 / 150.6 | 42.7 / 72.7 | 106.1 | 3.0 | 25.8 / 33.4 | 66.5 / 72.4 | 25.8 | 0 | **1 / 43** | 100 | 15.8 |
| Preview | endwrite-settled | 124.5 / 152.4 | 44.0 / 69.7 | 104.7 | 3.0 | 41.8 / 71.2 | 60.6 / 148.0 | 61.5 | 0 | 0 / 36 | 0 | 14.6 |
| Preview | endwrite-settled2f | 100.8 / 121.4 | 36.6 / 50.2 | 104.3 | 3.5 | 21.7 / 27.4 | 57.5 / 86.3 | 75.8 | 0 | 0 / 33 | 0 | 14.6 |
| Preview | parkresize-immediate | 132.2 / 152.1 | 36.6 / 43.5 | 100.9 | 25.5 | 2.1 / 3.6 | 52.7 / 60.9 | 2.1 | 0 | **3 / 20** | 100 | 14.8 |
| Preview | parkresize-settled | 129.0 / 135.4 | 37.5 / 41.4 | 104.0 | 25.1 | 1.3 / 1.4 | 65.8 / 91.6 | 66.3 | 0 | 0 / 14 | 0 | 14.6 |
| Preview | parkresize-settled2f | 146.2 / 159.1 | 42.9 / 51.7 | 102.7 | 28.6 | 1.2 / 1.3 | 66.9 / 74.9 | 84.4 | 0 | 0 / 17 | 0 | 14.6 |
| Activity Monitor | endwrite-immediate | 106.0 / 110.0 | 38.1 / 42.6 | 104.6 | 3.2 | 31.2 / 76.9 | 60.5 / 124.3 | 31.2 | 0 | 0 / 42 | 0 | 9.9 |
| Activity Monitor | endwrite-settled | 110.9 / 133.3 | 35.2 / 54.6 | 108.8 | 5.3 | 40.1 / 90.9 | 80.5 / 97.7 | 80.8 | 0 | 0 / 34 | 0 | 11.6 |
| Activity Monitor | endwrite-settled2f | 107.2 / 174.7 | 33.2 / 34.8 | 109.5 | 5.3 | 34.3 / 82.9 | 60.1 / 83.8 | 77.7 | 0 | 0 / 29 | 0 | 11.7 |
| Activity Monitor | parkresize-immediate | 143.9 / 178.9 | 37.8 / 50.1 | 106.0 | 30.5 | 6.4 / 9.0 | 56.1 / 67.9 | 6.4 | 0 | **3 / 14** | 100 | 11.8 |
| Activity Monitor | parkresize-settled | 164.1 / 184.7 | 43.8 / 56.7 | 107.8 | 40.6 | 5.2 / 6.0 | 53.4 / 63.3 | 56.1 | 0 | 0 / 8 | 0 | 11.9 |
| Activity Monitor | parkresize-settled2f | 149.9 / 157.5 | 41.0 / 49.1 | 107.9 | 39.7 | 5.1 / 6.2 | 55.0 / 83.4 | 72.3 | 0 | 0 / 6 | 0 | 11.8 |

Pooled over the five apps (`overlay3`):

| removal | variant | hand-off hole frames / checked | runs with a hole |
|---|---|---|---|
| immediate | endwrite | 4 / 250 | 4 / 20 |
| immediate | parkresize | 15 / 206 | 15 / 20 |
| settled | both | **0 / 458** | **0 / 40** |
| settled2f | both | **0 / 458** | **0 / 40** |
| — | show (overlay appears, window parked) | **0 hole frames in 120 runs** | 0 |

Reading the table:
- **Overlay render cadence was 100.9–111.0 updates/s in every cell.** That is at the window-stream
  instrument's measured ceiling (112/s, calib); no instrument here could see higher.
- **Swap pop** is the mean absolute RGB difference inside the target rect between the last frame with the
  overlay and the settled frame 500 ms later. It was identical for `settled` and `settled2f` in every app,
  so it is content, not timing. The overlay lands as a stretched still of the *old* layout, and the real
  window replaces it with reflowed content. Text-heavy apps: child ≈ 56, TextEdit ≈ 41. Preview ≈ 15,
  Activity Monitor ≈ 10–12. Calculator, which is not resized, measured 0.6–5.9 with clean hand-offs; the
  21.9 is the immediate-removal cell, which has holes.
- **What a clean hand-off costs:** the overlay has to hold at its end position until the window server
  reports the target frame. That is 37.5–97.2 ms (medians) after the final write for `settled`, and
  45.2–105.6 ms for `settled2f`.
- **`parkresize`** shrinks the final write to 0.6–6.4 ms (position only), versus 21.7–61.2 ms for
  `endwrite`, and the settle to 28.6–66.9 ms, versus 48.8–111.7 ms. The cost moves to the park write,
  12.0–62.5 ms, which pushes command→motion to 113.0–183.2 ms, versus 100.8–136.1 ms.

### Superseded overlay runs — a probe bug, recorded because it looked like a real flash

The first overlay implementation set `isGeometryFlipped = true` on the root layer of a layer-hosting
`NSView` and used flipped rects. AppKit did not reliably honour that. In some frames the snapshot drew
vertically mirrored: saved frames show it at y ≈ 611 instead of 131, which is exactly 1220 − 60 − 620 + 71,
the unflipped position. Two runs used that version:
- `full`: 120 overlay runs, all five apps.
- `showwait100`: 48 runs, child and TextEdit, `SHOW_WAIT_MS=100`.

In both runs the bug produced "show holes" at the origin: 1–8 per 4-run cell, mostly in `parkresize`. A
100 ms show-wait did not remove them (child parkresize 18 → 12, TextEdit 15 → 10), which ruled out overlay
display latency. The bug also inflated swap-pop values to 21.8–100.4. Replacing the flip with explicit
bottom-left layer rects (the committed `layerRect`) brought show holes to 0 of 120 runs.

The hand-off conclusion did not depend on the bug. In the superseded `full` run, `immediate` removal left
45 hole frames out of 464 checked, on every app, and `settled` / `settled2f` left 0 of 464 and 0 of 460.
`showwait100` reproduced the same split. Timing numbers (capture, writes, settle) in those runs match
`overlay3` within noise. None of their numbers are used above.
