# Testing

Four tiers, matching spec §12.

## 1. Unit tests

```sh
swift test
```

Runs `SpacialShellKitTests`, `SpacialShellPlatformTests`, and `AXAppLivenessTests` (the one
member of `PlatformIntegrationTests` that needs no Accessibility grant — it pins that every `AXApp`
call answers and that `destroy()` is final): the model and its invariants, every
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

### Declare every module a test imports (#156)

A test target must list **every package module it imports** in `Package.swift`, even one that
another dependency already brings in. Otherwise incremental `swift test` can segfault after a
change to a Kit struct:

- SwiftPM re-runs a target's compile only when a *declared* dependency's `.swiftmodule` changes.
  A module reached transitively (`ShellStoryTests` → `SpacialShellUI` → `SpacialShellKit`) can
  be imported, but it is not a build input.
- Adding a stored property to `Config` or `World` rewrites `SpacialShellKit.swiftmodule`. Platform
  and UI recompile but keep the same interface, and the compiler leaves those `.swiftmodule`
  files untouched. So a test target that lists only Platform or UI is never rebuilt, and its
  objects keep the struct's old layout.
- Value-copy helpers such as "outlined init with copy of Config" are weak symbols, emitted into
  every object that copies the struct. The linker keeps one of them. If it keeps the stale copy,
  it breaks *every* caller, recompiled ones included. The crash is signal 11 in `swift_retain`
  ← `outlined init with copy of Config` ← `Config.init()`, in whichever test first copies the
  struct (`SettingsTests`, `AXWindowBackendTests`, `KeyboardGrammarTests`, …).

`Scripts/check-target-deps.py` fails when a target imports a sibling target it doesn't declare.
The pre-commit hook and CI both run it. SwiftPM's own
`--explicit-target-dependency-import-check` accepts transitive modules, so it doesn't catch this.
If a local build crashes this way anyway, `swift package clean` recovers.

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
never blocks `swift test`. (Its target-mate `AXAppLivenessTests` is *not* gated — it needs no grant
and runs in tier 1 above.)

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

## Story snapshots (`Tests/ShellStoryTests`)

Storybook for the shell: every interesting state of the rail, tab bar, overview and cheat sheet is
a fixture "story" (`Stories.swift`), rendered at true panel geometry in light and dark. Each story
is image-snapshotted (references under `__Snapshots__/`, committed; `SNAPSHOT_RECORD=1 swift test
--filter ShellStoryTests` re-records) and run through `LayoutLint`, which fails on overlapping
text, content escaping its container, or content that wants more space than the panel has —
the wrap/truncate/line-height class of regressions a pixel diff alone can hide. Stories flagged
`knownOverflow` model conditions the design hasn't built handling for yet (tab "+N" badge, rail
overflow) and run under `withKnownIssue`. Before its snapshot, each story is spun on the run loop
until five passes in a row render identically (#159), not for a fixed time. So a scroll into view
is in the picture however loaded the machine is. A story whose view focuses a field as it appears
(the overview) is marked `awaitsFocus`, and it also waits until that field holds focus. A story that
never stops changing fails as "never settled", so give it fixed inputs (`reduceMotion: true`, a
fixed `elapsed`, fixture images at a fixed pixel size). macOS-only; new UI states get a story with their PR,
and the recorded stills feed the PR-media rule in `AGENTS.md`.

The items below need a human, a real display arrangement, and things a test suite cannot simulate
(unplugging a monitor, locking the screen, a real password field). None of this is automated;
record what you observe.

| # | Check | Procedure | What to look for |
|---|---|---|---|
| 1 | 3-display unplug/replug | Run SpacialShell with three displays attached. Unplug one, wait, replug it. | Windows on the surviving displays keep their positions throughout; the reconnected display's workspace stack comes back instead of being silently dropped; no crash or stuck "parked forever" window. |
| 2 | Lock/unlock | `⌃⌘Q` to lock the screen, wait a few seconds, unlock. | No writes happen while locked (spec §7.7); a fresh reconcile runs on unlock and the model matches reality afterward. |
| 3 | Hung app | Launch a managed app, then `kill -STOP <pid>` it from a terminal. Try to focus/move its window. Then `kill -CONT <pid>`. | The hung app's AX calls time out (bounded by `ax-timeout-ms`) without blocking commands aimed at *other* windows; after `kill -CONT`, the app catches back up on the next reconcile without needing a restart. |
| 4 | Native fullscreen round-trip | Put a managed window into native fullscreen (green-button double-click or the fullscreen shortcut), then take it back out. | While fullscreen the window keeps its tab, is never moved or parked by the shell, and the rail and tab bar do not draw over its fullscreen Space. Focus another app, then click its tab (or `Fn+A/D` to it): macOS switches back to the fullscreen Space. When it leaves fullscreen it retiles in its own slot — not duplicated, not lost. |
| 5 | Zoom parking | Get a Zoom window parked (switch away from its workspace, or to a layout that doesn't show it). | Zoom is one of the `zeroSliverBundleIDs` apps — confirm it still parks cleanly (no visible sliver, no window left onscreen) rather than clamping to something visible like some AX-strict apps do. |
| 6 | Secure Input in a password field | Click into a real password field (a browser login form, `login` in Terminal, etc.) so the OS enables Secure Input, then press a bound chord. | Secure Input drops `keyDown` events for every tap system-wide (spec §13.2) — bound chords do nothing while focus is in the field, then work again as soon as focus leaves it. No crash, no stuck modifier state. Within about 2 s the rail cog lists "*App* is waiting for a password ('*window title*', on workspace *N*)…" (#193), and **Show window** brings that window up; it clears within about 2 s of leaving the field. |
| 7 | Quit restores windows | With several windows parked (on background workspaces or other screens), quit SpacialShell: `Ctrl-C` on the dev binary, or `kill <pid>` (SIGTERM) otherwise. There is no menu bar, so no `⌘Q`, and `Fn+Q` with nothing focused is a no-op, not a quit shortcut. | Either path runs the termination gate (state save → restore parked windows → stop): every *parked* window ends up centred on its screen (spec §7.4) — nothing is left sitting in a parking corner after the app is gone. Windows that were tiled and visible stay exactly where they were: they are already reachable, so the restore leaves them alone rather than piling the whole layout into the middle of the screen. |

Related empirical checks — the hotkey-tap-vs-symbolic-hotkey race, `Fn`+arrow keycodes, parking
sliver geometry, stacked-display parking, and tap survival across sleep/lock — are tracked
separately in `docs/platform-notes.md`, with a `pending grant` result until someone with the
Accessibility grant runs through them. That page also explains *why* those specific checks can't be
scripted (they need a human to watch for a system UI popping up, or a real keyboard chord).
