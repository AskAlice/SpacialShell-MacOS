# Custom grid layouts — design

Date: 2026-09-25. Status: **proposed**, pending review (issue #7). Delivers a document; no code.
Implementation: #9 (expand), #10 (editor, absorbing #15), #11 (contract); epic #45. Once
approved, the rulings below bind in the same sense as the M1/M2 designs. §10 lists the M1/M2
rulings this re-opens.

**Supersedes `2026-09-12-custom-layouts-design.md`.** That draft was never approved. Since it
was written, #54 (minimum-size floor with paging), #64/#67/#77 (the switch-motion planner and
its prefetch), #61's retirement, #74 (the settings window's Workspaces tab) and the 2026-09-24
ruling on #15 have landed. Several of its rulings no longer match the code. Its geometry mapping
(§4.2) and the "built-ins stay generators" position (§5) carry over unchanged. Its changed rulings
are listed in §12. When this document is approved, epic #45's body should point here.

## 1. The problem

`Layout` is `enum Layout: String, Codable, CaseIterable { case maximize, split, column, half, grid }`
in `SpacialShellProtocol/CoreTypes.swift`, with a Kit typealias (`Model.swift`). It reaches:

| Where | How |
|---|---|
| Model | `Workspace.layout`, `World.defaultLayout`, `World.empty(…defaultLayout:)` |
| Config | `Config.defaultLayout` (`default-layout`), `WorkspaceSeed.layout` (`[[workspace]] layout`), decoded with `decodeIfPresent(Layout.self)`. **An unknown string throws and rejects the whole file.** |
| State | `PersistedState.WorkspaceState.layout`. The same throw rejects the whole `state.json`. |
| Wire | `WireState.WorkspaceDTO.layout` is **already a `String`** (`ws.layout.rawValue`); `WireState.v == 2`. `ShellSnapshot.WorkspaceRow.layout: Layout` is typed, but `ShellSnapshot` is *not yet emitted* (header comment). |
| `spacialctl` | Only `version`, `state`, `run <command-name>`. No verb carries a layout; `run cycle-layout` is the only layout verb. Raycast reads `layout: string` and has no `set-layout`. |
| Commands | `.cycleLayout` → `Layout.next` (modulo `allCases`); `.setWorkspaceLayout(UUID, Layout)`; `moveWindow` promotes `.maximize` → `.split`. |
| Engine | `LayoutEngine.frames(_:count:focused:in:gap:)`, which is the #54 page loop around `unfloored`, an exhaustive switch. |
| Reconciler | `Reconciler.desired(…config: LayoutConfig(gap:)…)`, called at 3 sites in `WorldStore`, one of them the #77 `predictedSwitches` prefetch. |
| UI | `WorkspacePanelView.layoutSwitcher` is `ForEach(Layout.allCases)`; `symbol(for:)` is an exhaustive switch; `ShellUIState.layout: Layout`; placeholder `layout: .maximize` in `ShellController`. |
| Cheat sheet | `Hint.after(.cycleLayout)` prints `layout.rawValue.capitalized`. |
| Rail | Nothing. The #61 schematic was retired (`5ef92a3`): "the rail stays narrow and shows apps, not arrangement". |

Two facts shape the design:

1. **Four of the five built-ins are functions of the window count**, and `maximize`/`split` are
   functions of the focus. A FancyZones layout is a fixed zone list. No fixed list expresses
   `column` (n columns for n windows) or `grid` (a widened last row). "Built-ins are seeded data"
   would be false.
2. **#54 already defined overflow.** When windows cannot all get 120 × 80 pt, the engine lays out
   the largest page of `k` that fits, namely the contiguous run that holds the focused window,
   and parks the rest (they keep tabs). A drawn layout with Z zones is the same shape as a layout
   whose capacity is Z, so custom layouts reuse the page rule instead of inventing a second one.

## 2. Rulings

