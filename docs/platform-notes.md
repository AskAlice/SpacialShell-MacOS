# Platform notes — empirical checks

Everything on this page is a claim about *this machine's macOS*, not about the code. The checks
below cannot be run from a test suite: they need the Accessibility grant (which only a human can
click), a real keyboard, and a foreground app to type into. **No result here is a guess** — the
Result column stays `pending grant` until someone runs the procedure and records what happened.

Recorded against: macOS 26.5 (Darwin 25.5), Apple internal keyboard with a Globe key.
Spec references: §6.2 (bindings), §13.2 (research findings), §13.5 (this checklist).

## How to run the checks

```sh
# 1. Build and launch in the foreground. First launch prompts for Accessibility and opens the
#    Privacy pane; tick SpacialShell, and the app continues on its own.
SPACIAL_LOG_KEYS=1 Scripts/dev.sh

# 2. In a second terminal, watch what the tap sees (keycode + flags for every keyDown):
/usr/bin/log stream --predicate 'subsystem == "sh.emu.SpacialShell"' --info
#    Always the full path: in zsh a bare `log` is a shell builtin (it lists logins) that silently
#    shadows Apple's tool — `log show` prints nothing and looks like "no logs" (#39).

# 3. Open TextEdit with two documents (⌘N twice) and press each chord below in TextEdit.
#    For each one record three things:
#      a. did a line appear in the log stream (did the tap see it at all)
#      b. did a character get typed / did anything happen in TextEdit (were we too late)
#      c. did a macOS system UI appear (Quick Note, Dock, Control Centre, Siri…)
#
# 4. Quit with Ctrl-C in the first terminal. Every managed window should end up centred.
```

Grant reminder: the debug binary's TCC identity is its **path**. See `Scripts/README`.

## Checklist

| # | Check | What decides it | Expectation (spec §13.2) | Result |
|---|-------|-----------------|--------------------------|--------|
| 1 | **T1 — Fn+letter pre-emption at session level** | Press `Fn+Q`, `Fn+A`, `Fn+S`, `Fn+H`, `Fn+F` in TextEdit. Does our `.cgSessionEventTap` see them *and* swallow them, or does macOS's symbolic hotkey fire first (Quick Note / Dock / Type-to-Siri / Show Desktop / Full Screen)? | Session taps pre-empt symbolic hotkeys for ⌘Space/⌘Tab (skhd #337, Hammerspoon #766); unverified for Fn+letter on 26.5. **This check decides the default preset.** If the tap loses, retry with `kCGHIDEventTap`; if that also loses, the default preset becomes `ctrl-alt` and `fn` stays a documented option. | `pending grant` |
| 2 | **Fn+arrow keycodes** | Press `Fn+←`, `Fn+→`, `Fn+↑`, `Fn+↓`. Record the keycode logged. | Arrives as Home/End/PgUp/PgDn — 115 / 119 / 116 / 121 — with the Fn flag set, *not* 123/124/126/125: IOHIDKeyboardFilter remaps them below the tap. Confirms that Fn+arrows can never be bound and that the arrow aliases must stay on `⌃⌥` (spec §6.2). | `pending grant` |
| 3 | **Input Monitoring prompt** | Watch for a second TCC dialog ("SpacialShell would like to receive keystrokes…") on first launch, beyond the Accessibility one. | Unknown. An active session tap is usually satisfied by Accessibility alone; if a second prompt appears, onboarding (§10) must mention it. | `pending grant` |
| 4 | **Every default binding reaches us** | Press each of `Fn+W`, `Fn+S`, `Fn+A`, `Fn+D`, `Fn+Q`, `Fn+G`, `Fn+[`, `Fn+]`, `Fn+Space`, `Fn+Esc`, `Fn+1`, and the shifted `Fn+⇧A/⇧D/⇧W/⇧S/⇧[/⇧]`. | Each is logged, swallowed (nothing typed in TextEdit), and performs its command. Any chord that instead shows a system UI is a conflict → move that binding in `KeyBindings.core` **and its test**, and record the replacement here. Known suspects from §13.2: `Fn+Q` (Quick Note), `Fn+A` (Dock), `Fn+S` (Type-to-Siri), `Fn+⇧A` (Apps). | `pending grant` |
| 5 | **Parking sliver geometry, cross-process** | Switch to a workspace whose windows must be parked, then inspect where the parked windows landed (`/usr/bin/log stream` shows the writes; a screenshot of the corner shows the sliver). | The 1×32 sliver at the screen corner (§7.4) survives AX's per-app clamping: apps that refuse a 1 pt width get the zero-width variant (`zeroSliverBundleIDs`, currently Zoom only). Record any app that clamps to something visible. | `pending grant` |
| 6 | **Stacked displays** | With two displays arranged *vertically* (one above the other in System Settings), park windows on both. | Parking picks a corner that is not covered by the other display, so a parked window never shows on the neighbour (§7.4). | `pending grant` |
| 7 | **Observer-subscribe retries** | Launch a heavy app (Xcode, Chrome) while SpacialShell is running and watch the `AXApp` log for retried `AXObserverAddNotification` calls. | Some apps refuse observer registration until they finish launching; the retry loop should show a bounded number of retries and then succeed. Record how many, and any app that never succeeds. | `pending grant` |
| 8 | **Tap survival across sleep / lock** | Sleep the machine (or `pmset sleepnow`), wake it, and press a bound chord. Then lock the screen (⌃⌘Q), unlock, and press one again. Repeat with fast user switching if available. | The tap keeps working. If it does not, the log shows which re-arm path fired: the in-callback `tapDisabledBy*` re-enable, the wake (+3 s) / unlock / session-active nudge, or the 1 s health poll (and whether it had to re-create the port). If the circuit breaker trips it logs `event tap could not be re-created 5× in a row; giving up until the next wake or unlock` — that is five **consecutive** failed re-creations, and any wake, unlock or session activation clears it. Record what preceded it. | `pending grant` |

