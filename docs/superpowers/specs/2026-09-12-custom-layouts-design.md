# Custom grid layouts — design

Date: 2026-09-12. Status: **proposed**, pending review (issue #7). Delivers a document; no code.
Implementation is issues #9 (expand), #10 (editor), #11 (contract), gated on this being approved.
Rulings below are binding once approved, in the same sense as the M1/M2 designs. §9 lists the M1/M2
rulings this re-opens and why.

## 1. The problem

`Layout` is `enum Layout: String, Codable, CaseIterable { case maximize, split, column, half, grid }`
in `SpacialShellProtocol/CoreTypes.swift`. Nothing about it is private:

- it is a field of `WorkspaceSeed` and `Config.defaultLayout`, decoded from hand-written TOML;
- it is a field of `PersistedState.WorkspaceState`, so it is in `state.json` on Alice's Mac today;
- it crosses the wire as `WireState.WorkspaceDTO.layout` (already a `String` there — see §6);
- `Layout.allCases` *is* the tab-bar switcher (`WorkspacePanelView.layoutSwitcher`), and
  `WorkspacePanelView.symbol(for:)` is an exhaustive `switch` over it;
- `Layout.next` is `cycleLayout` (`Fn+Space`), and `CommandRunner` promotes `.maximize` → `.split`
  on `moveWindow`;
- `LayoutEngine.frames(_:count:focused:in:gap:)` switches on it exhaustively and is the only thing
  the reconciler asks for geometry.

So "let the user draw a grid" is not a feature behind a cog. It changes a wire type, a config
schema, a persisted state schema, the CLI surface and the reconciler's input at once. Hence a
design first, and hence expand → migrate → contract rather than one retype (#9/#10/#11 exist
because a single edit breaks every call site and no slice lands green).

The second, less obvious problem is the one that shapes the whole design: **four of the five
built-ins are functions of the window count, and a FancyZones-style drawn layout is a fixed set of
zones.** `column` is n columns for n windows; `grid`'s last row widens; `maximize`/`split` follow
the focus anchor. No fixed zone list expresses any of them. A design that says "the built-ins are
just seeded data" is wrong, and would have to either re-derive them per count (a generator by
another name) or quietly change how they tile. §5 takes the honest route.

## 2. Rulings

