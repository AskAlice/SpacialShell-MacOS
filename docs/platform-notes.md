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
log stream --predicate 'subsystem == "sh.emu.SpacialShell"' --info

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
| 5 | **Parking sliver geometry, cross-process** | Switch to a workspace whose windows must be parked, then inspect where the parked windows landed (`log stream` shows the writes; a screenshot of the corner shows the sliver). | The 1×32 sliver at the screen corner (§7.4) survives AX's per-app clamping: apps that refuse a 1 pt width get the zero-width variant (`zeroSliverBundleIDs`, currently Zoom only). Record any app that clamps to something visible. | `pending grant` |
| 6 | **Stacked displays** | With two displays arranged *vertically* (one above the other in System Settings), park windows on both. | Parking picks a corner that is not covered by the other display, so a parked window never shows on the neighbour (§7.4). | `pending grant` |
| 7 | **Observer-subscribe retries** | Launch a heavy app (Xcode, Chrome) while SpacialShell is running and watch the `AXApp` log for retried `AXObserverAddNotification` calls. | Some apps refuse observer registration until they finish launching; the retry loop should show a bounded number of retries and then succeed. Record how many, and any app that never succeeds. | `pending grant` |
| 8 | **Tap survival across sleep / lock** | Sleep the machine (or `pmset sleepnow`), wake it, and press a bound chord. Then lock the screen (⌃⌘Q), unlock, and press one again. Repeat with fast user switching if available. | The tap keeps working. If it does not, the log shows which re-arm path fired: the in-callback `tapDisabledBy*` re-enable, the wake (+3 s) / unlock / session-active nudge, or the 5 s health poll (and whether it had to re-create the port). If the circuit breaker trips it logs `event tap could not be re-created 5× in a row; giving up until the next wake or unlock` — that is five **consecutive** failed re-creations, and any wake, unlock or session activation clears it. Record what preceded it. | `pending grant` |

## Notes for whoever runs this

- Check 1 is the important one. Everything else is a detail; check 1 can change the product's
  default modifier.
- Record *observations*, not conclusions: "Fn+Q logged as keycode 12 flags 0x800100, no Quick Note,
  nothing typed" is a result. "Fn works" is not.
- If a binding has to move, the change is in `KeyBindings.core` (Kit), its expectation in
  `Tests/SpacialShellKitTests/KeyBindingsTests.swift`, and the table in the spec §6.2.