| 9 | **Windows on another Space (#55)** | With two desktops in Mission Control, move a managed window to Desktop 2 while on Desktop 1. Watch the `store` log and the tab bar, then switch to Desktop 2 and back. Repeat with a minimized window and a ⌘H-hidden app. | On Desktop 1 the log shows `space away` for it, its tab carries `macwindow.on.rectangle`, and no `setFrame`/`setPosition` names it. Switching to Desktop 2 logs `space back` and it is tiled with no key pressed. Record whether `kAXWindowsAttribute` still lists minimized / app-hidden windows (if not, they also read as off-Space — harmless, both are untouched, but record it). | `pending grant` |

| 10 | **Trackpad gestures: what a third party can observe (#141)** | See [Trackpad gestures](#trackpad-gestures-141) below: a standalone probe with a global `NSEvent` monitor, a local one, and a listen-only `CGEvent` tap, all for `.gesture` events, left running while the trackpad was used normally. | The G27 acceptance asked for this measurement before scoring. | **Measured 2026-09-26** (partly): the global monitor sees **nothing**; the tap sees every touch frame. Details below. |

## Trackpad gestures (#141)

Recorded 2026-09-26 on a MacBook Pro (Mac16,8, built-in trackpad), macOS 26.5 (25F71). The probe
was a ~60-line AppKit program run from a terminal that holds the Accessibility grant
(`AXIsProcessTrusted() == true`). It installed, for `NSEvent.EventType.gesture` (29):
`NSEvent.addGlobalMonitorForEvents`, `NSEvent.addLocalMonitorForEvents`, and a
`CGEvent.tapCreate(.cgSessionEventTap, options: .listenOnly)` whose callback rebuilds an `NSEvent`
and reads `allTouches()`. A second global monitor, for `.mouseMoved` and `.scrollWheel`, showed
whether the trackpad was in use. Nobody made deliberate swipes for the probe. It ran while the
user was working, so the touches are whatever normal use produced.

| Run | macOS three-finger swipes | Length | Pointer/scroll events seen | Global monitor, `.gesture` | Listen-only tap, `.gesture` |
|---|---|---|---|---|---|
| 1 | on (`…ThreeFingerVertSwipeGesture` = 2, `…HorizSwipeGesture` = 2) | 60 s | not counted | **0** | not installed |
| 2 | on (same) | 180 s | 1314 mouse-moved, 762 scroll | **0** | not installed |
| 3 | off (both 0; four-finger horizontal 2, vertical 0) | 240 s | 1952 mouse-moved, 829 scroll | **0** (local monitor: 0 too) | **7361** frames: 1166 with 0 fingers down, 2420 with 1, 2372 with 2, 1403 with 3 |

What that establishes:

- **`NSEvent.addGlobalMonitorForEvents(matching: .gesture)` receives nothing** on 26.5, with
  macOS's three-finger swipes on or off, while the same process's global monitor for pointer and
  scroll events keeps firing. The monitor installs without error (a non-nil token); it is simply
  never called. So the plan in #141 (the global monitor, as SwipeAeroSpace once used) is not usable
  here, and SpacialShell uses the listen-only tap instead. That is still public API only:
  `CGEvent.tapCreate`, `NSEvent(cgEvent:)`, `NSEvent.allTouches()`, `NSTouch.normalizedPosition`
  and `NSTouch.phase`. The private MultitouchSupport framework is not used.
- **The tap sees every touch, whoever it is aimed at:** a frame about every 30 ms while any
  finger is down, one-finger pointer movement included. When the fingers lift, a frame arrives
  whose touches are all `ended`, so "0 fingers down" is observable, and the recognizer resets on it.
- **Nothing is consumed.** A listen-only tap cannot modify or swallow an event (that is what
  `.listenOnly` means), and Apple documents the same for global monitors. So a three-finger swipe
  macOS also uses does both: SpacialShell's step and macOS's Space switch or Mission Control. That is
  why the Problems warning exists (`TrackpadSystemGestures`, key `gestures.system-conflict`).
- **Resting touches.** In run 3's first second, two touches sat near the edges, at
  (0.10, 0.19) and (0.99, 0.37), with `isResting == false`. They were probably palms, but that is not
  known. Touches like that count as fingers, so a three-finger swipe made while they are down reads
  as five, and does nothing.

**Untested:**
- **Does the tap still see three-finger frames while macOS's own three-finger swipes are on?**
  Run 3, the only tap run, had them off. If the Dock claimed those touches before the session tap,
  swipes would silently do nothing with the system gestures on. The Problems warning tells the user
  to move them to four fingers either way.
- **Deliberate swipes.** Recognition thresholds were chosen from the geometry, not from recorded
  swipes. To check: run `SPACIAL_LOG_GESTURES=1 Scripts/dev.sh`, then watch the log
  (`/usr/bin/log stream --predicate 'subsystem == "sh.emu.SpacialShell" && category == "gestures"' --info`).
  Every frame shows its finger count and centroid, and each recognized swipe logs
  `swipe recognized: <direction>`. Record, for a few swipes in each direction, whether exactly one
  step happened.
- **A Magic Trackpad.** Only the built-in trackpad was measured.

## Notes for whoever runs this

- Check 1 is the important one. Everything else is a detail; check 1 can change the product's
  default modifier.
- Record *observations*, not conclusions: "Fn+Q logged as keycode 12 flags 0x800100, no Quick Note,
  nothing typed" is a result. "Fn works" is not.
- If a binding has to move, the change is in `KeyBindings.core` (Kit), its expectation in
  `Tests/SpacialShellKitTests/KeyBindingsTests.swift`, and the table in the spec §6.2.