| Question | Decision | Why |
|---|---|---|
| Zone coordinates | **Unit rect, `0…1`, origin top-left, y-down** — `LayoutZone {x, y, w, h: Double}` | Same convention as everything above the backend seam (M1 §3.2). The workspace rect changes with display, insets, Zen and gap; absolute points would be wrong on every second screen. |
| Mapping zone → frame | Map onto the rect **inflated by one `gap` in each axis**, then subtract one `gap` from each zone's width and height. Outer gap is already applied by the reconciler. | Reproduces `LayoutEngine.columns/rows` *exactly* (proof in §3.2), so seeded zone layouts and the built-in generators agree to the point. Any other rule makes the outer columns a half-gap wider and rewrites every tiling test. |
| Overlap | **Editor refuses it; engine tolerates it.** Zones may leave uncovered area (a deliberate hole is legitimate); they may not overlap by more than 1e-6. Zones are clamped to `0…1`; zero/negative zones are dropped at load with a log line. | "Windows are tiled and never overlap" is the M1 thesis (§1, §4.3). But a hand-edited `config.toml` is allowed to be wrong without disarming the file — that is the M1 §9 "invalid config keeps the previous one and logs" temperament, applied per-layout. |
| Editor model | The editor edits a **guillotine grid**: start from an n×m preset, drag interior splitters, merge adjacent cells. It stores **only the zone list**; its grid lines are derived from the distinct zone edges. | One representation, so a layout hand-written in TOML is still editable. Ceiling: a zone set that is not a clean block decomposition of its implicit grid opens **read-only** with "duplicate to edit". Freeform overlapping canvas zones are deferred (§11). |
| Zone precision | `Double`; the editor snaps splitters to multiples of **1/48** (exact halves, thirds, quarters, sixths, eighths, twelfths); validation tolerance 1e-6 | Cheap, and 48ths cover every split a person actually draws. |
| More windows than zones | Windows fill zones in row order; the rest **park** (frames `nil`), keeping their tabs. **The focused/anchor window always gets a zone**: if its index ≥ zone count it takes the last zone and displaces that occupant to parking. | Matches how `maximize`/`split` already overflow, and matches the M3a I6 intent — clicking a tab must show a window, never nothing. Issue #10 asks for exactly this to be predictable and documented. |
| Fewer windows than zones | Trailing zones stay empty. No redistribution. | A drawn layout is a drawn layout; silently restretching it is the thing FancyZones users complain about. |
| Zone below the minimum size | A zone that resolves smaller than the M3a A2 clamp (120 × 80 pt) **parks its window** instead of producing a sliver | The clamp is already the agreed answer for degenerate frames; layouts-as-data must not become a new way to manufacture them. |
| Identity | `LayoutID` — a `RawRepresentable`, `String`-backed, `Codable`, `Hashable` struct. **Never a closed enum again.** Built-in ids keep their exact current raw strings (`maximize`, `split`, `column`, `half`, `grid`). Custom ids are editor-minted slugs (`grid-3x2`, `grid-3x2-2` on collision). | Keeping the raw strings is what makes every existing `config.toml`, `state.json` and wire payload load unchanged through the whole sequence — #11's "a file written before the sequence still loads" becomes a no-op instead of a migration. |
| Definition type | `LayoutDef {id, name, symbol, body}`, `body = .builtin(BuiltinLayout) \| .zones([LayoutZone])`. The name `LayoutDef` is permanent; `Layout` is **retired**, not typealiased, in #11. | Two live spellings of one concept is the drift #11 exists to prevent. A retired name that resolves to nothing is a compiler error, which is the point. |
| Where the built-ins live | **Both, precisely: seeded as catalogue rows, geometry stays generator code.** `.builtin(_)` delegates to today's `LayoutEngine` switch, unchanged. | §5. They are count-dependent; a fixed zone list cannot express them. Pretending otherwise silently changes tiling. |
| Built-ins are immutable | Not deletable, not editable, not shadowable — a user layout may not claim a built-in id (rejected in the editor, ignored on load with a log line). "Duplicate" is the affordance. | The five are the vocabulary of the cheat sheet, the docs and `Fn+Space`. A config that redefines `grid` is a support ticket nobody can read. |
| Persistence — editor output | **`~/Library/Application Support/SpacialShell/layouts.json`**, versioned (`version: 1`), atomic write, same shape and save path as `PersistedState`. Not `config.toml`. Not `settings.json`. Not `state.json`. | The app never writes `config.toml` (2026-09-12 write-back research, Option B; §4 there). Not `settings.json` because that file's contract is "every field optional, `nil` means the file decides" — a union of user content is not an override. Not `state.json` because that is machine-owned and disposable, and layouts are content a user would be upset to lose. |
| Persistence — file-defined | `config.toml` may **define** layouts with `[[layout]]` tables (read-only to the app) and reference any id from `default-layout` / `[[workspace]] layout` | Otherwise the config file can reference what it cannot define, and a dotfile carried to a fresh machine has a dangling default. `[[workspace]]` is the precedent for the shape. |
| Precedence on id collision | `config.toml` **wins** over `layouts.json`. The editor shows a file-defined layout read-only with a "Duplicate" action and a one-line "defined in config.toml" note. | The file is the interface. Same direction of deference as the write-back research's Option B, and it fails loudly rather than by silent shadowing. |
| Catalogue | `LayoutCatalogue(builtins + config.layouts + store.layouts)`, built once in `AppRuntime`, passed to the reconciler and the UI alongside `Config`. `Reconciler.desired(…, layouts: .builtins)` defaults, so every existing call site and test compiles untouched. | Keeps #9 green by construction. |
| Unknown id at **decode** time | Never fails. `LayoutID` decodes any string; resolution happens late, at layout time. The workspace **keeps the id it was given**. | Today an unknown `layout = "foo"` throws out of `decodeIfPresent(Layout.self)` and rejects the entire config or state file. Remembering an unresolved id means fixing the config (or replugging the machine that has `layouts.json`) restores the layout instead of finding it silently rewritten to `maximize`. |
| Unknown id at **resolve** time | `catalogue.resolve(id) ?? catalogue.resolve(config.defaultLayout) ?? .builtin(.maximize)`, logged once per id, and the switcher shows the fallback glyph badged with `exclamationmark.triangle` and a tooltip naming the missing id | A chain with a floor, so there is no state in which the shell has no layout to draw. |
| Unknown id from **`spacialctl` / IPC** | **Refused**: `ok: false`, `error: unknown layout "foo" (known: maximize, split, …)`, exit 1 | Opposite of decode on purpose. A CLI call is an explicit act by a live caller who can be told it was wrong; a config file is user data that must not be discarded for a typo. |
| New wire verb | `list-layouts` → `[{id, name, symbol, zoneCount, builtin, onBar}]`; `state` gains `layoutResolved: Bool` per workspace | Raycast's `set-layout` dropdown is built from the five today; without a discovery verb every client hardcodes them forever. |
| Wire version | Payload stays `v: 1`. `capabilities` gains `"custom-layouts"`. | `WorkspaceDTO.layout` is already `String` on the wire (`WireState.swift`), so a v1 consumer sees no type change — only unfamiliar values, which the M2 ruling already requires clients to degrade on ("unknown layout degrades with warn", Raycast `types.ts`). `capabilities` exists exactly for this. |
| The tab-bar switcher | The catalogue has an ordered **bar set** — the layouts drawn in the switcher *and* cycled by `Fn+Space`. Defaults to the five built-ins, capped at **8**, toggled per layout in the editor. The active layout is always drawn even when it is not in the bar set. A trailing `ellipsis` button opens a menu of **all** layouts (checkmark on the current), with "Edit layouts…" at the bottom. | One concept answers both "what does the bar show at twenty layouts" and "what does `Fn+Space` cycle at twenty layouts". The bar's width stays fixed; the ring stays small enough that `Fn+Space` is still a reflex. |
| `cycleLayout` | Cycles the bar set, in bar-set order; if the active layout is outside the bar set, the first press enters the ring at its start | `Layout.next` (modulo `allCases`) dies with the enum in #11. |
| `moveWindow` layout promotion | The `CommandRunner` rule "`maximize` promotes to `split`" generalises to: **if the resolved layout shows fewer than two windows at this count, promote to `split`** | Keeps today's behaviour for the built-ins and gives a one-zone custom layout the same courtesy. The verb means "put this beside that" (`docs/keybindings.md`). |
| Deleting a layout in use | Allowed. Workspaces keep the dangling id and fall back per the resolve chain. The confirm sheet says "N workspaces use this layout". No silent rewrite of `state.json`. | The dangling-id machinery already has to exist for the unknown-id case, so the delete case costs nothing extra — and a delete that rewrites state cannot be undone by restoring the layout. |
| The cog | Opens the **existing settings window on a new "Layouts" tab**, not a second window | `WorkspacePanelView` already sends `.openSettings` from that cog, `SettingsWindow` already exists, and `Fn+,` should land in the same place. No new window class. |
| Sharing a layout | "Copy as TOML" in the editor, producing a `[[layout]]` block to paste into `config.toml` | No new file format, no importer to write, and it makes the two stores explain each other. Import UI is an open question (§12). |