| Question | Decision | Why |
|---|---|---|
| Identity | `LayoutID`, a `String`-backed `RawRepresentable` struct in **Protocol**. It encodes as a bare string and has static members `.maximize … .grid`. It is never a closed enum again. | Encoding is byte-identical to today's enum, so every existing `config.toml`, `state.json` and wire payload loads unchanged. The static members keep every `ws.layout == .maximize` call site compiling through #9. |
| Definition | `LayoutDef {id, name, symbol?, body}` in **Kit**, with `body = .builtin(BuiltinLayout)` or `.zones([LayoutZone])` | Only the id crosses the Protocol boundary. `spacialctl` never needs geometry, so the leaf target stays small. |
| Zone coordinates | Unit rect `0…1`, origin top-left, y-down: `LayoutZone {x, y, w, h: Double}` | This is M1 §3.2's AX convention. The workspace rect changes with display, insets, Zen and gap. |
| Zone → frame | Map onto the rect **inflated by one gap**, then subtract one gap from width and height (§4.2) | It is the only mapping that reproduces `columns`/`rows` exactly, so the equivalence tests are `==`, not tolerances. |
| Zone order | The order of the `zones` array is the **fill order**. The editor defaults to row-major (y, then x) and shows zone numbers, as FancyZones does. | Window `i` of the page goes to zone `i`. This follows M1 §5: index `i` is tiled window `i`. |
| Overlap / holes | The **editor refuses overlap** (> 1e-6); the **engine tolerates it**. Holes are allowed. Zones are clamped to `0…1`, and degenerate zones are dropped at load with a log line. | "Windows never overlap" is the M1 thesis. A hand-edited config may be wrong without disarming the file, per M1 §9. |
| More windows than zones | **#54 paging with page size = usable zones.** The page containing the focused window fills zones 0…k-1; the rest park and keep their tabs. | This is one overflow rule for the whole engine. The focused window always has a zone, and moving focus inside a page moves nothing (§4.3). |
| Fewer windows than zones | Trailing zones stay empty. Nothing restretches. | A drawn layout is a drawn layout (open question Q2). |
| Focused-window slot | **None.** No zone is "the focus zone". Focus picks the *page*, not a zone. | A focus zone would re-seat windows on every Fn+A/D and the #77 planner would animate constantly, which contradicts #54's "focus inside a page moves nothing". `maximize`/`split` keep their focus behaviour as generators. |
| Zone below 120 × 80 | Dropped from capacity **for this rect**. A 6-zone ultrawide layout on a laptop may have capacity 4. If capacity is 0, the focused window gets the whole rect (#54's existing floor). | #54's guarantee is "no layout ever returns a frame < 120 × 80". Layouts as data must not become a way round it. |
| Built-ins | **Seeded as catalogue rows; geometry stays generator code.** `.builtin(b)` calls today's `unfloored` switch verbatim. | They are count- and focus-dependent (§5). |
| Built-ins immutable | They cannot be deleted, edited or shadowed. A user layout claiming a built-in id is refused in the editor, and ignored with a log line on load. "Duplicate" is the affordance. | They are the vocabulary of the cheat sheet, the docs and `Fn+Space`. |
| Persistence | **Both.** `config.toml` `[[layout]]` (read-only to the app) **and** `settings.json` (`SettingsOverrides.layouts`, written by the editor) | The file stays the interface. The editor needs a store the app can write, and the app never writes `config.toml` (write-back research, Option B). |
| Which wins | **`settings.json` wins, per id**, merged over the file exactly like `keybindingOverrides` (`merge { _, gui in gui }`). The editor marks a file layout it has changed as *overridden*, with **Reset** (the existing `row(…overridden:reset:)` pattern). | This is the shipped precedent in `Settings.effective`: every key the settings window touches wins over the file. A second, opposite rule only for layouts would be a trap (§3). |
| Unknown id when **decoding** | Never fails. The workspace **keeps the id**; resolution is late. | Today a typo rejects the whole config or state file. Keeping the id means restoring the layout also restores the workspace. |
| Unknown id when **resolving** | `catalogue[id] ?? catalogue[config.defaultLayout] ?? maximize`, logged once per id. The switcher badges it. | A chain with a floor: there is never a moment with nothing to draw. |
| Unknown id from **IPC** | Refused: `ok:false`, `unknown layout "foo"`, exit 1 | A live caller can be corrected. A config file is user data and must not be discarded for a typo. |
| Wire | `WorkspaceDTO.layout` stays the id string. `state` gains top-level `layouts: [LayoutDTO]`. `capabilities += "layouts"`. **`v` stays 2.** | This is additive. Raycast already treats `layout` as an opaque string. |
| Switcher at 20 | A **bar set** (ordered, ≤ 8, default the five built-ins), plus the active layout when it is outside the set, plus a trailing `ellipsis` menu listing every layout, with "Edit layouts…" last | The bar keeps a fixed width, and Fn+Space cycles exactly what the bar shows (§7). |
| `cycleLayout` | Cycles the bar set. From outside the set, it enters at the start. | `Layout.next` dies with the enum. |
| `moveWindow` promotion | "`maximize` → `split`" generalises to: **if the resolved layout's capacity at this count is < 2, promote to `split`** | This is today's behaviour for built-ins, and gives a one-zone custom layout the same courtesy. |
| Deleted layout in use | Allowed. Workspaces keep the dangling id and fall back per the chain, with a badge. The confirm sheet names the usage count. `state.json` is never rewritten. | The dangling-id machinery exists anyway, and a delete that rewrites state cannot be undone by restoring the layout. |
| The cog (#15) | Opens a **layout popover** from the non-activating panel. It lists every layout by name with the active one marked, plus "Set as default", bar toggles, and **New / Edit…**. New / Edit opens the **editor window**, the one surface that takes key focus, because naming needs typing. | This is the 2026-09-24 ruling on #15 ("defer to the M3c layout editor"). It also meets #15's no-focus-steal criterion for everything except typing. |
| Editor model | A **guillotine grid**: start from an n×m preset, drag splitters (snapped to 1/48), merge adjacent cells. Only the zone list is stored. Pure Kit (`GridEditor`), with a thin AppKit/SwiftUI canvas. | One stored representation, and the layering rule. A zone set that is not a clean block decomposition opens read-only with "Duplicate to edit". |
| Glyph | Built-ins keep their SF Symbols. A custom layout draws its **zones as a 16 × 12 pt glyph** unless a `symbol` is set. | Twenty identical `square.grid.3x2` glyphs are unreadable. #61 retired a schematic on the *rail*, not a glyph in the switcher. |

## 3. Persistence

### 3.1 Sources and precedence

| Source | Written by | Holds | Precedence |
|---|---|---|---|
| Built-ins | the binary | the five | Cannot be shadowed. A redefinition is ignored and logged. |
| `config.toml` | the user only | `[[layout]]`, `layout-bar`, `default-layout` | base |
| `settings.json` | the settings window / editor | `layouts`, `layoutBar`, `defaultLayout` | **wins per id / per key** |

`Settings.effective(config:overrides:)` stays the single merge point. It already produces the
`Config` the shell runs on, so the catalogue is built from the effective config and nowhere else:

```swift
// SettingsOverrides (Kit) — additions; every field optional, nil = "the file decides"
public var layouts: [LayoutDef]?          // merged per id over config.layouts; GUI wins
public var layoutBar: [LayoutID]?         // replaces the file's list wholesale (like categoryOrder)
public var defaultLayout: LayoutID?

// Settings.effective
if let v = overrides.layouts { c.layouts = LayoutDef.merge(file: c.layouts, gui: v) }  // by id, gui wins
if let v = overrides.layoutBar { c.layoutBar = v }
if let v = overrides.defaultLayout { c.defaultLayout = v }
```

A layout **defined only in `settings.json`** can be deleted from the editor, which removes the
entry. A layout **defined in `config.toml`** cannot be deleted from the app, because the file is
the user's. The editor offers **Hide from bar**, plus **Reset** if it has overridden the layout.
Deleting a file layout means editing the file. No tombstone list is needed.

Why not a separate `layouts.json`, as the 09-12 draft ruled? `settings.json`'s contract
("overrides of file-set keys, nil = the file decides") *already* covers a keyed union.
`keybindingOverrides` is exactly that shape, merged per key with the GUI winning. A third file
would mean a third load/save path in `AppRuntime` with its own corruption story. The draft's
"config wins" rule was the *opposite* of what every other key in the settings window does. A
user who edits a layout in the editor and sees nothing change, because the file silently wins,
is the Option B support burden the write-back research warned about.

### 3.2 A corrupt entry must not lose drawn layouts

`AppRuntime.loadOverrides` treats an undecodable `settings.json` as "nothing overridden", and the
next `saveOverrides` **overwrites it**. That is harmless for a gap value and destructive for
twenty drawn layouts. #9 closes it in two lines of policy:

- `layouts` decodes **lossily per entry**. A bad `LayoutDef` is dropped with a log line and the
  rest load. One bad zone cannot fail the file.
- If the file as a whole is unreadable, it is **renamed to `settings.json.bad-<ISO date>`** before
  anything writes, and the error names the backup.

(The overwrite hazard exists today, independent of layouts. It should be filed as its own bug and
fixed by #9.)

### 3.3 TOML shape

```toml
default-layout = "code-3"            # any id: built-in, [[layout]], or editor-drawn
layout-bar = ["maximize", "split", "column", "code-3"]   # optional; default = the five

[[layout]]
id = "code-3"
name = "Code, three"
# symbol = "sidebar.left"            # optional SF Symbol; omitted → drawn from zones
zones = [
  { x = 0.0,  y = 0.0, w = 0.5,  h = 1.0 },
  { x = 0.5,  y = 0.0, w = 0.5,  h = 0.5 },
  { x = 0.5,  y = 0.5, w = 0.5,  h = 0.5 },
]

[[workspace]]
name = "Code"
layout = "code-3"
```

`[[layout]]` follows `[[workspace]]`'s shape. The editor's **Copy as TOML** produces exactly this
block, which is the whole sharing and import story (see §11).

## 4. Representation and geometry

### 4.1 Types

```swift
// SpacialShellProtocol — the only layout type on the leaf target after #11
public struct LayoutID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from d: Decoder) throws { rawValue = try d.singleValueContainer().decode(String.self) }
    public func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(rawValue) }
    public static let maximize: LayoutID = "maximize", split: LayoutID = "split",
                      column: LayoutID = "column", half: LayoutID = "half", grid: LayoutID = "grid"
}

// SpacialShellKit
public enum BuiltinLayout: String, CaseIterable, Sendable { case maximize, split, column, half, grid }

public struct LayoutZone: Codable, Hashable, Sendable { public var x, y, w, h: Double }

public struct LayoutDef: Codable, Hashable, Sendable, Identifiable {
    public enum Body: Codable, Hashable, Sendable { case builtin(BuiltinLayout), zones([LayoutZone]) }
    public var id: LayoutID
    public var name: String          // what the popover, menu, tooltip and Hint show
    public var symbol: String?       // SF Symbol; nil → zone glyph
    public var body: Body
    public var isBuiltin: Bool { if case .builtin = body { true } else { false } }
}

public struct LayoutCatalogue: Sendable, Equatable {
    public let all: [LayoutDef]      // built-ins first, then config order, then editor order
    public let bar: [LayoutID]       // ≤ 8, filtered to ids that resolve
    public subscript(id: LayoutID) -> LayoutDef? { get }
    public func resolve(_ id: LayoutID, fallback: LayoutID) -> (def: LayoutDef, resolved: Bool)
    public func next(after id: LayoutID) -> LayoutID          // cycleLayout: the bar ring
    public static let builtins: LayoutCatalogue
    public init(config: Config)      // config is already Settings.effective's output
}
```

`LayoutCatalogue` rides in the value the reconciler already receives:

```swift
public struct LayoutConfig: Sendable, Equatable {
    public var gap: CGFloat
    public var layouts: LayoutCatalogue = .builtins      // new; default keeps every test compiling
}
```

All three `Reconciler.desired` call sites in `WorldStore`, including #77's `predictedSwitches`,
already construct `LayoutConfig` from `config`. They get the catalogue in one place, so the
prefetched prediction can never disagree with the real switch about a layout.

### 4.2 Zone → frame

For the rect `R` the reconciler already computes (after insets, outer gap and the height −1) and
gap `g`:

```
frame.x = R.minX + zone.x · (R.width  + g)      frame.width  = zone.w · (R.width  + g) − g
frame.y = R.minY + zone.y · (R.height + g)      frame.height = zone.h · (R.height + g) − g
```

Each zone owns a `g`-wide gutter at its trailing edge, and the rect's own trailing gutter is the
outer gap. For `column` at n (zone i = `x: i/n, w: 1/n`), this gives `width = (W − (n−1)g)/n` and
`x = i(W+g)/n`, which is `LayoutEngine.columns` term for term. The same holds for `rows`, for
`half`, and for `grid` when its last row is full. The #9 tests are exact equalities:
a 3-zone column set == `.column` at 3, a 2×2 set == `.grid` at 4, and a half-shaped 4-zone set ==
`.half` at 4, for random rects and gaps.

### 4.3 The engine, with #54

The #54 page arithmetic is lifted out of the loop so both bodies share it verbatim:

```swift
public static func frames(_ def: LayoutDef, count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
    switch def.body {
    case .builtin(let b):
        return frames(b, count: count, focused: focused, in: rect, gap: gap)   // today's function, unchanged
    case .zones(let zones):
        guard count > 0 else { return [] }
        let usable = zones.map { rect(for: $0, in: rect, gap: gap) }.filter(fits)   // #54 floor, per zone
        let f = min(max(focused, 0), count - 1)
        guard !usable.isEmpty else { var out = [CGRect?](repeating: nil, count: count); out[f] = rect; return out }
        let k = min(count, usable.count)
        let start = min(f / k * k, count - k)                                   // #54 paging, same formula
        var out = [CGRect?](repeating: nil, count: count)
        for i in 0..<k { out[start + i] = usable[i] }
        return out
    }
}

/// Capacity at this rect: how many windows the layout can show at once. Drives moveWindow's
/// promotion and the switcher tooltip ("shows 4 of 6").
public static func capacity(_ def: LayoutDef, count: Int, in rect: CGRect, gap: CGFloat) -> Int
```

The properties M1 §5 and #54 state still hold for every body:
- the function is pure and total;
- entry `i` is tiled window `i`;
- `nil` means parked;
- no frame is smaller than 120 × 80 unless the rect itself is;
- focus inside a page moves nothing;
- only crossing a page edge flips the page.

Property tests (`PropertyTests`, `i6NoInvisibleWindows`, `layoutsNeverOverlap`) extend to
random catalogues of built-ins plus random legal zone sets.

## 5. The five built-ins

**They are catalogue rows with generator bodies.** Each is a `LayoutDef` with its existing id, its
existing symbol (moved off `WorkspacePanelView.symbol(for:)` onto the def) and `body = .builtin(_)`.
The switcher, popover, menu, `state.layouts`, `cycleLayout` and the editor list see five
ordinary rows with no special case. Only the engine's `.builtin` branch knows they are code.

| Built-in | Why it cannot be a fixed zone list |
|---|---|
| `maximize` | One slot at the *focus* index; everything else parks. |
| `split` | Two slots chosen relative to the focus (its right neighbour, or its left one when last). |
| `column` | n slots for n windows. |
| `half` | 1 + (n−1); the right-hand stack's row height depends on n. |
| `grid` | `cols = ⌈√n⌉`, `rows = ⌈n/cols⌉`; the last row's cells widen. |

A count-dependent layout expressed *as data* would need parametric zones: a zone template that
repeats per window, plus a rule for the remainder. That is a small language, it is only needed if a
user asks to draw a count-dependent layout, and nobody has. **Deferred** (§11). The escape hatch
exists: `Body` is an enum, so a `.template(…)` case can be added later without touching ids,
persistence or the wire.

The user-facing consequence, stated in the editor: *built-in layouts adapt to the number of
windows; drawn layouts have a fixed number of zones and page when there are more windows.*

## 6. Wire, `spacialctl`, and ids nobody knows

**Out (the `state` verb).** `WorkspaceDTO.layout` keeps its type (`String`) and carries the stored
id, *even when it does not resolve*, so a client sees what the user chose. `WireState` gains:

```swift
public struct LayoutDTO: Codable, Equatable, Sendable {
    public var id: String, name: String, symbol: String?, builtin: Bool, zones: Int?   // zones nil for builtins
}
public var layouts: [LayoutDTO]   // the catalogue, in `all` order; bar membership is UI-only
```

`capabilities` gains `"layouts"`, and `v` stays **2**: every change is additive. A client detects an
unresolved workspace layout by its absence from `layouts`, so there is no per-workspace flag.

**Clients that have never heard of an id.** Raycast's `spacialctl.ts` types `layout: string` and
`switch.tsx` prints it as a subtitle, so an unknown id shows as its raw id. That is correct
degradation with zero change, matching the M2 ruling ("unknown layout degrades with warn").
`spacialctl state` prints JSON verbatim. `ShellSnapshot.WorkspaceRow.layout` (not yet emitted)
is retyped to `LayoutID` in #9, before anything can decode it strictly.

**In (commands).** No existing verb carries a layout id. `run cycle-layout` is unchanged apart from
cycling the bar set. If Q5 is accepted, #10 adds `spacialctl set-layout <id> [--workspace <uuid>]`,
which sends IPC `set-layout {layout, workspace?}` → `.setWorkspaceLayout(UUID, LayoutID)`. An id the
catalogue does not know gets `ok:false`, `unknown layout "foo" (known: maximize, split, …)`, exit 1.
This is **the opposite of decode on purpose**: a live caller can be corrected, and user data on
disk must never be thrown away for a typo.

**Downgrade.** A pre-#9 build reading a `state.json` with a custom id throws, as it does today for
any unknown value, and starts with fresh workspaces. That cannot be fixed retroactively. It is
documented in the #9 PR and in `docs/config.md`. Upgrade is lossless because the built-in strings
never change.

## 7. The switcher at twenty layouts

Today the switcher is `ForEach(Layout.allCases)`: five 24 pt glyphs on a 34 pt bar that also holds
every window tab. Twenty layouts would take 480 pt.

```
[ tabs …                              ] [▭][▯▯][▯▯▯][◧][▦][⌗*][⋯]
                                          └──── bar set (≤ 8) ───┘ │  └ menu: all layouts ✓ current,
                                                   active, if outside ┘    "Edit layouts…"
```

- **Bar set:** `catalogue.bar`, at most **8**, ordered, and by default the five built-ins. It comes
  from `layout-bar` in the file or `layoutBar` in settings, and is toggled per layout in the popover.
- **Active outside the set:** drawn after the set, before `⋯`, so the bar always shows what is
  active.
- **`⋯`:** an `NSMenu` of every layout, with its glyph and name and a checkmark on the current one.
  Separators divide built-ins, file layouts and drawn layouts. "Edit layouts…" is last.
- **`Fn+Space`** cycles the bar set, so the bar is an honest picture of the keyboard.
- **Unresolved:** the fallback's glyph with an `exclamationmark.triangle` badge, and the tooltip
  *layout "code-3" is missing — using maximize*.

The cog is unchanged in position and opens the §2 popover. The popover lists every layout **by name**
(#15's "choose by name, not by guessing a glyph") and is the non-keyboard way to reach all twenty.

## 8. A workspace whose layout was deleted

1. The workspace keeps `layout = "code-3"`. `state.json` is not touched.
2. `resolve` → `config.defaultLayout` → `maximize`. It is logged once per id.
3. The switcher shows the badge (§7), and the Hint and tooltip name the missing id.
4. Restoring the layout (Reset, re-pasting the `[[layout]]` block, or restoring `settings.json`)
   restores the workspace with no further action.
5. Choosing any layout on that workspace replaces the dangling id normally.
6. The delete confirmation says *3 workspaces use this layout; they will use maximize until you
   choose another.*

If `default-layout` itself names a deleted layout, new workspaces start with the dangling id and
resolve to `maximize`. The badge makes that visible, and the popover's "Set as default" fixes it.

## 9. Motion (#64/#67/#77)

`Transition.moves` is **frame-based**. It diffs `ShownRow.frames` before and after, so it never
knows which layout produced them. Layouts as data need no planner change for:

- **switching layout on a workspace:** focus and workspace are unchanged, so the delta is zero.
  Windows on screen in both morph from frame to frame. Windows the new layout parks disappear, as
  they do today with `split → maximize`;
- **focus inside a page:** no frame changes, so there are no moves, as #54 intends;
- **workspace switches:** a vertical slide of one viewport, independent of layout.

**One change is required: page flips.** `direction` slides a tab switch by `(j − i) × (focused
width + gap)`. For a row of equal columns that is a strip scroll. For a zone page, such as a 2×2
or a wide zone next to a narrow one, the leaving and arriving windows would slide by less than a
page and cross each other inside the clip. The rule becomes:

```swift
// Transition.direction, tab-switch branch
if Set(before.frames.keys).isDisjoint(with: after.frames.keys) {        // page flip: one whole page
    return CGVector(dx: j > i ? -(viewport.width + gap) : viewport.width + gap, dy: 0)
}
let slot = (after.frames[new]?.width).map { $0 + gap } ?? viewport.width  // strip scroll: unchanged
return CGVector(dx: -CGFloat(j - i) * slot, dy: 0)
```

A page flip slides one whole page, and a strip scroll is unchanged. This also fixes built-in
`column` pages under #54, which have the same crossing. It lands in #9 with a `TransitionTests`
case, and is the only motion change. The #77 prefetch needs nothing beyond §4.1's catalogue in
`LayoutConfig`, because its prediction runs the real reconciler.

## 10. M1/M2 rulings this re-opens

| Ruling | Source | Change | Justification |
|---|---|---|---|
| `Layout` is a closed, `CaseIterable` enum of five | M1 §4.1 (`enum Layout`) | Retired in #11. `LayoutID` (Protocol) + `LayoutDef`/`BuiltinLayout`/catalogue (Kit). | This is the ticket. Closedness is the one fact that makes user layouts impossible; nothing else in M1 depends on it. |
| `Layout.frames(count:focused:in:gap:)` over five | M1 §5 | Takes a `LayoutDef`; the built-in branch is today's code verbatim | The stated properties (pure, total, index `i`, `nil` = parked) and #54's floor are preserved exactly. |
| `default-layout` / `[[workspace]] layout` take one of five names | M1 §9, `docs/config.md` | Any id; `[[layout]]` and `layout-bar` added | A config that can reference a layout but not define one does not travel between machines. |
| The Protocol leaf holds `Layout` | M2 Decisions, "Target graph" | Protocol holds `LayoutID` only | Geometry is not a wire concern; `spacialctl` still links Protocol only. |
| `.setWorkspaceLayout(UUID, Layout)`, and `setLayout` in the verb list | M2 Decisions, "New verbs" | Payload becomes `LayoutID` | The distinct-base-name rule that ruling protects is untouched. |
| `ShellSnapshot.WorkspaceRow.layout: Layout` | M2 Decisions, "Snapshot" | `LayoutID`, plus `layouts` beside `capabilities` | Not yet emitted, so it is free to change now and expensive later. |
| Layout icons are the five SF Symbols | M2 design tokens, "Icons" | Built-ins unchanged; custom layouts draw a zone glyph | Twenty layouts need twenty distinguishable glyphs. `docs/design-system.md` gains the glyph as a component. |
| Switcher = the five, click → `.setLayout(next)` | M2 T19 `LayoutSwitcher`, `WorkspacePanelView` | Bar set + active + `⋯` menu; cog → popover (#15) | The cog was always "the way to everything else about them". |
| **Not re-opened:** reconciler owns geometry; insets are data; parking is the single hiding mechanism; the app never writes `config.toml`; settings are "nil = the file decides"; the rail shows apps, not arrangement (#61) | M1 §5, M2 Decisions, `Settings.swift`, #61 | — | Zones are data fed to the same reconciler, and the editor writes `settings.json` only. |

## 11. Migration plan

**#9: expand. Nothing user-visible; the catalogue holds exactly the five.**

1. Protocol: `LayoutID` (bare-string codec, static built-ins). Codec tests cover round-tripping each
   built-in byte-for-byte against the enum's encoding, and decoding a string no build has seen.
2. Kit: `typealias BuiltinLayout = SpacialShellProtocol.Layout` for now (new code uses the final
   name), plus `LayoutZone`, `LayoutDef`, `LayoutCatalogue` (merge, built-in shadowing refused,
   GUI-wins precedence, bar ≤ 8, `next(after:)`, the resolve chain) and their tests.
3. Engine: `frames(LayoutDef…)`, `rect(for:)` and `capacity`. Tests cover the §4.2 **exact
   equalities**, zone paging (count > zones, focus at page edges), the per-zone floor (a 6-zone set
   on a 1280 pt rect), and capacity 0 → whole rect. Property tests take random catalogues.
4. Retype storage to `LayoutID`: `Workspace.layout`, `World.defaultLayout`, `Config.defaultLayout`,
   `WorkspaceSeed.layout`, `PersistedState`, `.setWorkspaceLayout`, `ShellUIState.layout`,
   `ShellSnapshot`. The static members keep `== .maximize` compiling. Add a test that
   `layout = "nonsense"` no longer rejects `config.toml` or `state.json`.
5. Config: `[[layout]]` and `layout-bar` decoding. `SettingsOverrides.layouts/layoutBar/
   defaultLayout`, lossily decoded. Quarantine of an unreadable `settings.json` (§3.2).
6. `LayoutConfig.layouts`. The reconciler resolves through it, and so do the three `WorldStore` call
   sites.
7. `cycleLayout` → `catalogue.next(after:)`. The `moveWindow` promotion becomes the capacity rule.
   `Hint.after` uses `def.name`. `WireState.layouts` plus the `"layouts"` capability.
8. `Transition.direction` page-flip rule (§9) with a `TransitionTests` case.

Exit: the five on the bar, identical tiling, no story-snapshot changes, and `swift test` counts in
the PR. The `Layout` enum still exists, now used only by the switcher's `allCases` and
`symbol(for:)` and as `BuiltinLayout`'s backing.

**#10: the editor, absorbing #15.** The cog → popover (list by name, active marked, Set as default,
bar toggles, New / Edit…), from the non-activating panel. Then:
- the editor window, with a canvas over a pure-Kit `GridEditor` (presets, splitter derivation from
  zone edges, 1/48 snapping, merge legality, overlap rejection, row-major numbering, each with
  tests);
- name, save to `settings.json`, duplicate, delete with usage count, Reset for overridden file
  layouts, and Copy as TOML;
- the switcher bar set, active-outside, `⋯` menu, unresolved badge and zone glyph;
- `set-layout` over IPC and `spacialctl` (Q5).

The switcher moves off `Layout.allCases` here, because it must show custom layouts. Stories cover
the popover, the editor, the switcher with 20 layouts, and the unresolved badge, in both
appearances. The PR carries an editor animation plus the overview loop (AGENTS.md).

**#11: contract.**
- Delete `SpacialShellProtocol.Layout`, the Kit typealias and `Layout.next`.
- `BuiltinLayout` becomes a real Kit enum (not Codable; `LayoutDef` encodes built-ins by id).
- `WorkspacePanelView.symbol(for:)` is gone; the symbol lives on the def.
- `docs/config.md` (`[[layout]]`, `layout-bar`, any id), `docs/ipc.md` (`layouts`, `set-layout`),
  `docs/keybindings.md` (`cycle-layout` cycles the bar) and the cheat sheet reach their final
  wording.

The "old file still loads" criterion holds by construction. The proof is a `config.toml` and
`state.json` fixture captured **before #9 starts**, decoded by the post-#11 build in a test.

*As landed (#11):* the enum, its Kit typealias, `Layout.next` and the `LayoutID(_: Layout)` bridge
are gone; `BuiltinLayout` is a Kit enum, and `LayoutDef` writes a built-in as its raw string. There
is no `docs/ipc.md`: the `state.layouts` / `set-layout` wording lives in `docs/config.md` beside
`[[layout]]`, and `spacialctl`'s own usage text. The cheat sheet's "Cycle layout" label needed no
change. The pre-#9 fixtures (config, state, wire, built-in frames golden) pass on the post-#11 build.

## 12. Changes from the 2026-09-12 draft

| Draft said | Now | Why |
|---|---|---|
| Editor output in a new `layouts.json`; `config.toml` wins | `settings.json`, GUI wins per id | This is `Settings.effective`'s shipped precedent, and it avoids a third store (§3.1). |
| Overflow: fill in order; the focused window takes the last zone and displaces its occupant | #54 paging with page = usable zones | #54 landed after the draft; one overflow rule for the engine. |
| A zone below the floor parks its window | The zone drops out of capacity for this rect | The same outcome, expressed as the page rule. |
| `LayoutDef` in Protocol | Kit; Protocol holds only `LayoutID` | `spacialctl` needs no geometry. |
| `list-layouts` verb; per-workspace `layoutResolved` | `state.layouts`; absence = unresolved | One round trip, one field. |
| Wire `v` stays 1 | `v` stays **2** | `WireState.v` is 2 today. |
| `spacialctl set-layout` / Raycast dropdown "exist" | They don't; `set-layout` is proposed for #10 (Q5) | This is what the code actually has. |
| Cog → settings window "Layouts" tab | Cog → popover; editor window for drawing | The #15 ruling (2026-09-24). |
| No motion section | §9 page-flip rule | #64/#67/#77 landed. |

## 13. Deferred

- **Parametric / template zones**, which would let `column` become data. Nobody has asked; `Body`
  can grow a case later.
- **A freeform, overlapping canvas** (FancyZones' Canvas editor). The issue asks for grids.
- **Drag a window onto a zone** (FancyZones' signature interaction). It needs `DragTap` (M2
  task 23, deferred). See Q3.
- **Per-app zone affinity.** It belongs with `[[float]]`/`[[tile]]` window rules, not geometry.
- **Importing a layout file.** Copy as TOML covers sharing.
- **Per-display / aspect-aware layouts** (Q1).

## 14. Open questions for the user

Each has a recommended default. Silence means the recommendation stands.

| # | Question | Recommended answer |
|---|---|---|
| Q1 | A layout drawn on a 32:9 ultrawide is odd on a laptop. Scope layouts per display or aspect? | **No.** Scale, and let the floor drop zones that get too small; paging covers the rest. Revisit if it bites. |
| Q2 | Fewer windows than zones: leave zones empty, or stretch? | **Leave them empty.** This is FancyZones' behaviour, and it is predictable. |
| Q3 | Is dragging a window onto a zone part of #10? | **No.** Make it a separate ticket after #10. It needs `DragTap` and would double #10. |
| Q4 | Is the bar set capped at a fixed 8, or "as many as fit"? | **A fixed 8.** It is predictable, and Fn+Space stays a short ring. |
| Q5 | Should `spacialctl set-layout <id>` and IPC `set-layout` ship in #10? | **Yes.** It is about 20 lines, refuses unknown ids with exit 1, and makes custom layouts scriptable from Raycast. |
| Q6 | Should there be an optional "primary zone" where the focused window always goes? | **No.** It re-seats windows on every focus change and fights #54 paging. Defer. |
| Q7 | Precedence: the editor's `settings.json` wins over `config.toml` per id (a flip from the draft). Agree? | **Yes.** It matches every other settings-window key, and Reset returns to the file. |
| Q8 | Should the delete sheet offer "move those workspaces to…"? | **No.** Fallback plus badge is enough and costs nothing extra. |

## 15. Verification

- `swift test` is green at every slice, and #9 changes no story snapshot.
- The §4.2 exact-equality tests are the single most important tests. They are what makes "built-ins
  are catalogue rows" and "zones use the same gap math" true rather than approximately true.
- The property suite runs random catalogues through `Reconciler.desired`. It asserts I6 (every
  active, non-hidden window is framed inside its display or parked with a tab), the 120 × 80
  floor, and no overlap from any legal zone set.
- The pre-#9 `config.toml`/`state.json` fixtures decode on the post-#11 build.
- A `settings.json` with one malformed layout loads the rest. An unreadable one is quarantined, not
  overwritten.
- The PR media follows AGENTS.md. #9 and #11 show `swift test` counts plus a before/after of
  unchanged tiling. #10 shows the editor in motion plus the overview loop.
