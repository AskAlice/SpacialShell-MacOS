# Contributing to SpacialShell

Thanks for helping. The short version: read the model, keep the core pure, run `swift test`, and
show what your change does.

## Setup

macOS 14+ and a Swift 6 toolchain (Xcode 16 or later).

```sh
swift test          # the gate for every change; Kit and Protocol tests are pure and fast
Scripts/dev.sh      # build debug and run in the foreground (needs the Accessibility grant)
Scripts/bundle.sh   # build/SpacialShell.app
make hooks          # pre-commit: build, fast tests, bundle, install to /Applications
```

The hook installs to `/Applications` on every commit; `SPACIAL_SKIP_INSTALL=1` skips the install
and `--no-verify` skips the hook. `Scripts/README` explains the Accessibility (TCC) identity
caveats of running from a checkout.

## Where things go

- **Pure logic lives in `SpacialShellKit`** (wire types in `SpacialShellProtocol`); AppKit stays in
  the app, UI and platform targets. Kit must not grow AppKit dependencies.
- **The UI never mutates `World`.** Every click re-enters `WorldStore.run(_:)` as a `Command`,
  exactly like a hotkey.
- **The reconciler owns geometry.** Panels and insets are data, not layout logic.
- **Borrowed code keeps its attribution** header and is listed in `NOTICE`. Design ideas from
  material-shell and Veshell are welcome. Their code is GPL-3 like SpacialShell, so it is
  licence-compatible; borrowing it still needs an attribution header and a `NOTICE` entry.

Accepted designs are in `docs/superpowers/specs/`, and `docs/design-system.md` is the rulebook for
any UI work. [Testing](docs/testing.md) covers the pure suites, snapshot stories
(`SNAPSHOT_RECORD=1` re-records) and the VM end-to-end harness.

## Pull requests

- One concern per PR, at the granularity of the issue it closes.
- Include the `swift test` pass/fail counts when you touch Kit, Protocol or the store.
- **Show it.** Anything visible ships a screenshot of the change *and* an overview shot of the
  shell, plus a short loop (webp, gif alongside, ≲10 s) of the behaviour. Changes with no visible
  surface show their effect instead: a `spacialctl` transcript or a test run. Renders are fine
  when you can't run the app, if labelled as renders. Media goes in `docs/media/`.
- Say so if you couldn't compile or run the change.

## Issues

Bugs, ideas and tasks live in [GitHub Issues](https://github.com/AskAlice/SpacialShell-MacOS/issues),
organised milestone → epic → story → task. Look for `ready-for-agent` (fully specified) and avoid
`needs-info` until the open question is answered.

## Security

Never commit signing material, API keys or tokens — `*.p8`, `*.p12`, `*.cer` and
`Scripts/sign-identity` are gitignored. Report vulnerabilities privately through GitHub's
security advisories rather than a public issue.