## 3. Representation

### 3.1 Types (`SpacialShellProtocol`, leaf target — these are wire types)

```swift
public struct LayoutID: RawRepresentable, Codable, Hashable, Sendable { public let rawValue: String }

/// Unit rect on the workspace rect. Origin top-left, y-down (AX convention, M1 §3.2).
public struct LayoutZone: Codable, Hashable, Sendable { public var x, y, w, h: Double }

public enum BuiltinLayout: String, Codable, Hashable, Sendable { case maximize, split, column, half, grid }

public struct LayoutDef: Codable, Hashable, Sendable {
    public enum Body: Codable, Hashable, Sendable { case builtin(BuiltinLayout), zones([LayoutZone]) }
    public var id: LayoutID
    public var name: String         // "3 × 2 grid" — what the menu and tooltip show
    public var symbol: String       // SF Symbol; custom layouts default to "square.grid.3x2"
    public var body: Body
}
```

`LayoutCatalogue` (Kit) holds the merged, ordered list plus the bar set, and exposes
`resolve(_ id: LayoutID) -> LayoutDef?`, `all: [LayoutDef]`, `bar: [LayoutDef]`, `next(after:)`.

### 3.2 Geometry, and why the mapping rule is what it is

For rect `R` (already inset by the outer gap and the −1 pt height by the reconciler) and gap `g`:

