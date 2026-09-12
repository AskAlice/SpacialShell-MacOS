# Window identity without the private AX call

Date: 2026-09-12
Status: accepted (Alice, 2026-09-12 — App Store distribution confirmed as the goal, option (a))
Implemented: `bd6751f` on `prototype/window-identity`, alongside this document rather than gated
behind it, at Alice's direction
Supersedes: M1 §7.2 ("`WindowRef.id` comes from `_AXUIElementGetWindow`")
Issues: #17 (spike; its first verdict of "not viable" was withdrawn in a follow-up comment — see
"History" at the end), #18 (this change), unblocks #19, #20

## The ruling this replaces

M1 §7.2 states flatly:

> `WindowRef.id` comes from `_AXUIElementGetWindow` — the single private symbol, header-only C
> target (`Sources/PrivateApi/**`). Windows for which it returns nil are dropped (Finder desktop
> etc.).

That symbol is undocumented, and its presence in a binary is an automatic App Store rejection. This
design removes it. Per `CLAUDE.md` a binding ruling is changed by a new accepted design, not by a
patch, which is why this document exists.

## What the spike found, and why the obvious approach is rejected

Issue #17 asked whether an `AXUIElement` can be mapped to a stable `CGWindowID` using public API.
The probe lives on `prototype/window-identity` (`Tools/window-identity-probe/`). Measured on a live
desktop, 858 standard-window observations:

| predictor | correct | wrong | refused |
|---|---|---|---|
| pid + frame + title, layer 0 | 64.8% | 0 | 302 |
| same, any layer | 64.8% | 0 | 302 |
| assignment + onscreen-order tiebreak | 94.4% | 0 | 48 |
| ordinal only (control) | 26.6% | — | — |

The refusals concentrate exactly where a tiling window manager lives: several windows of one app
sharing a tile, hence sharing a frame *and* a title. Six Finder windows on one folder reproduced it
immediately; at 19 windows the safe matcher fell to 47.2%.

Adding an ordering tiebreak lifts the rate but makes it lie: four minimized windows with identical
titles and frames produced **16/16 confidently wrong ids**, every round. Identity that is silently
wrong is worse than absent, because every write in the model is addressed by it — a wrong id moves,
focuses or parks the wrong window and corrupts what gets remembered.

**So deriving a `CGWindowID` from public data is rejected.** Not "unpreferred" — measured and
rejected. Anyone reopening this should reproduce the probe before proposing a matcher.

## The actual requirement

The spike answered the wrong question, because #17 asked the wrong one. SpacialShell never needed a
`CGWindowID`. It needed a *stable key*, and `AXUIElement` already is one.

Measured, same machine: two independently-fetched references to the same window are **different
pointers** but compare `CFEqual`, hash equal under `CFHash`, and Swift's own `==` on the imported CF
type returns true. A plain `[AXUIElement: T]` dictionary hit 5/5 on re-fetched elements and
deduplicated to exactly 5 entries. The property holds across move, minimize, hide/unhide and time
(6/6 windows, every sample). No wrapper type is needed.

`WindowRef.id` was only ever a `CGWindowID` because AeroSpace had the private call handy and the
number was free.

## Design

`WindowIdentities` (`Sources/SpacialShellPlatform/AX/WindowIdentities.swift`) owns a process-wide
`[AXUIElement: WindowID]` map, its inverse, and a monotonic counter. Ids are minted on first sight
and returned unchanged thereafter.

`AXUIElement.windowIdentity()` replaces `containingWindowId()` and is the single mint point. Every
`WindowRef` in the app is constructed from it, so one function covers all of them:

```swift
func windowIdentity() -> WindowID? {
    guard get(Ax.roleAttr) == kAXWindowRole else { return nil }
    return WindowIdentities.id(for: self)
}
```

The role read does both jobs the private call used to do, and the order is load-bearing.

- **Not-a-window filter.** Across 280 live windows, every element the private call gave an id to
  had `AXRole == AXWindow`; the only thing the old filter dropped was Finder's desktop, an
  `AXScrollArea`. Exact replacement, not an approximation.
- **Liveness.** A closed window's attribute read fails with `kAXErrorInvalidUIElement` (-25202,
  measured), so a dead element returns nil here. The role must be read **before** the registry is
  consulted, or a dead element would keep answering with the id it was minted — which is why the
  guard comes first rather than as a later check.

Three properties the design depends on:

1. **Minting is idempotent per element.** `AxUiElementWindowType` compares a window's identity
   against the focused window's by equality; an element minting two ids would break focus detection
   silently. Asserted by `mintingIsIdempotentForTheSameElement`.
2. **Ids are process-wide, not per-app.** A bare id stays unique across apps exactly as a
   `CGWindowID` was, so nothing that passes an id without a pid changes meaning.
3. **Ids start at 1,000,000 and count up.** Above the corpus's recorded `CGWindowID`s (hundreds to
   low thousands) so a dump id can never be mistaken for a minted one, and never colliding with the
   `0xDEAD_BEEF` that `AXAppLivenessTests` uses as a guaranteed-absent id. A hash-based mint would
   break both.

Dead windows are evicted (`WindowIdentities.forget`, plus `forgetWindowLevel`) where `AXApp` already
computes its dead set, so a long session does not accumulate entries. A forgotten element mints a
*fresh* id rather than resurrecting the old one, so a stale `WindowRef` held anywhere can never
resolve onto a live window.

### The dump corpus is untouched

