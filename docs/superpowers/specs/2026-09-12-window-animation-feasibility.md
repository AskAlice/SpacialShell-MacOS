# Window animation feasibility — can SpacialShell animate other apps' windows? (verified 2026-09-12)

Legend: [H]=high, [M]=medium, [L]=low confidence. **Measured** = run on this Mac by
`Tools/window-animation-probe/probe.swift` on 2026-09-12 (macOS 26.5 25F71, M4 Pro, Swift 6.3.3; main
display 2560×1440 @ 144 Hz, scale 1.0); raw numbers, commands, instrument ceilings and sample sizes are in
`Tools/window-animation-probe/RESULTS.md`. **Reasoned** = inferred from the measurements or from source,
not itself measured — always labelled. Peer evidence is pinned upstream source, the project's own docs,
or maintainer statements in its own tracker. No secondary write-ups.

Conditions that bound every number here: SpacialShell was **not running** during the probe runs (no
tiling interference); every animated window was opened by the probe itself and closed after; TCC grants
were attributed to the launching shell; the probe uses public API only (`nm -u` clean).

---

## The question

SpacialShell tiles other apps' windows through the Accessibility API. It is heading for the Mac App
Store: **no private API** (it just removed `_AXUIElementGetWindow`) and **App Sandbox** (entitlement
tracked as #20; #19 cleared the subprocess and config-path blockers). Can it animate other apps' windows
moving and resizing under those rules, and by what mechanism?

**Short answer.**

- **Under App Sandbox: no.** The probe measured Accessibility calls failing inside the sandbox
  (`kAXErrorCannotComplete`) while `AXIsProcessTrusted()` returned true. SpacialShell could not move
  another app's window at all under App Sandbox, animated or not (§1).
- **Unsandboxed, public API only: yes.** The best mechanism is a ScreenCaptureKit snapshot of the window,
  slid by Core Animation while the real window is parked out of sight. The window is resized while parked,
  and the snapshot is removed only once the window server reports the real window in place (§3, §4).
  - The flight renders at the instrument ceiling (101–111 updates/s).
  - The hand-off is clean when removal waits for the window server: 0 hole frames in 458 checked.
  - The costs: 113–183 ms before motion starts, a 38–66 ms hold at the end, a visible content "pop" when
    the size changed, and a second TCC grant (Screen Recording).
- **Moving the real window with stepped AX writes works for position** (~146 writes/s, stalls of
  35–57 ms), **and is janky for size**: 30–58 geometry updates/s, 60–95 ms stalls (§2).
- **yabai's seamless version** needs private SkyLight calls plus a Dock scripting addition with SIP
  partially disabled. It is ruled out (§5, §6).

---

## 1. The finding that sits under every mechanism: App Sandbox blocks the Accessibility API

This is not an animation result, but no animation mechanism survives it, so it comes first.

**Measured** [H] (`probe sandboxcheck`, RESULTS.md §Sandbox). Same Calculator window, same TCC grants,
the same binary once inside an ad-hoc-signed bundle carrying only `com.apple.security.app-sandbox` and
once unsandboxed, back to back:

- Sandboxed: `AXIsProcessTrusted()` returns **true**, and then every AX call fails —
  `AXUIElementCopyAttributeValue(app, kAXRoleAttribute)` and `(app, kAXWindowsAttribute)` both return
  **-25204 `kAXErrorCannotComplete`**; no window is found in 15 s of polling; no write is possible.
- Unsandboxed control: reads succeed; 61 `kAXPosition` writes, 0 errors, p50 1.6 ms.
- ScreenCaptureKit works in both: sandboxed `SCScreenshotManager.captureImage` returned a 460×816 image,
  p50 46.3 ms (n=5).

**Apple's own statement matches** [H]:

- "Protecting user data with App Sandbox" lists, under activities "forbidden by the operating system when
  an app runs in a sandbox": "Use of accessibility APIs in assistive apps."
  ([developer.apple.com](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox))
- Quinn (Apple DTS), June 2025: "In general, App Sandbox blocks use of the Accessibility APIs … However,
  there are some exceptions" — the exceptions named are `CGEventTap` under Input Monitoring and
  `CGEvent.post`, which "doesn't give you complete accessibility access. It's just limited to posting
  events." ([forums thread 789896](https://developer.apple.com/forums/thread/789896))
- Quinn, 2018: "The Accessibility API is not, in general, compatible with sandboxing"
  ([thread 103998](https://developer.apple.com/forums/thread/103998)).
- On window managers already on the Store: "Not all Mac App Store apps are sandboxed. Some apps shipped on
  the store before sandboxing was required." ([thread 707680](https://developer.apple.com/forums/thread/707680))

Caveats on the measurement [M]: the bundle was ad-hoc signed, not Store-signed; TCC attribution went to
the parent shell, not to the bundle. Neither plausibly *grants* AX — the sandbox refused the calls while
TCC said yes — but a Developer-ID/Store-signed build with its own TCC row is the confirming run still to
do. No temporary-exception entitlement was tried (App Review scrutinises those; out of scope here).

**Reasoned consequence** [H]: under App Sandbox, SpacialShell cannot read or set any other app's window
frame — so it cannot tile, let alone animate. The animation question below is therefore answered for the
build that can actually move windows today: unsandboxed, public API only (e.g. Developer ID distribution).
Everything marked "sandbox compatible" below means *the animation layer adds no new sandbox problem*; the
AX writes every mechanism ends with do.

---

## How the mechanisms were measured

This applies to everything in §2–§4 (details and raw tables in RESULTS.md).
- **Apps:** five, each opened by the probe:
  - its own AppKit child window (an `NSTextView` with ~180 KB of wrapping text)
  - TextEdit (~480 KB text file)
  - Calculator (fixed size)
  - Preview (a large HEIC)
  - Activity Monitor
- **Motion:** each window animated between A = 900×620 at (120, 131) and B = 1300×900 at (1100, 331).
  300 ms, 4 runs per condition, alternating direction.
- **Instruments:**
  - wall time around each `AXUIElementSetAttributeValue`
  - a thread polling `CGWindowListCopyWindowInfo` for what the window server says the frame is (86–171
    polls/s)
  - an `SCStream` on the overlay window (ceiling 112 updates/s, calibrated)
  - an `SCStream` on the screen region over a magenta backdrop the probe owns (82–90 updates/s,
    calibrated). Magenta inside a rect a window should cover counts as a **hole**.
- **Sample sizes:** stepped AX, 20 conditions × 4 = 80 runs (`stepped2`). Overlay, 30 × 4 = 120 runs
  (`overlay3`). Capture cost, 10 per app. Superseded runs are listed in RESULTS.md with the reason.
- **Ceiling on every rate below:** no instrument here sees the display's 144 Hz. Rates are lower bounds.
  Stalls (gaps) are the robust signal.

## 2. Mechanism 1 — stepped Accessibility frame writes

A wall-clock loop capped at the display rate writes the eased frame for "now" through
`kAXPositionAttribute` / `kAXSizeAttribute`. A slow app therefore drops steps rather than stretching the
animation. This is how Loop ships it, and how Rectangle PRs #1848/#1849 propose it (§5).

**Measured** [H]:

- **Position writes are cheap on every app.**
  - p50 0.5–1.9 ms, worst-run p95 3.7–10.4 ms.
  - The loop held its cap on all five apps: 145.8–146.3 writes/s.
  - 0 AX errors on the four resizable apps.
- **Size writes are where the time goes.**
  - p50 8.9–12.1 ms, worst-run p95 32.4–50.1 ms (55.0 ms in `both` on Preview).
  - Resize-only runs could manage only 67.8–98.7 writes/s.
- **What the window server showed** (geometry updates/s; longest stall between geometry changes per run,
  median / worst):
  - **move:** 65.8–98.3/s; stalls 34.9–42.2 / 49.6–57.2 ms.
  - **resize:** 33.5–53.0/s; stalls 49.0–78.5 / 59.8–95.5 ms. The window finished up to 29.4 ms after the
    loop did.
  - **both:** 30.2–57.9/s at 43.2–86.0 writes/s; worst stalls 58.0–87.5 ms; up to 25.5 ms late.
- **Holes are rare** once poll alignment is accounted for: 0–3 frames per 101–147 sampled, per cell. The
  worst frame inspected (TextEdit resize, 16.7% of the rect) is real: the window server's frame was ahead
  of TextEdit's drawing, and the last line of text drew below the frame's bottom edge.
- **Calculator refuses every size write:** 176 AX errors per 4 resize runs. Its position still animated.

**Reasoned** (not measured directly):

- A frame at 144 Hz is 6.9 ms. A 35–57 ms stall in a 300 ms move is therefore a visible hitch of 5–8
  frames. Resize stalls of 60–95 ms with ~30–55 geometry updates/s are plainly janky.
  - This agrees with yabai's maintainer ("Resizing using the AX API is just too slow") and Amethyst's
    ("choppy"), §5.
  - Human-visible smoothness was not filmed; the judgement rests on the stall numbers.
- **The cost lands on the target app.** Every step is an IPC round-trip into its main thread, and every
  size step is a layout pass. A tiling transition moves several windows at once, and all of this was
  measured one window at a time.
- **The animation must read frames back and adapt** to apps that refuse sizes. Loop does this
  (`WindowTransformAnimation.swift` L248-308), and it also clears `AXEnhancedUserInterface` around writes
  (`Window.swift` L550-562). Enhanced-UI and Chromium/Electron apps were not measured.

## 3. Mechanism 2 — snapshot overlay

Sequence:
1. A persistent, click-through overlay window at `.floating`.
2. `SCShareableContent` → `SCScreenshotManager.captureImage` of the window (the API SpacialShell already
   uses for rail hover previews, `Sources/SpacialShellUI/WindowPreview.swift`).
3. The image goes in a `CALayer` at the window's frame.
4. One AX write parks the real window in a corner sliver, the way SpacialShell already parks
   inactive-workspace windows.
5. Core Animation slides and stretches the layer to the new frame.
6. The real AX write(s) place the window.
7. The overlay is removed.

**Measured** [H]:

- **Capture cost is a round-trip floor, not a pixel cost.** `SCShareableContent` p50 31.5–35.7 ms;
  `captureImage` p50 38.3–44.9 ms, p95 44.2–135.8 ms. A 230×408 window costs the same as a 1300×900 one.
- **Command → first motion** (content list + capture + 25 ms for the overlay to appear + park write):
  100.8–136.1 ms median, max 174.7 ms.
- **The flight: 100.9–111.0 updates/s in every one of 30 cells**, at the measuring instrument's 112/s
  ceiling. The app's latency does not enter the flight at all.
- **Showing the overlay and parking the window: 0 hole frames in 120 runs.**
- **The hand-off decides whether it is seamless:**
  - Removing the overlay the moment the AX write returns left a hole frame in **19 of 40 runs**, mostly a
    full-rect flash of whatever is behind: 15/20 when resized while parked, 4/20 otherwise.
  - Removing it once the geometry poller sees the target frame left **0 hole frames of 458 checked in 40
    runs**. Waiting two further display frames also left 0 of 458.
  - The price is a hold at the end position of 54.2–97.2 ms (`settled`, median, after the final write).
- **The final write:** size + position + size took 21.7–61.2 ms median (max 115.5). The window settled
  48.8–111.7 ms after the write began.
- **The swap is a content pop whenever the size changed.** Mean absolute RGB difference (0–255) between
  the last overlay frame and the settled window:
  - child ≈ 56, TextEdit ≈ 41, Preview ≈ 15, Activity Monitor ≈ 10–12.
  - Calculator, whose size doesn't change, measured 0.6–5.9 when removal waited for the window server.
  - It is identical whether removal waits 0 or 2 extra frames, so it is the stretched old layout being
    replaced by reflowed content, not a timing artifact.
- **Sandbox:** capture works inside App Sandbox (§1). The park and final AX writes do not.

**A probe bug worth knowing about** (measured): the first implementation put `isGeometryFlipped` on the
root layer of a layer-hosting `NSView`. AppKit intermittently drew the snapshot vertically mirrored. That
produced convincing "flash at start" frames: 1–8 per 4-run cell, not cured by a 100 ms wait. Explicit
bottom-left layer rects removed them. All overlay numbers here come from the corrected run; RESULTS.md
records the superseded ones.

**Reasoned:**

- **It needs Screen Recording**, a second TCC prompt. It was not measured without the grant, because the
  grant was present on this Mac. The repo's own `WindowPreview.swift` records that without it
  ScreenCaptureKit hands back wallpaper instead of failing. The fallback must check
  `CGPreflightScreenCaptureAccess()` and place the window without animation.
- **The picture is a still.** Video, progress bars and typing freeze for the ~450 ms from capture to
  removal. Shadows are not in the capture (`ignoreShadowsSingleWindow`), and yabai's maintainer notes
  vibrancy isn't captured either.
- **Several windows:** captures are ~40 ms each, and the content list can be fetched once. The
  command→motion delay grows with window count unless captures run concurrently. Not measured.
- **This is what material-shell does**, with the difference in §5. GNOME hands an extension a live
  compositor clone for free. A macOS app pays ~100 ms and a TCC grant for a frozen picture, and must park
  the real window because it cannot hide it.

## 4. Mechanism 3 — hybrids

**3a. Stepped position, one size write** (measured [H], `stepped2` `hybrid`):
- Results:
  - 145.8–146.3 writes/s.
  - The single size write: p50 6.6–17.6 ms (worst p95 33.0).
  - 50.3–88.6 geometry updates/s.
  - Longest stall per run: median 22.1–58.7 ms, worst 32.1–69.4 ms.
  - Finished ≤ 10.2 ms after the loop; 0–1 hole frames per cell.
- It is steadier than `resize` or `both` on every app.
- Reasoned: the size changes in one jump at the start position, before the glide, and that jump is
  visible.

**3b. Overlay for position and scale, size applied once while parked** (measured [H], `overlay3`
`parkresize`):
- The final write is position only: 0.6–6.4 ms, settled 28.6–66.9 ms later. The app reflows off-screen
  during the flight.
- The size write moves to the park step: 12.0–62.5 ms. Command → motion rises to 113.0–183.2 ms median.
- Hand-off is clean under the same rule: `settled` 0 hole frames in 40 runs; `immediate` holed 15 of 20.
- The overlay hold is 37.5–66.3 ms (`settled`, median), against 54.2–97.2 ms for `endwrite`, because at
  the end the window only has to move.
- The swap pop is unchanged, because the overlay is still a picture of the old size.

**3c. Recapture after the parked resize and cross-fade in flight** (reasoned only, **not measured**): a
second ~40 ms capture once the window has reflowed at its new size. Cross-fading to it mid-flight would
remove the end-of-animation content pop. It adds a capture per window and a frame of compositing.

---

## 5. What peers actually do

### AeroSpace — no animations, by stated principle

- [H] README design principles: "Provide _practical_ features. Fancy appearance features are not
  _practical_ (e.g. window borders, transparency, animations, etc.)", and "'dark magic' (aka 'private
  APIs', 'code injections', etc.) must be avoided as much as possible … AeroSpace will never require you
  to disable SIP" ([README.md L122-126 @39e5190](https://github.com/nikitabobko/AeroSpace/blob/39e519044725694635712c739df9ca40ae78c5d1/README.md#L122-L126),
  re-fetched and verified verbatim). L20: "Fast workspaces switching without animations and without the
  necessity to disable SIP".
- [H] Maintainer, closing PR #2121 "Add 120fps animated window resize/move": "Please see the README. The
  PR goes against project values. AeroSpace will never have animations"
  ([comment](https://github.com/nikitabobko/AeroSpace/pull/2121#issuecomment-4659234343)); #452: "Goes
  against project values" ([comment](https://github.com/nikitabobko/AeroSpace/issues/452#issuecomment-2308585371)).
- The stated reason is values (practicality, no dark magic), not a claim of impossibility.

### yabai — animates a screenshot proxy; needs SIP partially disabled + Screen Recording

- [H] Docs: "*window_animation_duration* … Requires Screen Recording permissions. + System Integrity
  Protection must be partially disabled." ([doc/yabai.asciidoc L203-207 @dd84572](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/doc/yabai.asciidoc#L203-L207),
  re-fetched and verified verbatim). Enforced in `src/message.c` L1302-1311: a non-zero value is refused
  unless `scripting_addition_is_sip_friendly()` and `CGPreflightScreenCaptureAccess()`. (Repo moved:
  `koekeishiya/yabai` → `asmvik/yabai`.)
- [H] Mechanism, `src/window_manager.c` @dd84572: capture each window with private
  `SLSHWCaptureWindowList` (L507-531) into a proxy window created with `SLSNewWindowWithOpaqueShapeAndContext`
  (L463-484); `scripting_addition_swap_window_proxy_in`; **one real frame write** through the AX path
  (`window_manager_set_window_frame`); then a `CVDisplayLink` per-frame callback commits
  `SLSTransactionSetWindowTransform` + `SLSTransactionSetWindowAlpha` on the proxy (L537-573); at the end
  `SLSDisableUpdate` → swap proxy out → destroy → `SLSReenableUpdate` (L577-589). Orchestration L603-703.
- [H] The part that needs SIP runs **inside Dock** via the scripting addition: `do_window_swap_proxy_in`
  does `SLSTransactionOrderWindowGroup(proxy, wid)` and `SLSTransactionSetWindowSystemAlpha(wid, 0)` — it
  hides the *real* window and binds it to the proxy ([src/osax/payload.m L812-856](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/osax/payload.m#L812-L856)).
  Why Dock, per the maintainer in #1863: "its connection to the WindowServer has elevated privileges and is
  authorized to modify window properties that can otherwise only be set by the application whom the window
  belongs to." The wiki's SIP page lists "enable window animations" among the SIP-only features.
- [H] Maintainer on why not plain AX, #148: "Resizing using the AX API is just too slow" (2022-09-12); "The
  flicker is caused by … resetting the transform at the end of the animation to apply the change in size
  using the AX API"; "the screenshot does not capture vibrancy effects"; and "I think I found a way for this
  entire thing to work without having to disable SIP… Edit: … animations will require SIP to be disabled"
  ([#148](https://github.com/asmvik/yabai/issues/148)). CHANGELOG: added 5.0.0 (L393); restricted to
  SIP-disabled in 5.0.1 (L388); CVDisplayLink-driven since 6.0.10 (L264).

### Amethyst — none shipped; maintainer thinks SIP is required, reviewed stepped frames as choppy

- [H] ianyh, #1263: "As far as I know there is no way for amethyst to support animated window
  transitions… I believe you have to disable SIP to get the animations, but if someone else has a way to
  implement it without disabling SIP I am fine with getting a contribution"
  ([#1263](https://github.com/ianyh/Amethyst/issues/1263#issuecomment-2629191079)).
- [H] On stepped intermediate frames, PR #537: "Even in that video the transitions seemed a little
  choppy… with larger screens the number of intermediate steps would get large really fast", and dropping
  superseded transitions "is fundamentally in opposition to how this works"
  ([#537](https://github.com/ianyh/Amethyst/pull/537#issuecomment-276079942)).
- [M] PR #1883 (contributor, opened 2026-09-09, open, no maintainer reply) proposes exactly mechanism 2
  without SIP — ScreenCaptureKit pictures slid "using the system's own compositor… real windows are moved
  and resized behind a frozen backdrop", falling back to moving real windows without Screen Recording. A
  claim, not merged code.

### Rectangle — does not animate other apps' windows

- [H] rxhanson, #1465: "Unfortunately, there is no way to do this as a 3rd party. I'm not aware of any new
  APIs for it"; "Yes, unfortunately it would be laggy provided the options available"; and on macOS 26:
  "there are no new APIs that would allow a 3rd party to do this in a nice way"
  ([#1465](https://github.com/rxhanson/Rectangle/issues/1465#issuecomment-2354469626)). #234: "Rectangle does
  not perform resizing animation."
- [M] Contributor PR #1848 (stepped AX, "up to 60 updates per second… Target applications can still impose
  minimum sizes or respond slowly, so this remains experimental") closed unmerged; rxhanson: "I'm interested
  in merging this." #1849 open with the same approach. Rectangle's only in-tree animation is its own
  snap-footprint `NSWindow` (`animator().setFrame`), default off.

### Loop — ships stepped AX writes, off by default

- [H] `animateWindowResizes` defaults to `false` ([Defaults+Extensions.swift L75 @df26d56](https://github.com/MrKai77/Loop/blob/df26d565e07c82e156b8f1c361bdcf428f32e3a4/Loop/Extensions/Defaults%2BExtensions.swift#L75)).
  `WindowTransformAnimation.swift` is an `NSAnimation` (L26), 0.3 s ease-out at the screen's refresh rate
  (L65-66), cancels an in-flight animation for the same window (L70-74), and each tick calls
  `window.setSize`/`setPosition` — AX writes — re-reading the frame to adapt to apps that refuse sizes
  (L118-197, L248-308). It is skipped for `AXEnhancedUserInterface` windows and in Low Power mode
  (`WindowEngine.swift` L166-178), and temporarily clears enhanced UI around the write (`Window.swift`
  L550-562). No maintainer statement on jank found.

### Magnet — no primary evidence

- [L] Distributed on the Mac App Store (its site). Nothing primary on animation, sandboxing or how it
  obtains Accessibility was found. Given §1, a Store window mover that uses AX is either unsandboxed
  (grandfathered, per DTS thread 707680) or doing something not documented — unverified.

### material-shell — the positioning reference animates clones, not windows

- [H] From `docs/superpowers/specs/2026-09-12-material-shell-feature-inventory.md` (branch
  `research/material-shell-inventory`, material-shell @4c0cfcf, GNOME 45–46): tiles are compositor-level
  clones of their windows; slide transitions move the clones; tiles that are not shown have their real
  window **minimized** (Y20, `msWindow.ts:1296-1309`); slide duration is hard-coded **250 ms** and the
  `tween-time` preference is read but never used (Y22, `transition.ts:213-214`).
- Reasoned [H]: that *is* mechanism 2. The difference is who pays for the picture — a GNOME Shell
  extension runs inside the compositor and gets a live `Clutter.Clone` of every window for free, updated
  every frame; a third-party macOS app has to ask ScreenCaptureKit for a still (a Screen Recording grant
  and tens of ms per window, §3), cannot hide the real window, and gets a frozen image rather than a live one.

---

## 6. Private / SIP-requiring paths — why some tools can, ruled out here

- [H] yabai is the worked example (§5): SkyLight window creation/capture on its own connection is private
  API (`SLS*`), and the step that makes the swap seamless — hiding the real window (system alpha 0) and
  grouping it with the proxy — is done from **Dock's** connection via an injected scripting addition, which
  requires SIP partially disabled. Per the yabai wiki/#1863, Dock "owns the sole connection to the macOS
  window server" with universal-owner rights; a normal process may only transform windows it owns.
- [M] No primary source found that names `CGSSetWindowTransform` specifically as owner-restricted; the
  owner restriction rests on yabai's maintainer text.
- Ruled out for SpacialShell on two independent counts: private symbols (the `nm -u` gate) and SIP
  modification (not something a Store — or any mainstream — app can ask of users).
- [H] Apple offers no public API to animate another process's window: AX has no animation attribute (the
  macOS 26.5 SDK's public HIServices headers contain no "animat" string), and `NSWindow`
  `setFrame(_:display:animate:)` / `animator()` act only on windows the caller owns.

---

## 7. Compatibility and verdicts

| mechanism | private API | App Sandbox | extra grant | verdict |
|---|---|---|---|---|
| 1. Stepped AX, position only | none | **blocked** (AX, §1) | — | **viable with caveats**: 35–57 ms stalls in a 300 ms move, load on the target app's main thread, one window measured at a time |
| 1. Stepped AX, with size | none | **blocked** | — | **not viable** as a smooth animation: 30–58 geometry updates/s, 60–95 ms stalls, frames where geometry runs ahead of content, some apps refuse sizes |
| 2. Snapshot overlay, final write at end | none | AX blocked; capture works | Screen Recording | **viable with caveats**: 101–136 ms before motion, removal must wait for the window server (54–97 ms hold), content pop on resize, frozen picture, no shadow |
| 3a. Stepped position + one size write | none | **blocked** | — | **viable with caveats**: visible size jump at the start, 22–59 ms stalls |
| 3b. Overlay + resize while parked | none | AX blocked; capture works | Screen Recording | **viable with caveats** — same as 2, with a 113–183 ms start and a 38–66 ms end hold |
| SkyLight proxy + Dock scripting addition (yabai) | yes | no | SIP partially disabled + Screen Recording | **not viable** for SpacialShell (private API, SIP) |

## 8. Recommendation

1. **Settle distribution before building any of this.** Under App Sandbox no mechanism in this document
   works, because SpacialShell cannot read or move another app's window at all (§1: measured -25204,
   matching Apple's own sandbox documentation). That is a finding about tiling, not animation, and it
   bears directly on #20. The confirming run is a properly signed sandboxed build with its own TCC row.
2. **For the build that can move windows** (unsandboxed, public API only), use **mechanism 3b**:
   - capture with `SCScreenshotManager`
   - park the real window and apply its new size there
   - slide and scale the snapshot with Core Animation
   - make one AX position write at the end
   - remove the overlay only when the window server reports the target frame, never when the AX call
     returns

   Why 3b:
   - It is the only mechanism whose flight is independent of the target app: 101–111 updates/s in every
     cell, versus 30–58 for stepped resizing.
   - With the settled removal rule its hand-off was clean in all 40 measured runs.
   - It reuses two things SpacialShell already does: `SCScreenshotManager` capture and corner parking.
   - It is the macOS shape of what material-shell does (compositor clones, 250 ms).
3. **Fallback and scope:**
   - If `CGPreflightScreenCaptureAccess()` is false or a capture fails, place the window instantly. Never
     fall back to stepped size writes.
   - Ship it off by default until three things are measured: several windows animating at once, the
     no-grant path, and Chromium/Electron apps.
   - Expect a transition to take roughly 113–183 ms before motion, 250–300 ms of motion, and a 38–66 ms
     end hold (medians measured for 3b). The overlay's end state is a stretched picture of the old layout, which pops to the reflowed
     window; 3c is the unmeasured fix for that.

## Not measured, and why

- **A Store-signed or Developer-ID-signed sandboxed build** with its own TCC row: only an ad-hoc bundle
  with the TCC grant attributed to the parent shell was available.
- **Capture without the Screen Recording grant:** the grant was present, and the probe does not reset TCC.
- **Several windows animating at once:** every run animated one window.
- **Chromium/Electron, Safari, terminals, `AXEnhancedUserInterface` windows:** those apps were running for
  the user, and the probe does not touch other apps' windows.
- **Frame-exact smoothness at 144 Hz:** no capture instrument here exceeds 112 updates/s (calibrated), and
  no high-speed camera was used.
- **A Retina (2×) display:** all animation was on the 1× 144 Hz display, so capture cost at 2× is
  unmeasured.
- **With SpacialShell running and tiling:** deliberately excluded to isolate the mechanisms.
- **3c** (recapture and cross-fade), **caching `SCShareableContent`** (~32 ms per transition),
  **temporary-exception entitlements** for AX under the sandbox: reasoned or out of scope.