```
frame.x = R.minX + zone.x * (R.width  + g)      frame.width  = zone.w * (R.width  + g) - g
frame.y = R.minY + zone.y * (R.height + g)      frame.height = zone.h * (R.height + g) - g
```

Read it as: every zone owns a `g`-wide gutter at its trailing edge, and the rect's own trailing
gutter is the outer gap the reconciler already applied.

This is not a taste choice — it is the only mapping that reproduces the existing engine. For
`column` with n windows, zone i is `x = i/n, w = 1/n`:

```
frame.x     = R.minX + i(W+g)/n
frame.width = (W+g)/n − g = (W − (n−1)g) / n
```

which is `LayoutEngine.columns(n:)` term for term (`w = (W − g(n−1))/n`, origin `i(w+g) =
i(W+g)/n`). The same falls out for `rows`, for `half`'s left column and right-hand stack, and for
`grid` at counts where the last row is full. So the #9 equivalence tests are exact-equality tests,
not tolerance tests:

- a fixed 3-zone column set == `frames(.column, count: 3)` for any rect and gap;
- a fixed 2×2 zone set == `frames(.grid, count: 4)`;
- a `half`-shaped 4-zone set == `frames(.half, count: 4)`.

### 3.3 TOML shape

```toml
default-layout = "grid-3x2"        # any layout id, built-in or defined below

[[layout]]
id = "grid-3x2"
name = "3 × 2 grid"
symbol = "square.grid.3x2"
zones = [
  { x = 0.0,     y = 0.0, w = 0.3333, h = 0.5 },
  { x = 0.3333,  y = 0.0, w = 0.3333, h = 0.5 },
  # …
]

[[workspace]]
name = "Code"
layout = "grid-3x2"
```

## 4. Where layouts live

| Source | Written by | Read | Precedence |
|---|---|---|---|
| Built-ins | the binary | always | lowest, and unshadowable (a redefinition is ignored + logged) |
| `~/.config/spacial-shell/config.toml` `[[layout]]` | **the user, only** | on load and on config reload | highest |
| `~/Library/Application Support/SpacialShell/layouts.json` | the editor | on launch, on editor save | middle |

The app **never writes `config.toml`** — that is the settled position (`Settings.swift`; the
2026-09-12 write-back research, §4 and Option B), and custom layouts do not re-open it. A layout
drawn in the editor is app-owned content in an app-owned store; a layout typed into the dotfile is
the user's and is never touched. The editor must show which is which, or the user edits the TOML
and sees nothing change — the exact support burden the research names as Option B's one real cost.

`layouts.json` is its own file, not a section of `settings.json` or `state.json`: `settings.json`
means "overrides of file-set keys", which a union of definitions is not; `state.json` is
machine-owned and cheerfully discarded on schema drift, which user-drawn layouts must never be.

## 5. The five built-ins once layouts are data

**Seeded as data, computed as code — both, and not by compromise.**

Each built-in is a `LayoutDef` in the catalogue with its existing id, its existing SF Symbol
(`WorkspacePanelView.symbol(for:)` moves onto `LayoutDef.symbol` and stops being an exhaustive
switch) and `body = .builtin(_)`. Every consumer — the switcher, `list-layouts`, the menu, the
editor list, `cycleLayout` — sees five ordinary catalogue rows and needs no special case.

