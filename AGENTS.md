# Agent guide — SpacialShell

SpacialShell is a spatial window manager for macOS (material-shell / Veshell lineage). Read
`README.md` for the model and `docs/superpowers/specs/` for the accepted designs — the
2026-08-19 M2 design's rulings are binding; don't re-open them mid-implementation.
For any UI/design work (Figma imports included), `docs/design-system.md` is the rules doc:
tokens, components, icons, styling, and the six musts for integrating a design.

## Build and test

- `swift test` — the gate for every change. Kit and Protocol tests are pure and must stay green.
- `Scripts/dev.sh` builds debug and runs the app in the foreground (macOS only; needs the
  Accessibility grant — see `Scripts/README` for the TCC identity caveats).
- `Scripts/bundle.sh` produces the signed app bundle.
- `make hooks` enables the repo pre-commit hook: on macOS every commit builds, runs the fast pure
  tests, bundles, and installs to `/Applications` (`SPACIAL_SKIP_INSTALL=1` or `--no-verify` to
  bypass; the hook auto-skips on non-macOS, where CI and a Mac gate the commit instead).
- The app targets macOS 14+; Kit code must not silently grow AppKit dependencies.

## Pull requests

**Every PR must include, inline in its description:**

1. **Screenshots** of the specific changes — UI changes show the UI; non-UI changes show the
   observable effect (a `spacialctl` transcript rendered as an image, a passing `swift test` run,
   a before/after of the tiling the change affects).
2. **Animations** (short loops, webp/gif, ≲10 s each) showing **both** (a) the changed behaviour
   in motion and (b) a general overview of the app's functionality as of that PR — every PR's
   description doubles as a current demo of the whole shell.

No exceptions by change type. A reviewer should see what the change does — and what the app does —
before reading the diff.

What counts, in order of preference:

1. A real capture from a Mac running the change (`Scripts/dev.sh`, then screenshot / screen
   recording; convert to webp/gif loops with `ffmpeg`).
2. Rendered media from the repo's own pipeline — `Scripts/render-m2-media.py` regenerates the
   loops and stills in `docs/media/`; new features should extend that pipeline so the overview
   loop stays current.
3. If authored in an environment that cannot run the app (e.g. a Linux container), rendered
   previews/animations are acceptable **only if clearly labelled as renders, not live captures** —
   and live captures should follow before merge.

Commit media into `docs/media/` (small: webp preferred, gif alongside for inline GitHub playback,
stills as webp/png, keep files small — the showcase loops in `docs/media/` are the size reference)
or attach via the PR upload widget; either way the PR body must show everything inline.

**Embedding committed media (this repo is private):** the only URL schema that renders inline in
PR/issue bodies and the README is
`https://github.com/AskAlice/alice-material/blob/<branch>/docs/media/<file>?raw=true` —
GitHub serves it with the viewer's session. Never use `raw.githubusercontent.com` URLs (proxied
anonymously → broken), never `data:` URIs (stripped by the sanitizer), never `?token=GHSAT…` raw
links (per-file signed tokens that expire within days).

Other PR expectations:

- Keep PRs on the milestone's task granularity (see the design's task list); one concern per PR.
- `swift test` output (pass/fail counts) belongs in the PR description when the change touches
  Kit, Protocol, or the store.
- If the change was authored without compiling (no macOS toolchain available), say so explicitly
  in the PR description — never imply a build that didn't happen.

## Layering rules (short form)

- Everything that can be pure lives in `SpacialShellKit` (or `SpacialShellProtocol` for wire
  types); AppKit stays in the app/platform targets.
- UI never mutates `World` — every interaction re-enters `WorldStore.run(_:)` as a `Command`,
  exactly like a hotkey.
- The reconciler owns geometry; panels/insets are data (`ShellInsets`), not layout logic.
- Harvested AeroSpace files keep their attribution headers; new borrowings go through `NOTICE`.
