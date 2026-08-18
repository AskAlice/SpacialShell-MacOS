# Testing

Four tiers, matching spec §12.

## 1. Unit tests

```sh
swift test
```

Runs `SpacialShellKitTests` and `SpacialShellPlatformTests`: the model and its invariants, every
command on hand-built worlds, layout frame math, the reconciler's write planning, config parsing,
hotkey parsing/tables, and property tests that throw random world/command/event sequences at the
model and assert spec §4.2's five invariants still hold plus that `Layout.frames` never returns
overlapping frames. No permissions needed, and it stays well under 5 seconds — if it's taking
longer, something regressed.

Two property-style sweeps are worth knowing about specifically, since a failure names a seed you
can reproduce directly:

- `PropertyTests.randomSequencesPreserveInvariants` (`Tests/SpacialShellKitTests/PropertyTests.swift`)
  drives `World` directly through 200 random seeds.
- `WorldStoreTests.randomSnapshotsPreserveInvariants` (`Tests/SpacialShellKitTests/WorldStoreTests.swift`)
  drives the `WorldStore` actor through a `FakeBackend` — 50 seeds, each replaying 30 random
  `apply(.snapshot(...))` / `run(command)` / `.windowMoved` events — so it also exercises
  adoption-from-snapshot, native focus, and the parking side tables that the direct-`World` sweep
  above never touches.

Both use `Tests/SpacialShellKitTests/Support/TestRNG.swift`, a deterministic SplitMix64 generator
seeded per test case, so `swift test --filter randomSnapshotsPreserveInvariants` reproduces a
specific seed's failure exactly by reading the seed number out of the failure message.

## 2. Classifier corpus regression

```sh
swift test --filter ClassifierCorpusTests
```

`Tests/SpacialShellPlatformTests/ClassifierCorpusTests.swift` replays every fixture under
`axDumps/*.json5` — real AX-tree dumps captured from live apps — through the window classifier and
checks the result against the expected tile/float/ignore verdict recorded alongside each fixture.
This is what pins classifier behaviour against real-world AX quirks (Zoom, Chrome, dialogs, popups)
without needing those apps installed or a live Accessibility grant. Also no permissions needed.

## 3. Platform integration test (opt-in, needs the Accessibility grant)

`Tests/PlatformIntegrationTests/TextEditTests.swift` is the one tier that talks to real windows.
It is gated behind an environment variable so it never runs by accident (in CI or otherwise) and
never blocks `swift test`:

```sh
swift test                                    # TextEditTests is skipped, suite stays green
SPACIAL_INTEGRATION=1 swift test --filter TextEditTests   # actually runs it
```

What it does: opens two plain `.txt` files in TextEdit (via
`NSWorkspace.open(_:withApplicationAt:configuration:)` — deliberately not AppleScript/Apple Events,
which would need a separate Automation TCC grant on top of Accessibility), drives a real
`AXWindowBackend` + `WorldStore` against them, and asserts that `.maximize` parks one window while
showing the other, and that cycling to `.split` shows both. It terminates TextEdit and deletes its
scratch files when done.

**Before it can pass, the test host needs the Accessibility grant.** `swift test` runs the suite
inside an `.xctest` bundle (currently
`.build/arm64-apple-macosx/debug/SpacialShellPackageTests.xctest`, architecture/build-config
folder aside) — like the debug app binary described in `Scripts/README`, TCC identifies this loose
binary by its **path**, not a bundle id, so:

1. Run `SPACIAL_INTEGRATION=1 swift test --filter TextEditTests` once. It will fail (`AXError` /
   timeouts) — that first run is what makes the process request the Accessibility permission and
   register in TCC.
2. Open System Settings → Privacy & Security → Accessibility and tick the checkbox for the test
   runner that just appeared (it may be listed as the `.xctest` bundle, `xctest`, or
   `SpacialShellPackageTests`, depending on Xcode/toolchain version).
3. Re-run the same command. It should pass.
4. Rebuilding changes the ad-hoc signature of the test binary, which can silently invalidate the
   grant (checkbox stays ticked, `AXIsProcessTrusted()` returns false anyway) — the fix is the same
   untick/re-tick or remove-and-re-grant dance described in `Scripts/README`.

The suite creates exactly one `AXWindowBackend` and calls its terminal `stop()` exactly once, at
the end of the one test — `AXApp`'s registry is process-global, so a second backend in the same
process would be unsound.

## 4. Manual checklist

The items below need a human, a real display arrangement, and things a test suite cannot simulate
(unplugging a monitor, locking the screen, a real password field). None of this is automated;
record what you observe.

| # | Check | Procedure | What to look for |
|---|---|---|---|
| 1 | 3-display unplug/replug | Run SpacialShell with three displays attached. Unplug one, wait, replug it. | Windows on the surviving displays keep their positions throughout; the reconnected display's workspace stack comes back instead of being silently dropped; no crash or stuck "parked forever" window. |
| 2 | Lock/unlock | `⌃⌘Q` to lock the screen, wait a few seconds, unlock. | No writes happen while locked (spec §7.7); a fresh reconcile runs on unlock and the model matches reality afterward. |
| 3 | Hung app | Launch a managed app, then `kill -STOP <pid>` it from a terminal. Try to focus/move its window. Then `kill -CONT <pid>`. | The hung app's AX calls time out (bounded by `ax-timeout-ms`) without blocking commands aimed at *other* windows; after `kill -CONT`, the app catches back up on the next reconcile without needing a restart. |
| 4 | Native fullscreen round-trip | Put a managed window into native fullscreen (green-button double-click or the fullscreen shortcut), then take it back out. | The window is removed from its workspace's layout while fullscreen (moved to `ignored`) and is re-adopted at the end of its former workspace when it leaves fullscreen — not duplicated, not lost. |
| 5 | Zoom parking | Get a Zoom window parked (switch away from its workspace, or to a layout that doesn't show it). | Zoom is one of the `zeroSliverBundleIDs` apps — confirm it still parks cleanly (no visible sliver, no window left onscreen) rather than clamping to something visible like some AX-strict apps do. |
| 6 | Secure Input in a password field | Click into a real password field (a browser login form, `login` in Terminal, etc.) so the OS enables Secure Input, then press a bound chord. | Secure Input drops `keyDown` events for every tap system-wide (spec §13.2) — bound chords should silently do nothing while focus is in the field, then work again as soon as focus leaves it. No crash, no stuck modifier state. |
| 7 | Quit restores windows | With several windows parked (on background workspaces or other screens), quit SpacialShell: `Ctrl-C` on the dev binary, or `kill <pid>` (SIGTERM) otherwise. There is no menu bar, so no `⌘Q`, and `Fn+Q` with nothing focused is a no-op, not a quit shortcut. | Either path runs the termination gate (state save → restore parked windows → stop): every *parked* window ends up centred on its screen (spec §7.4) — nothing is left sitting in a parking corner after the app is gone. Windows that were tiled and visible stay exactly where they were: they are already reachable, so the restore leaves them alone rather than piling the whole layout into the middle of the screen. |

Related empirical checks — the hotkey-tap-vs-symbolic-hotkey race, `Fn`+arrow keycodes, parking
sliver geometry, stacked-display parking, and tap survival across sleep/lock — are tracked
separately in `docs/platform-notes.md`, with a `pending grant` result until someone with the
Accessibility grant runs through them. That page also explains *why* those specific checks can't be
scripted (they need a human to watch for a system UI popping up, or a real keyboard chord).