Their *geometry* stays in `LayoutEngine`'s existing switch, untouched, because four of the five are
functions of the window count and cannot be written as a fixed zone list:

| Built-in | Count-dependence |
|---|---|
| `maximize` | one slot, at the anchor index; every other window parks |
| `split` | two slots, chosen relative to the anchor (right neighbour, or left when the anchor is last) |
| `column` | n slots for n windows |
| `half` | 1 + (n−1); the right-hand stack's row height depends on n |
| `grid` | `cols = ceil(√n)`, `rows = ceil(n/cols)`, and the last row's cells widen to fill |

So `LayoutEngine.frames` grows one dispatch:

```swift
public static func frames(_ def: LayoutDef, count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
    switch def.body {
    case .builtin(let b): return frames(b, count: count, focused: focused, in: rect, gap: gap)  // today's code
    case .zones(let z):   return zoneFrames(z, count: count, focused: focused, in: rect, gap: gap)
    }
}
```

Anything that later wants `column`-as-data needs parametric zones (a zone whose count is a function
of n), and that is deferred (§11) — not smuggled in here by degrading `column` into a fixed 3.

## 6. The wire, `spacialctl`, and ids nobody knows

`WireState.WorkspaceDTO.layout` is already typed `String`. That is the whole compatibility story:
the field's *type* never changes, only the set of values that can appear in it. `v` stays `1`,
`capabilities` gains `"custom-layouts"`, and the M2 ruling that clients degrade gracefully on an
unknown layout (Raycast `parseState`) is what makes that safe — a client that ignored the ruling
breaks, and its own spec said it would.

Two different answers for an id the receiver has never heard of, on purpose:

- **Reading persisted user data** (config, `state.json`, an IPC payload arriving at a client) —
  keep the id, resolve late, fall back per the chain, badge it in the UI, log once. The user's
  choice is data; losing it is worse than not honouring it today. This also *fixes* a current
  sharp edge: `layout = "foo"` today throws out of the decoder and rejects the whole file.
- **Executing a command** (`spacialctl set-layout foo`, IPC `set-layout`) — refuse with
  `ok:false`, a message naming the known ids, exit 1. A live caller can be corrected.

New/changed CLI surface: `spacialctl list-layouts` (`--json` by default, table with `--no-json`),
`spacialctl set-layout <id> [--workspace <uuid>]`, and `state`'s workspace rows gain
`layoutResolved`. `spacialctl` links `SpacialShellProtocol` only; nothing here changes that.

## 7. The switcher at twenty layouts

Today: `ForEach(Layout.allCases)` → five 24 pt glyphs, then the cog. Twenty would be 480 pt of tab
bar, on a 34 pt-high bar that also holds every window tab.

The **bar set** (≤ 8, default the five built-ins, per-layout toggle in the editor) is what the
switcher draws, plus the active layout when it is outside the set, plus one `ellipsis` button
whose menu lists every layout with a checkmark on the current one and "Edit layouts…" last. `Fn+Space`
cycles the same set, so the bar is an honest picture of what the keyboard does — the property the
five built-ins have today and the thing that quietly breaks if the bar and the ring diverge.

## 8. A workspace whose layout was deleted

The workspace keeps the id. `resolve` falls through to `config.defaultLayout`, then to `maximize`.
The switcher draws the fallback's glyph with an `exclamationmark.triangle` badge and the tooltip
*"layout "grid-3x2" is missing — using maximize"*. Nothing is rewritten: restore `layouts.json` from
a backup, or paste the `[[layout]]` block back into `config.toml`, and the workspace is itself again.