`axDumps` fixtures carry recorded real ids, read via `Aero.axWindowId` in `AxDumpMock`. That path
does not go through the mint and must not: the corpus is a regression record, and rewriting its ids
would destroy the thing it exists to pin down.

## The two window-server crossings

Exactly two places still need a real `CGWindowID`. Both get it from
`WindowIdentities.captureIDs(for:)`, which runs the same public match the spike measured, scoped to
the on-screen list — where the match is strongest, and all either caller cares about. A window
parked in a corner sliver for an inactive workspace is still on screen, so it keeps working. When
the match is ambiguous the function returns nothing rather than guessing.

| crossing | cost of a miss |
|---|---|
| `WindowPreview.swift` — `SCWindow.windowID` for the rail's hover thumbnails | no thumbnail; the card still has its name and icon |
| `windowLevelCache.swift` — `CGWindowList` layer for the classifier | **see below** |

### The window level must fail *open*, and originally did not

This is the part that nearly shipped a serious bug, and it is worth recording why.

A missing level is *not* harmless. `AxUiElementWindowType.isWindowHeuristic` read:

```swift
if windowLevel != .normalWindow && (id == .slack || id == .chrome || id?.isFirefox == true || ...)
```

`nil != .normalWindow` is `true`, so an *unresolvable* level made every Chrome, Firefox, Brave,
Slack, iTerm2, Outlook, Codex and Wispr Flow window classify as "not a window" and never tile —
most of a real desktop. `isDialogHeuristic` had the same shape for 1Password, turning its windows
into floating dialogs.

Under the private call this was nearly unreachable, because a window absent from the list was rare.
Under a best-effort public match it becomes common. Both sites now read `if let windowLevel,
windowLevel != .normalWindow`, so an unknown level takes the default path instead of deciding
anything.

The guard is a test, not a comment: `anUnknownWindowLevelStillClassifiesAsAWindow` replays every
corpus fixture that is a real tiling window with its level withheld. Reverting the fix fails it on
`firefox.json5`, `codex.json5` and `iterm2.json5` (all become `.popup`), which is how the bug was
caught in the first place.

Residual: an always-on-top panel of a gated app may occasionally classify as a normal window when
its level cannot be resolved. Visible, recoverable, and preferable to a browser that refuses to
tile.

## What does not change

- **Nothing on disk.** `PersistedState` has never held a window id, a `WindowRef` or a pid — only
  display UUID → workspace UUID/name/symbol/layout/pinned. M1 §9 rules windows non-persisted and
  §13.3 already recorded that no public cross-restart window id exists, deferring window↔placeholder
  matching to M3b on `(bundle id, title, pid-we-launched)`. That plan is unaffected: a `CGWindowID`
  would not have survived a restart either.
- **Nothing on the wire, today.** `WindowRef` keeps its `{id, pid}` shape. `WireState` carries only
  `windowCount`, and `ShellSnapshot` — the one DTO carrying `WindowRef` — is not yet emitted.
  **Once `ShellSnapshot` ships, minted ids become externally visible to `spacialctl` and any
  scripting consumer**, and the contract must say plainly that an id is opaque, per-run, and not a
  `CGWindowID`. That is a documentation obligation on whoever ships it.
- **Write order.** `Reconciler.swift:68` sorts desired writes by `.id` for determinism. Minted ids
  order differently from window-server ids, so write order changes. It remains deterministic, which
  is all the sort is for.

## Consequences

- `Sources/PrivateApi` is deleted, with its `Package.swift` target and its three `NOTICE` entries.
  No undocumented symbol remains in the binary.
- #19 (sandbox blockers) and #20 (submit) are unblocked.
- Ids are meaningless across runs. They always were.

## Verification

`swift test`: **246 tests in 39 suites passed**, 2 known issues (both pre-existing: the
`bar-twenty-tabs` overflow story, T18/T19). 238/38 before this change; the 8 new tests are
`WindowIdentityTests`.

The live `TextEditTests` integration suite additionally asserts, against two real TextEdit windows,
that ids are distinct, identical across two enumerations, and unchanged across parking, a focus
change and a relayout. Two *pre-existing* frame assertions in that suite fail on this machine — and
fail identically on `main`'s code, verified by A/B — most likely the rebuild-invalidates-the-TCC-grant
hazard documented in `docs/testing.md`, or the 3-display layout. Not a regression from this change,
and not fixed here.

The built binary was checked directly: `nm -u` on `SpacialShell` reports zero references to
`_AXUIElementGetWindow`. That, not the absence of the source directory, is the App Store bar.

## History

The #17 spike's first comment concluded **not viable** and recommended closing #18, #19 and #20
unbuilt. That was withdrawn the same day in a follow-up comment on #17, once the requirement was
reframed from "derive a `CGWindowID`" to "hold a stable identity" and `AXUIElement` was measured
as that key. The original measurements were never wrong; the conclusion drawn from them was. Both
comments are left in place on the issue so the reasoning is auditable — a future reader who finds
only the first would close three tickets on a mistake.

Two other things worth recording for whoever touches this next:

- The private call had been doing a *second* job nobody had written down: its nil return was the
  filter that dropped Finder's desktop. The public replacement (`AXRole == AXWindow`) was found by
  measuring what the private call actually excluded, not by reading its documentation, because it
  has none.
- The window-level fail-open fix was found by an independent audit of the classifier, not by the
  test suite, which had no coverage for a nil level. The corpus-replay test now closes that gap.