Deleting from the editor is allowed and the confirm sheet names the cost ("3 workspaces use this
layout"). Re-pointing those workspaces in the delete sheet is desirable polish, not a gate on #10.

## 9. M1/M2 rulings this re-opens

| Ruling | Source | Change | Justification |
|---|---|---|---|
| `Layout` is a closed, `String`-backed, `CaseIterable` enum of five | M1 §4.1; `CoreTypes.swift` | Retired in #11; replaced by `LayoutID` + `LayoutDef` + catalogue. `BuiltinLayout` keeps the five cases and their raw strings. | This is the ticket. The enum's closedness is the single fact that makes user-defined layouts impossible; nothing else in M1 depends on it being closed. |
| `LayoutEngine.frames` signature | M1 §5 | Takes a `LayoutDef`; the built-in overload stays and keeps its body verbatim | The *property* M1 states — "a pure total function", index `i` is tiled window `i`, `nil` means parked — is preserved exactly. Only the first parameter's type moves. |
| `default-layout` / `[[workspace]] layout` are one of five names | M1 §9; `docs/config.md` | Any layout id; `[[layout]]` tables added to the schema | A config that can reference a custom layout but not define one is not portable between machines. |
| `Command.setWorkspaceLayout(UUID, Layout)` | M2 Decisions (verb set) | Payload becomes `(UUID, LayoutID)` | The distinct-base-name rule that ruling actually protects is untouched; only the payload type changes. |
| `ShellSnapshot.WorkspaceRow.layout` | M2 Decisions (Snapshot) | Carries an id string plus `layoutResolved`; `v` stays 1, `capabilities` gains `custom-layouts` | Additive. `WireState` already sends a `String`, and the M2 snapshot ruling's own escape hatch (`capabilities`) is what it is for. |
| "the layouts on the bar are the five built-in ones" | `WorkspacePanelView.swift` comment + the M2 switcher design | Bar shows the bar set (default: the same five) + the active layout + an overflow menu | The comment already calls the cog "the way to everything else about them"; this is that sentence coming due. |
| Zen/insets, parking, reconciler ownership of geometry, panels-as-data | M2 Decisions | **Not re-opened** | Zones are data; the reconciler still owns geometry and still receives insets as data. |
| The app never writes `config.toml` | `Settings.swift`; 2026-09-12 write-back research | **Not re-opened — reinforced.** The editor writes `layouts.json` only. | Every option in that research that writes the file costs ~880 lines of line surgery or a second TOML dependency, and its worst failure mode is deleting a user's config. Nothing about drawing a grid is worth that. |

Not a ruling but worth flagging: M3a task A2 (minimum-size clamp) becomes load-bearing here — a
drawn layout is the easiest way yet invented to ask for a 40 pt-wide window. If A2 has not landed
when #10 does, #10 carries the clamp.

## 10. Sequencing (#9 → #10 → #11)

**#9 — expand. Nothing user-visible; the catalogue contains exactly five.**

1. Protocol: `LayoutID`, `LayoutZone`, `BuiltinLayout`, `LayoutDef` + codec tests (round-trip, and a
   `LayoutID` decode of a string no build has ever seen).
2. Kit: `LayoutCatalogue` (merge, precedence, bar set, `next(after:)`) + tests, including built-in
   shadowing ignored and `config.toml` beating `layouts.json`.
3. Kit: `LayoutEngine.frames(LayoutDef,…)` + `zoneFrames` + the §3.2 **exact-equality** tests
   (column-3, grid-2×2, half-4), overflow/anchor-displacement, and the min-size park.
4. Kit: `LayoutStore` over `layouts.json` (versioned, atomic, same shape as `PersistedState`) + tests.
5. Config: `[[layout]]` decoding; `defaultLayout`/`WorkspaceSeed.layout` become `LayoutID` with
   late resolution; a test that `layout = "nonsense"` no longer rejects the file.
6. `Reconciler.desired(…, layouts: LayoutCatalogue = .builtins)`; `PersistedState` layout field
   becomes `LayoutID` (raw strings unchanged → old files load byte-identically).
7. IPC: `list-layouts`; `set-layout` resolves against the catalogue and refuses unknown ids;
   `state` gains `layoutResolved`; `capabilities` gains `custom-layouts`. `spacialctl` verbs to match.

Exit: five layouts on the bar, identical tiling, no story-snapshot changes, `Layout` still compiles.

**#10 — the editor, behind the cog.** Settings window gains a Layouts tab (`.openSettings` already
arrives there); list of catalogue rows with source badges; guillotine-grid canvas (preset → drag
splitters → merge cells → name → save); duplicate; delete with the usage count; bar-set toggle;
"Copy as TOML"; overflow `ellipsis` menu in the switcher; badge for unresolved ids. Editor geometry
(splitter derivation, merge legality, snap to 1/48, overlap rejection) is **pure Kit with its own
tests**; the canvas is a thin AppKit/SwiftUI view over it — the layering rule.

**#11 — contract.** Delete `Layout`, the typealias shims and every compatibility overload;
`WorkspacePanelView` off `Layout.allCases` and off its exhaustive symbol switch; `Layout.next` gone
(`catalogue.next(after:)` is the only cycler); `docs/config.md`, `docs/ipc.md`, `docs/keybindings.md`
and the cheat sheet updated to their final form. The "old file still loads" criterion is satisfied
by construction (built-in raw strings never changed), and the test that proves it is a fixture
`state.json`/`config.toml` captured *before* #9 and decoded after #11.

## 11. Deferred, deliberately

- **Parametric zones** (a zone that repeats per window, which is what would let `column` become
  data). Needed only if someone wants a user-defined count-dependent layout; nobody has asked.
- **Freeform / overlapping FancyZones canvas zones.** The guillotine grid is what "custom grid
  layouts" means in the issue title.
- **Per-app zone affinity** (FancyZones' app-to-zone rules). Belongs with `[[float]]`/`[[ephemeral]]`
  window rules, not with geometry.
- **Drag a window onto a zone** (FancyZones' defining interaction). Lives in M2's `DragTap`
  territory, not in the editor — see §12.
- **Per-display / aspect-aware layouts** — see §12.
- **Importing a layout file.** "Copy as TOML" covers sharing in one direction; an importer is UI
  with a file picker and no demand yet.

## 12. Open questions for review

1. **Aspect ratio / per-display scoping.** A zone set drawn on a 32:9 ultrawide is nonsense on a
   laptop panel, and unit coordinates hide that rather than solve it. Options: (a) a layout is a
   layout, scale it and let the min-size clamp park what doesn't fit (my lean — it is the M1 posture
   toward displays and costs nothing); (b) `LayoutDef` carries an optional aspect hint and the
   switcher hides layouts far from the current screen's aspect; (c) layouts are scoped per display
   UUID like `PersistedState`. This is a product call, not an engineering one.
2. **Does #10 include drag-a-window-onto-a-zone?** It is the interaction most people mean by
   "FancyZones", it needs `Fn+Drag`/`DragTap` (M2 task 23, still deferred), and it would roughly
   double #10. I have scoped #10 as *draw and select*, per its own acceptance criteria. If the
   intent was the drag too, it should be a fourth issue between #10 and #11, not a bigger #10.
3. **Bar-set cap of 8.** Chosen from geometry (8 × 24 pt = 192 pt of a 34 pt bar that also holds
   window tabs), not from use. If the real ceiling is "as many as fit, computed", say so now — it
   changes `LayoutCatalogue.bar` from a stored list to a derived one.

## 13. Verification

- `swift test` green at every slice; #9 changes no story snapshot.
- Exact-equality tests binding zone geometry to the existing engine (§3.2) — the single most
  important test in the sequence, because it is what makes "the built-ins are catalogue rows" true
  rather than approximately true.
- Property test extension: random catalogues (built-ins + random legal zone sets) through
  `Reconciler.desired`, asserting the M1 invariants and M3a's I6 — every non-hidden window on an
  active workspace either has a frame inside its display or is parked with a tab.
- Round-trip fixtures: a pre-#9 `config.toml` and `state.json` decoded on the post-#11 build.
- Per AGENTS.md, #10's PR carries an editor animation plus the overview loop; #9 and #11 show
  `swift test` counts and a before/after of unchanged tiling.
